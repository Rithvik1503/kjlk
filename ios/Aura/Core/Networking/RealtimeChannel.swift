import Foundation

/// Live `INSERT` notifications for the readings table, over Supabase Realtime.
///
/// Realtime speaks the Phoenix channel protocol: join a topic, heartbeat every 25 seconds,
/// and receive `postgres_changes` frames. We hand the authenticated JWT over after joining so
/// row level security applies — without it the server accepts the socket but sends nothing.
///
/// This is an optimisation, never a requirement. The dashboard polls on its own schedule, so
/// a socket that never connects costs freshness, not correctness.
actor RealtimeChannel {
    enum Event: Sendable {
        case connected
        case disconnected
        case inserted(Reading)
    }

    private let topic = "realtime:aura-readings"

    private var socket: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?

    private var messageRef = 0
    private var reconnectAttempt = 0
    private var isStopping = false

    private var config: SupabaseConfig?
    private var accessToken: String?

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Opens the socket and returns the stream of events. Calling it again replaces the old stream.
    func start(config: SupabaseConfig, accessToken: String) -> AsyncStream<Event> {
        stopInternal()

        self.config = config
        self.accessToken = accessToken
        isStopping = false
        reconnectAttempt = 0

        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.continuation = continuation

        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }

        openSocket()
        return stream
    }

    /// Swaps in a refreshed JWT without tearing the socket down.
    func updateToken(_ token: String) {
        accessToken = token
        guard socket != nil else { return }
        send([
            "topic": topic,
            "event": "access_token",
            "payload": ["access_token": token],
            "ref": nextRef(),
        ])
    }

    func stop() {
        isStopping = true
        stopInternal()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Socket lifecycle

    private func stopInternal() {
        listenTask?.cancel()
        listenTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func openSocket() {
        guard let config, let url = config.realtimeURL else { return }

        let task = urlSession.webSocketTask(with: url)
        task.resume()
        socket = task

        join()
        startHeartbeat()
        listen()
    }

    private func join() {
        guard let accessToken else { return }

        // `postgres_changes` filters server-side, so we only wake for rows we can actually read.
        let payload: [String: Any] = [
            "config": [
                "broadcast": ["ack": false, "self": false],
                "presence": ["key": ""],
                "private": false,
                "postgres_changes": [
                    ["event": "INSERT", "schema": "public", "table": "readings"]
                ],
            ],
            "access_token": accessToken,
        ]

        let ref = nextRef()
        send([
            "topic": topic,
            "event": "phx_join",
            "payload": payload,
            "ref": ref,
            "join_ref": ref,
        ])
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { return }
                await self?.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() {
        send([
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": [:],
            "ref": nextRef(),
        ])
    }

    /// Captures the current socket so that a reconnect leaves this loop reading the old one,
    /// which then fails and exits instead of competing with the new loop.
    private func listen() {
        guard let socket else { return }

        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    await self?.handle(message)
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case let .string(text): data = text.data(using: .utf8)
        case let .data(raw): data = raw
        @unknown default: data = nil
        }

        guard
            let data,
            let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = frame["event"] as? String
        else { return }

        switch event {
        case "phx_reply":
            guard
                let payload = frame["payload"] as? [String: Any],
                let status = payload["status"] as? String
            else { return }
            if status == "ok", frame["topic"] as? String == topic {
                reconnectAttempt = 0
                continuation?.yield(.connected)
            }

        case "postgres_changes":
            guard
                let payload = frame["payload"] as? [String: Any],
                let body = payload["data"] as? [String: Any],
                body["type"] as? String == "INSERT",
                let record = body["record"] as? [String: Any],
                let encoded = try? JSONSerialization.data(withJSONObject: record),
                let reading = try? JSONDecoder().decode(Reading.self, from: encoded)
            else { return }
            continuation?.yield(.inserted(reading))

        case "phx_close", "phx_error":
            Task { [weak self] in await self?.scheduleReconnect() }

        default:
            break
        }
    }

    private func scheduleReconnect() async {
        guard !isStopping else { return }

        continuation?.yield(.disconnected)
        stopInternal()

        // Back off to a minute, so a project that is down doesn't get hammered.
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        let delay = min(pow(2.0, Double(reconnectAttempt)), 60)

        try? await Task.sleep(for: .seconds(delay))
        guard !isStopping else { return }
        openSocket()
    }

    private func send(_ object: [String: Any]) {
        guard
            let socket,
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return }

        socket.send(.string(text)) { _ in
            // A send failure surfaces on the receive loop as a socket error; nothing to do here.
        }
    }

    private func nextRef() -> String {
        messageRef += 1
        return String(messageRef)
    }
}
