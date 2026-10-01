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
    @Published var accountEmail: String?
    /// When this monitor first reported. No date picker should go further back than this.
    @Published private(set) var firstReadingAt: Date?

    /// The day being shown. Views reload by keying a `.task` on this.
    @Published var selectedDate: Date = Date()

    // MARK: - Dependencies

    let preferences: Preferences

    let notifier = AirQualityNotifier()

    private let client: SupabaseClient
    private let realtime: RealtimeChannel
    private let calendar = Calendar.current

    private var realtimeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        preferences: Preferences? = nil,
        client: SupabaseClient = SupabaseClient(),
        realtime: RealtimeChannel = RealtimeChannel()
    ) {
        let preferences = preferences ?? Preferences()

        self.preferences = preferences
        self.client = client
        self.realtime = realtime

        // Views observe the store, not `Preferences`, so the signal is forwarded. The
        // publisher only ever fires on the main actor, because `Preferences` is isolated to it.
        for publisher in [preferences.objectWillChange, notifier.objectWillChange] {
            publisher
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.objectWillChange.send() }
                }
                .store(in: &cancellables)
        }
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

    /// How much a metric has moved in the last hour, and whether that was for the worse.
    ///
    /// Only meaningful for today — a past day has no "last hour" — and only when there is a
    /// reading old enough to compare against.
    func hourlyChange(for metric: MetricKind) -> MetricChange? {
        guard isViewingToday else { return nil }

        let cutoff = Date().addingTimeInterval(-3600)
        guard
            let current = value(for: metric),
            let earlier = readings.last(where: { $0.recordedAt <= cutoff && $0.value(for: metric) != nil }),
            let previous = earlier.value(for: metric)
        else { return nil }

        let delta = current - previous
        guard abs(delta) >= metric.changeThreshold else { return nil }

        // Direction is what the number did; worse is what that meant.
        let worse = metric.distanceFromIdeal(current) > metric.distanceFromIdeal(previous)
        return MetricChange(delta: delta, isWorse: worse)
    }

    /// What the monitor was labelled when it last reported, which titles the Home screen.
    var currentZone: String? {
        readings.reversed().lazy.compactMap(\.zone).first
    }

    /// When the most recent reading on screen was taken.
    var lastReadingAt: Date? { readings.last?.recordedAt }

    /// The earliest day any picker should offer — when the monitor started reporting.
    var earliestSelectableDate: Date {
        firstReadingAt.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: Date())
    }

    func canGoBack(from date: Date) -> Bool {
        calendar.startOfDay(for: date) > earliestSelectableDate
    }

    /// The span a metric's indicator should cover.
    ///
    /// Everything but light uses its fixed range. Light has no real ceiling — direct sun will
    /// run past 5,000 lux — so the range grows to the next round thousand above the day's
    /// peak rather than pinning the marker to the right edge and hiding the variation.
    func scale(for metric: MetricKind) -> ClosedRange<Double> {
        let base = metric.scale
        guard metric == .light else { return base }

        let peak = readings.compactMap(\.light).filter(\.isFinite).max() ?? 0
        guard peak > base.upperBound else { return base }

        let widened = (peak / 1000).rounded(.up) * 1000
        return base.lowerBound...max(widened, base.upperBound)
    }

    /// Backdrop colour, driven by CO₂ — the metric that moves fastest and the one you can
    /// actually act on.
    var tint: Color {
        MetricKind.co2.tint(for: value(for: .co2))
    }

    var canGoForward: Bool {
        !isViewingToday
    }

    /// The Trends screen's store, on the same connection — one client, one session, one
    /// token refresh between them. Owned here rather than built per view, so it isn't
    /// reallocated on every body evaluation.
    private(set) lazy var trends: TrendsStore = TrendsStore(client: client, preferences: preferences)

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

        await notifier.refreshAuthorization()

        await loadSelectedDay()
        startLiveUpdates()
        startPolling()
    }

    // MARK: - Date selection

    func step(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        // Never walk past today, or back before the first reading — there is nothing either way.
        guard next <= Date() || calendar.isDateInToday(next) else { return }
        guard calendar.startOfDay(for: next) >= earliestSelectableDate else { return }
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

            await refreshDeviceList()
            await refreshFirstReadingDate()

            if calendar.isDateInToday(day) {
                await notifier.evaluate(
                    readings: fetched,
                    enabled: preferences.notificationsEnabled
                )
            }
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

    /// Fetched once per session — it only moves when the monitor is brand new.
    private func refreshFirstReadingDate() async {
        guard firstReadingAt == nil else { return }
        firstReadingAt = try? await client.firstReadingDate(deviceID: preferences.selectedDeviceID)
    }

    private func refreshDeviceList() async {
        guard devices.isEmpty else { return }
        // A nicety — a project without the helper view still works.
        devices = (try? await client.knownDevices()) ?? []
    }

    func selectDevice(_ deviceID: String?) async {
        guard preferences.selectedDeviceID != deviceID else { return }
        preferences.selectedDeviceID = deviceID
        firstReadingAt = nil
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

        readings = []
        devices = []
        errorMessage = nil
        accountEmail = nil
        firstReadingAt = nil
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
