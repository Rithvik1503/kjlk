import Combine
import Foundation
import SwiftUI

/// The one object the UI observes.
///
/// Holds the session state, the readings for the selected range, and the derived summaries.
/// Views read; everything that mutates goes through a method here.
@MainActor
final class AuraStore: ObservableObject {
    // MARK: - Published state

    enum Phase: Equatable {
        case launching
        case needsConfiguration
        case needsSignIn
        case ready
    }

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var latest: Reading?
    @Published private(set) var status: RoomStatus = .unknown
    @Published private(set) var summaries: [MetricKind: MetricSummary] = [:]
    @Published private(set) var devices: [String] = []

    @Published private(set) var isRefreshing = false
    @Published private(set) var isLiveConnected = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    /// True while showing data restored from disk that hasn't been refreshed yet.
    @Published private(set) var isShowingCachedData = false

    @Published var range: TimeRange {
        didSet {
            guard range != oldValue else { return }
            preferences.preferredRange = range
            Task { await refresh() }
        }
    }

    @Published var accountEmail: String?

    // MARK: - Dependencies

    let preferences: Preferences

    private let client: SupabaseClient
    private let realtime: RealtimeChannel
    private let cache: ReadingCache

    private var realtimeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Polls are a safety net under Realtime, and the only source when the socket is down.
    private var pollInterval: TimeInterval { isLiveConnected ? 300 : 60 }

    /// `Preferences` is main-actor isolated, and a default argument is evaluated in a
    /// nonisolated context, so it can't be constructed in the signature. Passing nil and
    /// building it in the body — which *is* isolated — gives the same ergonomics.
    init(
        preferences: Preferences? = nil,
        client: SupabaseClient = SupabaseClient(),
        realtime: RealtimeChannel = RealtimeChannel(),
        cache: ReadingCache = ReadingCache()
    ) {
        let preferences = preferences ?? Preferences()

        self.preferences = preferences
        self.client = client
        self.realtime = realtime
        self.cache = cache
        self.range = preferences.preferredRange

        // Views observe the store, not `Preferences`. Forwarding the signal means switching to
        // Fahrenheit or nudging the calibration offset redraws every screen that shows a value,
        // without each of them having to observe a second object.
        // `Preferences` is main-actor isolated, so this publisher only ever fires on the main
        // actor — stating that explicitly beats relying on how Combine's non-Sendable closure
        // inherits isolation.
        preferences.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Launch

    func start() async {
        await client.restore()

        guard await client.isConfigured else {
            phase = .needsConfiguration
            return
        }
        guard await client.isSignedIn else {
            phase = .needsSignIn
            return
        }

        accountEmail = await client.currentSession?.email
        phase = .ready

        loadCachedReadings()
        await refresh()
        startLiveUpdates()
        startPolling()
    }

    /// Shows the last session's data immediately, so the first frame is never empty.
    private func loadCachedReadings() {
        guard readings.isEmpty, let snapshot = cache.load() else { return }
        guard snapshot.deviceID == preferences.selectedDeviceID else { return }

        let cutoff = range.start()
        let recent = snapshot.readings.filter { $0.recordedAt >= cutoff }
        guard !recent.isEmpty else { return }

        apply(readings: recent)
        isShowingCachedData = true
        lastUpdated = snapshot.savedAt
    }

    // MARK: - Configuration and auth

    func configure(urlString: String, anonKey: String) async throws {
        guard let config = SupabaseConfig(rawURL: urlString, anonKey: anonKey) else {
            throw SupabaseError.transport("That doesn't look like a Supabase URL.")
        }
        await client.configure(config)

        // Pointing at a new project clears any session, so this is normally the sign-in path.
        // It can still land on `.ready` when the same project is re-entered, and that case
        // has to bring the data loop up itself — nothing else will.
        let signedIn = await client.isSignedIn
        guard signedIn else {
            phase = .needsSignIn
            return
        }

        phase = .ready
        await refresh()
        startLiveUpdates()
        startPolling()
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.signIn(email: email, password: password)
        accountEmail = session.email
        phase = .ready

        await refresh()
        startLiveUpdates()
        startPolling()
    }

    /// Returns false when Supabase requires the address to be confirmed before signing in.
    func signUp(email: String, password: String) async throws -> Bool {
        let session = try await client.signUp(email: email, password: password)
        guard let session else { return false }

        accountEmail = session.email
        phase = .ready

        await refresh()
        startLiveUpdates()
        startPolling()
        return true
    }

    func sendPasswordReset(email: String) async throws {
        try await client.sendPasswordReset(email: email)
    }

    func signOut() async {
        stopLiveUpdates()
        stopPolling()
        refreshTask?.cancel()

        await client.signOut()
        cache.clear()

        readings = []
        latest = nil
        summaries = [:]
        status = .unknown
        devices = []
        lastUpdated = nil
        errorMessage = nil
        isShowingCachedData = false
        accountEmail = nil
        phase = .needsSignIn
    }

    func disconnectProject() async {
        await signOut()
        await client.clearConfiguration()
        phase = .needsConfiguration
    }

    // MARK: - Loading

    /// Reloads the current range. Safe to call from anywhere; overlapping calls collapse.
    func refresh() async {
        refreshTask?.cancel()

        // Unwrapped rather than optional-chained: `await self?.performRefresh()` would make
        // the closure return `Void?`, giving a `Task<Void?, Never>`.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard phase == .ready else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let end = Date()
        let start = range.start(from: end)
        let deviceID = preferences.selectedDeviceID

        do {
            let fetched = try await client.readings(
                from: start,
                to: end,
                deviceID: deviceID,
                limit: range.rowLimit
            )
            guard !Task.isCancelled else { return }

            apply(readings: fetched)
            lastUpdated = Date()
            isShowingCachedData = false
            errorMessage = nil
            cache.save(readings: fetched, deviceID: deviceID)

            await refreshDeviceList()
        } catch is CancellationError {
            return
        } catch let error as SupabaseError {
            guard !Task.isCancelled else { return }
            if case .notSignedIn = error {
                await handleSessionExpiry()
            } else {
                // Keep whatever is on screen; a failed refresh shouldn't blank the dashboard.
                errorMessage = error.localizedDescription
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshDeviceList() async {
        guard devices.isEmpty else { return }
        // The device list is a nicety — a project without the helper view still works.
        devices = (try? await client.knownDevices()) ?? []
    }

    func selectDevice(_ deviceID: String?) async {
        guard preferences.selectedDeviceID != deviceID else { return }
        preferences.selectedDeviceID = deviceID
        cache.clear()
        readings = []
        latest = nil
        summaries = [:]
        status = .unknown
        await refresh()
    }

    private func handleSessionExpiry() async {
        stopLiveUpdates()
        stopPolling()
        accountEmail = nil
        errorMessage = nil
        phase = .needsSignIn
    }

    // MARK: - Derived state

    private func apply(readings newReadings: [Reading]) {
        readings = newReadings
        latest = newReadings.last

        var built: [MetricKind: MetricSummary] = [:]
        for metric in MetricKind.allCases {
            built[metric] = MetricSummary.make(metric: metric, readings: newReadings)
        }
        summaries = built
        status = RoomStatus.evaluate(newReadings.last)
    }

    /// Bucketed points for a chart of `metric` over the current range.
    func trend(for metric: MetricKind) -> [TrendPoint] {
        let end = lastUpdated ?? Date()
        return Trend.buckets(
            from: readings,
            metric: metric,
            interval: range.bucket,
            start: range.start(from: end),
            end: end
        )
    }

    var isStale: Bool {
        guard let latest else { return false }
        // The firmware uploads once a minute; fifteen minutes of silence means something is wrong.
        return Date().timeIntervalSince(latest.recordedAt) > 900
    }

    // MARK: - Live updates

    func startLiveUpdates() {
        guard preferences.liveUpdatesEnabled, phase == .ready, realtimeTask == nil else { return }

        realtimeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            guard
                let config = await self.client.config,
                let token = try? await self.client.validToken()
            else { return }

            let stream = await self.realtime.start(config: config, accessToken: token)
            for await event in stream {
                guard !Task.isCancelled else { break }
                self.handle(event)
            }
        }
    }

    func stopLiveUpdates() {
        realtimeTask?.cancel()
        realtimeTask = nil
        isLiveConnected = false
        Task { [realtime] in await realtime.stop() }
    }

    private func handle(_ event: RealtimeChannel.Event) {
        switch event {
        case .connected:
            isLiveConnected = true

        case .disconnected:
            isLiveConnected = false

        case let .inserted(reading):
            guard matchesSelectedDevice(reading) else { return }
            insert(reading)
        }
    }

    private func matchesSelectedDevice(_ reading: Reading) -> Bool {
        guard let selected = preferences.selectedDeviceID, !selected.isEmpty else { return true }
        return reading.deviceID == selected
    }

    /// Merges a pushed row into the in-memory series, keeping it sorted and de-duplicated.
    private func insert(_ reading: Reading) {
        guard reading.recordedAt >= range.start() else { return }
        guard !readings.contains(where: { $0.id == reading.id }) else { return }

        var updated = readings
        if let last = updated.last, reading.recordedAt >= last.recordedAt {
            updated.append(reading)
        } else {
            let index = updated.firstIndex { $0.recordedAt > reading.recordedAt } ?? updated.count
            updated.insert(reading, at: index)
        }

        // Drop anything that has fallen out of the window as time has moved on.
        let cutoff = range.start()
        updated.removeAll { $0.recordedAt < cutoff }

        apply(readings: updated)
        lastUpdated = Date()
        isShowingCachedData = false
        cache.save(readings: updated, deviceID: preferences.selectedDeviceID)
    }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Read the interval each time around: it halves once Realtime connects.
                let interval = self.pollInterval

                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Called when the app comes back to the foreground.
    func handleForeground() {
        guard phase == .ready else { return }
        Task {
            await refresh()
            startLiveUpdates()
            startPolling()
        }
    }

    /// Called on backgrounding — the socket would be torn down by the system anyway.
    func handleBackground() {
        stopLiveUpdates()
        stopPolling()
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - History

    /// Every reading on the calendar day containing `date`, in the device's local time zone.
    func readings(forDayContaining date: Date) async throws -> [Reading] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return try await client.readings(
            from: start,
            to: end.addingTimeInterval(-1),
            deviceID: preferences.selectedDeviceID,
            limit: 5000
        )
    }

    /// Days in the month containing `date` that have at least one reading, for the calendar dots.
    func daysWithData(inMonthOf date: Date) async throws -> Set<Date> {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        return try await client.daysWithData(in: interval, deviceID: preferences.selectedDeviceID)
    }
}

// MARK: - Convenience for previews

extension AuraStore {
    /// An in-memory store filled with plausible data, for SwiftUI previews and screenshots.
    static func preview() -> AuraStore {
        let store = AuraStore()
        store.phase = .ready
        store.apply(readings: Reading.sampleSeries())
        store.lastUpdated = Date()
        store.isLiveConnected = true
        store.accountEmail = "you@example.com"
        return store
    }
}
