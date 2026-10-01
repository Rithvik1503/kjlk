import Foundation

/// Last-known readings on disk, so the app opens showing something instead of a spinner.
///
/// Written to Caches rather than Documents: it is all reproducible from Supabase, and the
/// system is welcome to reclaim it under pressure.
struct ReadingCache: Sendable {
    private let fileURL: URL
    private let maximumAge: TimeInterval = 7 * 24 * 3600

    init(filename: String = "readings-cache.json") {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent(filename)
    }

    struct Snapshot: Codable, Sendable {
        var readings: [Reading]
        var savedAt: Date
        var deviceID: String?
    }

    func load() -> Snapshot? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }

        // Anything older than a week is more misleading than useful.
        guard Date().timeIntervalSince(snapshot.savedAt) < maximumAge else { return nil }
        return snapshot
    }

    func save(readings: [Reading], deviceID: String?) {
        // Cap what we persist: the dashboard only ever reads back the recent tail.
        let trimmed = readings.suffix(3000)
        let snapshot = Snapshot(readings: Array(trimmed), savedAt: Date(), deviceID: deviceID)

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// User choices that aren't secret and don't belong on the server.
@MainActor
final class Preferences: ObservableObject {
    @Published var temperatureUnit: TemperatureUnit {
        didSet { store.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit) }
    }

    /// Added to every temperature reading, to correct for the SCD40 self-heating inside its case.
    @Published var temperatureOffset: Double {
        didSet { store.set(temperatureOffset, forKey: Keys.temperatureOffset) }
    }

    @Published var selectedDeviceID: String? {
        didSet { store.set(selectedDeviceID, forKey: Keys.selectedDevice) }
    }

    @Published var preferredRange: TimeRange {
        didSet { store.set(preferredRange.rawValue, forKey: Keys.preferredRange) }
    }

    @Published var liveUpdatesEnabled: Bool {
        didSet { store.set(liveUpdatesEnabled, forKey: Keys.liveUpdates) }
    }

    @Published var reduceMotion: Bool {
        didSet { store.set(reduceMotion, forKey: Keys.reduceMotion) }
    }

    private let store: UserDefaults

    private enum Keys {
        static let temperatureUnit = "pref.temperatureUnit"
        static let temperatureOffset = "pref.temperatureOffset"
        static let selectedDevice = "pref.selectedDevice"
        static let preferredRange = "pref.preferredRange"
        static let liveUpdates = "pref.liveUpdates"
        static let reduceMotion = "pref.reduceMotion"
    }

    init(store: UserDefaults = .standard) {
        self.store = store

        let unitValue = store.string(forKey: Keys.temperatureUnit) ?? TemperatureUnit.celsius.rawValue
        temperatureUnit = TemperatureUnit(rawValue: unitValue) ?? .celsius

        temperatureOffset = store.double(forKey: Keys.temperatureOffset)
        selectedDeviceID = store.string(forKey: Keys.selectedDevice)

        let rangeValue = store.string(forKey: Keys.preferredRange) ?? TimeRange.day.rawValue
        preferredRange = TimeRange(rawValue: rangeValue) ?? .day

        liveUpdatesEnabled = store.object(forKey: Keys.liveUpdates) as? Bool ?? true
        reduceMotion = store.object(forKey: Keys.reduceMotion) as? Bool ?? false
    }

    // Unit conversion and formatting live on `DisplayScale` (see `scale(for:)`) so there is
    // exactly one place that knows how a raw sensor value becomes something on screen.
}
