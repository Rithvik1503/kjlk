import Combine
import Foundation
import SwiftUI

/// The one object the UI observes.
///
/// The app shows one day at a time. `selectedDate` is the day on screen; everything else is
/// derived from the readings of that day.
@MainActor
final class AuraStore: ObservableObject {
    enum Phase: Equatable {
        case launching
        case needsConfiguration
        case needsSignIn
        case ready
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var devices: [String] = []
    /// Mean temperature over the week before the selected day, or nil if unavailable.
    @Published private(set) var temperatureBaseline: Double?
    @Published var accountEmail: String?

    /// The day being shown. Views reload by keying a `.task` on this.
    @Published var selectedDate: Date = Date()

    // MARK: - Dependencies

    let preferences: Preferences

    private let client: SupabaseClient
    private let realtime: RealtimeChannel
    private let cache: ReadingCache
    private let calendar = Calendar.current

    private var realtimeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

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

        // Views observe the store, not `Preferences`, so the signal is forwarded. The
        // publisher only ever fires on the main actor, because `Preferences` is isolated to it.
        preferences.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    var isViewingToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    /// Most recent reading of the selected day.
    var current: Reading? { readings.last }

    /// The figure to show for a metric: the latest reading today, or the day's average for
    /// a past day.
    ///
    /// A past day has no "now", and its last reading — often taken at 3am — is a worse answer
    /// to "what was it like in here" than the average of the whole day.
    /// Today resolves per metric rather than from one row, because the sensors fail
    /// independently — a dropped BH1750 read shouldn't blank the light figure while the
    /// SCD40 in the same row is reporting fine.
    func value(for metric: MetricKind) -> Double? {
        guard isViewingToday else { return average(of: metric) }
        return readings.reversed().lazy.compactMap { $0.value(for: metric) }.first
    }

    /// Mean across the whole selected day, regardless of which day is being viewed.
    func dayAverage(of metric: MetricKind) -> Double? {
        average(of: metric)
    }

    private func average(of metric: MetricKind) -> Double? {
        let values = readings.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// How the selected day's temperature compares with the week before it.
    ///
    /// Falls back to describing the day on its own terms when there is no baseline — either
    /// too little history, or the project hasn't run the optional migration that adds the
    /// averaging function.
    var thermalComparison: String {
        guard let today = dayAverage(of: .temperature) else { return "No readings" }

        guard let baseline = temperatureBaseline else {
            return MetricKind.temperature.label(for: today)
        }

        let delta = today - baseline
        if abs(delta) < 0.5 { return "About usual" }
        return delta > 0 ? "Hotter than usual" : "Colder than usual"
    }

    /// Backdrop colour, driven by CO₂ — the metric that moves fastest and the one you can
    /// actually act on.
    var tint: Color {
        MetricKind.co2.tint(for: value(for: .co2))
    }

    var canGoForward: Bool {
        !isViewingToday
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
        await loadSelectedDay()
        startLiveUpdates()
        startPolling()
    }

    /// Shows the last session's readings immediately, so the first frame is never empty.
    private func loadCachedReadings() {
        guard readings.isEmpty, isViewingToday, let snapshot = cache.load() else { return }
        guard snapshot.deviceID == preferences.selectedDeviceID else { return }

        let today = calendar.startOfDay(for: Date())
        let recent = snapshot.readings.filter { $0.recordedAt >= today }
        guard !recent.isEmpty else { return }

        readings = recent
    }

    // MARK: - Date selection

    func step(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        // Never walk past today — there is nothing there.
        guard next <= Date() || calendar.isDateInToday(next) else { return }
        selectedDate = next
    }

    func goToToday() {
        selectedDate = Date()
    }

    // MARK: - Loading

    /// Loads the selected day. Overlapping calls collapse onto the latest one.
    func loadSelectedDay() async {
        loadTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        guard phase == .ready else { return }

        let day = selectedDate
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        // Drop readings from a different day before fetching, so stepping the date never shows
        // one day's number sitting under another day's label while the request is in flight.
        if let first = readings.first, !calendar.isDate(first.recordedAt, inSameDayAs: day) {
            readings = []
        }

        do {
            let fetched = try await client.readings(
                from: start,
                to: end.addingTimeInterval(-1),
                deviceID: preferences.selectedDeviceID,
                limit: 5000
            )
            guard !Task.isCancelled, calendar.isDate(day, inSameDayAs: selectedDate) else { return }

            readings = fetched
            errorMessage = nil

            if calendar.isDateInToday(day) {
                cache.save(readings: fetched, deviceID: preferences.selectedDeviceID)
            }
            await refreshDeviceList()
            await loadTemperatureBaseline(before: start)
        } catch is CancellationError {
            return
        } catch let error as SupabaseError {
            guard !Task.isCancelled else { return }
            if case .notSignedIn = error {
                await handleSessionExpiry()
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Averages the seven days before the one on screen, for the "than usual" comparison.
    private func loadTemperatureBaseline(before dayStart: Date) async {
        guard let weekEarlier = calendar.date(byAdding: .day, value: -7, to: dayStart) else { return }

        let baseline = await client.averageTemperature(
            from: weekEarlier,
            to: dayStart,
            deviceID: preferences.selectedDeviceID
        )
        guard !Task.isCancelled else { return }
        temperatureBaseline = baseline
    }

    private func refreshDeviceList() async {
        guard devices.isEmpty else { return }
        // A nicety — a project without the helper view still works.
        devices = (try? await client.knownDevices()) ?? []
    }

    func selectDevice(_ deviceID: String?) async {
        guard preferences.selectedDeviceID != deviceID else { return }
        preferences.selectedDeviceID = deviceID
        cache.clear()
        readings = []
        await loadSelectedDay()
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Auth

    func configure(urlString: String, anonKey: String) async throws {
        guard let config = SupabaseConfig(rawURL: urlString, anonKey: anonKey) else {
            throw SupabaseError.transport("That doesn't look like a Supabase URL.")
        }
        await client.configure(config)

        guard await client.isSignedIn else {
            phase = .needsSignIn
            return
        }
        await enterReadyState()
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.signIn(email: email, password: password)
        accountEmail = session.email
        await enterReadyState()
    }

    /// Returns false when Supabase requires the address to be confirmed before signing in.
    func signUp(email: String, password: String) async throws -> Bool {
        guard let session = try await client.signUp(email: email, password: password) else {
            return false
        }
        accountEmail = session.email
        await enterReadyState()
        return true
    }

    func sendPasswordReset(email: String) async throws {
        try await client.sendPasswordReset(email: email)
    }

    private func enterReadyState() async {
        phase = .ready
        await loadSelectedDay()
        startLiveUpdates()
        startPolling()
    }

    func signOut() async {
        stopLiveUpdates()
        stopPolling()
        loadTask?.cancel()

        await client.signOut()
        cache.clear()

        readings = []
        devices = []
        errorMessage = nil
        accountEmail = nil
        selectedDate = Date()
        phase = .needsSignIn
    }

    func disconnectProject() async {
        await signOut()
        await client.clearConfiguration()
        phase = .needsConfiguration
    }

    private func handleSessionExpiry() async {
        stopLiveUpdates()
        stopPolling()
        accountEmail = nil
        errorMessage = nil
        phase = .needsSignIn
    }

    // MARK: - Updates
    //
    // Both of these run silently. New readings simply appear; nothing in the UI reports on
    // the state of the connection.

    func startLiveUpdates() {
        guard phase == .ready, realtimeTask == nil else { return }

        realtimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard
                let config = await self.client.config,
                let token = try? await self.client.validToken()
            else { return }

            let stream = await self.realtime.start(config: config, accessToken: token)
            for await event in stream {
                guard !Task.isCancelled else { break }
                if case let .inserted(reading) = event {
                    self.insert(reading)
                }
            }
        }
    }

    func stopLiveUpdates() {
        realtimeTask?.cancel()
        realtimeTask = nil
        Task { [realtime] in await realtime.stop() }
    }

    /// Merges a pushed row into today's series, keeping it sorted and de-duplicated.
    private func insert(_ reading: Reading) {
        guard isViewingToday else { return }
        guard matchesSelectedDevice(reading) else { return }
        guard calendar.isDateInToday(reading.recordedAt) else { return }
        guard !readings.contains(where: { $0.id == reading.id }) else { return }

        if let last = readings.last, reading.recordedAt >= last.recordedAt {
            readings.append(reading)
        } else {
            let index = readings.firstIndex { $0.recordedAt > reading.recordedAt } ?? readings.count
            readings.insert(reading, at: index)
        }

        cache.save(readings: readings, deviceID: preferences.selectedDeviceID)
    }

    private func matchesSelectedDevice(_ reading: Reading) -> Bool {
        guard let selected = preferences.selectedDeviceID, !selected.isEmpty else { return true }
        return reading.deviceID == selected
    }

    func startPolling() {
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                guard let self, self.isViewingToday else { continue }
                await self.loadSelectedDay()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func handleForeground() {
        guard phase == .ready else { return }
        Task {
            await loadSelectedDay()
            startLiveUpdates()
            startPolling()
        }
    }

    func handleBackground() {
        stopLiveUpdates()
        stopPolling()
    }
}

// MARK: - Previews

extension AuraStore {
    /// An in-memory store filled with plausible data, for SwiftUI previews.
    static func preview() -> AuraStore {
        let store = AuraStore()
        store.phase = .ready
        store.readings = Reading.sampleSeries()
        store.accountEmail = "you@example.com"
        return store
    }
}
