import Foundation

/// Everything the app does over the network, in one place.
///
/// An actor so that two screens refreshing at once can't both decide the token is stale and
/// fire off competing refresh calls — `validToken()` funnels them into a single in-flight task.
actor SupabaseClient {
    private(set) var config: SupabaseConfig?
    private(set) var session: SupabaseSession?

    private let urlSession: URLSession
    private var refreshTask: Task<SupabaseSession, any Error>?

    private static let configKey = SharedKeys.config
    private static let sessionKey = SharedKeys.session

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Lifecycle

    /// Loads whatever was saved last run, falling back to the bundled `Config.plist`.
    func restore() {
        if let saved = Keychain.decode(SupabaseConfig.self, for: Self.configKey) {
            config = saved
        } else if let bundled = SupabaseConfig.bundled {
            // Persisted rather than just held: `Config.plist` ships in the app bundle, and the
            // widget extension is a bundle of its own that can't see it. The keychain is the
            // one place both processes read.
            config = bundled
            Keychain.encode(bundled, for: Self.configKey)
        }
        session = Keychain.decode(SupabaseSession.self, for: Self.sessionKey)
    }

    func configure(_ newConfig: SupabaseConfig) {
        // Pointing at a different project invalidates any session we were holding.
        if let existing = config, existing.url != newConfig.url {
            session = nil
            Keychain.remove(Self.sessionKey)
        }
        config = newConfig
        Keychain.encode(newConfig, for: Self.configKey)
    }

    func clearConfiguration() {
        config = nil
        session = nil
        Keychain.remove(Self.configKey)
        Keychain.remove(Self.sessionKey)
    }

    var isConfigured: Bool { config != nil }
    var isSignedIn: Bool { session != nil }
    var currentSession: SupabaseSession? { session }

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let body: [String: String] = ["email": email, "password": password]
        let newSession: SupabaseSession = try await authRequest(
            path: "token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: body
        )
        store(newSession)
        return newSession
    }

    /// Creates an account. Supabase may or may not return a session, depending on whether the
    /// project requires email confirmation.
    func signUp(email: String, password: String) async throws -> SupabaseSession? {
        let body: [String: String] = ["email": email, "password": password]
        let data = try await rawAuthRequest(path: "signup", query: [], body: body)

        guard let newSession = try? decoder.decode(SupabaseSession.self, from: data) else {
            return nil // Confirmation required — no session yet, and that's not an error.
        }
        store(newSession)
        return newSession
    }

    func signOut() async {
        if let config, let session {
            // Best effort — a failure here still signs the user out locally.
            var request = URLRequest(url: config.authURL.appendingPathComponent("logout"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        session = nil
        refreshTask = nil
        Keychain.remove(Self.sessionKey)
    }

    func sendPasswordReset(email: String) async throws {
        _ = try await rawAuthRequest(path: "recover", query: [], body: ["email": email])
    }

    /// Returns a usable access token, refreshing first if the current one is close to expiry.
    func validToken() async throws -> String {
        guard let session else { throw SupabaseError.notSignedIn }
        guard session.isExpired else { return session.accessToken }

        if let existing = refreshTask {
            return try await existing.value.accessToken
        }

        let task = Task<SupabaseSession, any Error> { [refreshToken = session.refreshToken] in
            try await self.performRefresh(refreshToken: refreshToken)
        }
        refreshTask = task

        defer { refreshTask = nil }
        do {
            return try await task.value.accessToken
        } catch {
            // A rejected refresh token means the session is gone for good. `error` is
            // `any Error` here, so it has to be cast before the case pattern applies.
            if let supabaseError = error as? SupabaseError,
               case let .server(status, _) = supabaseError,
               status == 400 || status == 401 {
                self.session = nil
                Keychain.remove(Self.sessionKey)
                throw SupabaseError.notSignedIn
            }
            throw error
        }
    }

    private func performRefresh(refreshToken: String) async throws -> SupabaseSession {
        let refreshed: SupabaseSession = try await authRequest(
            path: "token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken]
        )
        store(refreshed)
        return refreshed
    }

    private func store(_ newSession: SupabaseSession) {
        session = newSession
        Keychain.encode(newSession, for: Self.sessionKey)
    }

    // MARK: - Readings

    /// Readings in `start...end`, oldest first.
    ///
    /// `limit` guards against a month of 20-second samples arriving all at once; when it bites
    /// we take the newest rows, because recent detail matters more than ancient detail.
    func readings(
        from start: Date,
        to end: Date,
        deviceID: String?,
        limit: Int
    ) async throws -> [Reading] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: Self.readingColumns),
            URLQueryItem(name: "recorded_at", value: "gte.\(PostgresDate.string(from: start))"),
            URLQueryItem(name: "recorded_at", value: "lte.\(PostgresDate.string(from: end))"),
            URLQueryItem(name: "order", value: "recorded_at.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let deviceID, !deviceID.isEmpty {
            query.append(URLQueryItem(name: "device_id", value: "eq.\(deviceID)"))
        }

        let rows: [Reading] = try await restGet(table: "readings", query: query)
        return rows.sorted { $0.recordedAt < $1.recordedAt }
    }

    func latestReading(deviceID: String?) async throws -> Reading? {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: Self.readingColumns),
            URLQueryItem(name: "order", value: "recorded_at.desc"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        if let deviceID, !deviceID.isEmpty {
            query.append(URLQueryItem(name: "device_id", value: "eq.\(deviceID)"))
        }

        let rows: [Reading] = try await restGet(table: "readings", query: query)
        return rows.first
    }

    /// Device IDs that have ever reported, newest first. Backed by a view so the query stays cheap.
    func knownDevices() async throws -> [String] {
        struct Row: Decodable {
            let deviceID: String
            private enum CodingKeys: String, CodingKey { case deviceID = "device_id" }
        }

        let rows: [Row] = try await restGet(
            table: "device_summary",
            query: [
                URLQueryItem(name: "select", value: "device_id"),
                URLQueryItem(name: "order", value: "last_seen_at.desc"),
            ]
        )
        return rows.map(\.deviceID)
    }

    /// When this device first reported, which is as far back as any date picker should go.
    func firstReadingDate(deviceID: String?) async throws -> Date? {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "recorded_at"),
            URLQueryItem(name: "order", value: "recorded_at.asc"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        if let deviceID, !deviceID.isEmpty {
            query.append(URLQueryItem(name: "device_id", value: "eq.\(deviceID)"))
        }

        struct Row: Decodable {
            let recordedAt: String
            private enum CodingKeys: String, CodingKey { case recordedAt = "recorded_at" }
        }

        let rows: [Row] = try await restGet(table: "readings", query: query)
        return rows.first.flatMap { PostgresDate.parse($0.recordedAt) }
    }

    /// Per-day or per-month means of every sensor, aggregated by Postgres.
    ///
    /// Throws rather than returning empty when the function is missing, so the Trends screen
    /// can tell "no data yet" apart from "the migration hasn't been run".
    func metricBuckets(
        from start: Date,
        to end: Date,
        unit: String,
        timeZone: TimeZone,
        deviceID: String?
    ) async throws -> [MetricBucket] {
        var body: [String: String] = [
            "p_from": PostgresDate.string(from: start),
            "p_to": PostgresDate.string(from: end),
            "p_unit": unit,
            "p_tz": timeZone.identifier,
        ]
        if let deviceID, !deviceID.isEmpty {
            body["p_device"] = deviceID
        }

        let data = try await restPost(function: "aura_metric_buckets", body: body)
        do {
            return try JSONDecoder().decode([MetricBucket].self, from: data)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    /// The same buckets as `metricBuckets`, split by zone, for the Areas section.
    func zoneBuckets(
        from start: Date,
        to end: Date,
        unit: String,
        timeZone: TimeZone,
        deviceID: String?
    ) async throws -> [ZoneBucket] {
        var body: [String: String] = [
            "p_from": PostgresDate.string(from: start),
            "p_to": PostgresDate.string(from: end),
            "p_unit": unit,
            "p_tz": timeZone.identifier,
        ]
        if let deviceID, !deviceID.isEmpty {
            body["p_device"] = deviceID
        }

        let data = try await restPost(function: "aura_zone_buckets", body: body)
        do {
            return try JSONDecoder().decode([ZoneBucket].self, from: data)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    private static let readingColumns =
        "id,device_id,zone,recorded_at,co2_ppm,temperature_c,humidity_percent,light_lux"

    // MARK: - Request plumbing

    private func restPost(function: String, body: [String: String]) async throws -> Data {
        guard let config else { throw SupabaseError.notConfigured }
        let token = try await validToken()

        let url = config.restURL
            .appendingPathComponent("rpc")
            .appendingPathComponent(function)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 20

        return try await send(request)
    }

    private func restGet<T: Decodable>(table: String, query: [URLQueryItem]) async throws -> T {
        guard let config else { throw SupabaseError.notConfigured }
        let token = try await validToken()

        var components = URLComponents(
            url: config.restURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query

        guard let url = components?.url else {
            throw SupabaseError.transport("Couldn't build the request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data = try await send(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    private func authRequest<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        body: [String: String]
    ) async throws -> T {
        let data = try await rawAuthRequest(path: path, query: query, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SupabaseError.decoding(error.localizedDescription)
        }
    }

    private func rawAuthRequest(
        path: String,
        query: [URLQueryItem],
        body: [String: String]
    ) async throws -> Data {
        guard let config else { throw SupabaseError.notConfigured }

        var components = URLComponents(
            url: config.authURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }

        guard let url = components?.url else {
            throw SupabaseError.transport("Couldn't build the request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 20

        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw SupabaseError.transport(Self.message(for: error))
        } catch {
            throw SupabaseError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.transport("Unexpected response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data)
        }
        return data
    }

    /// Supabase reports failures in a few shapes; pull out whichever message is present.
    private static func error(status: Int, data: Data) -> SupabaseError {
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (payload?["error_description"] as? String)
            ?? (payload?["msg"] as? String)
            ?? (payload?["message"] as? String)
            ?? (payload?["error"] as? String)

        let code = (payload?["error_code"] as? String) ?? (payload?["code"] as? String)

        if code == "email_not_confirmed" {
            return .emailNotConfirmed
        }
        if status == 429 {
            return .rateLimited
        }

        // GoTrue reports a bad email/password pair as `invalid_grant`, or as a 400 whose
        // message mentions credentials. Anything else at 400/401 keeps its own wording —
        // "User already registered" should not read as a wrong password.
        let mentionsCredentials = message?.localizedCaseInsensitiveContains("credential") == true
        if status == 400 || status == 401, code == "invalid_credentials" || code == "invalid_grant" || mentionsCredentials {
            return .invalidCredentials
        }
        if status == 401 {
            return .server(status: status, message: message ?? "Not authorised.")
        }
        return .server(status: status, message: message)
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: "No internet connection."
        case .timedOut: "The server took too long to respond."
        case .cannotFindHost, .cannotConnectToHost: "Couldn't reach your Supabase project — check the URL."
        case .networkConnectionLost: "The connection dropped."
        default: error.localizedDescription
        }
    }

    private var decoder: JSONDecoder { JSONDecoder() }
}
