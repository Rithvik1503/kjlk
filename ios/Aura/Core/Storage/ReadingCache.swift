import Foundation

/// Today's readings on disk, so the app opens showing something instead of a spinner.
///
/// Written to Caches rather than Documents: it is all reproducible from Supabase, and the
/// system is welcome to reclaim it under pressure.
struct ReadingCache: Sendable {
    private let fileURL: URL
    private let maximumAge: TimeInterval = 24 * 3600

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

        // Yesterday's cache would show under today's date, which is worse than showing nothing.
        guard Date().timeIntervalSince(snapshot.savedAt) < maximumAge else { return nil }
        return snapshot
    }

    func save(readings: [Reading], deviceID: String?) {
        let trimmed = readings.suffix(2000)
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
    /// Which monitor to show, or nil for whichever reported most recently.
    @Published var selectedDeviceID: String? {
        didSet { store.set(selectedDeviceID, forKey: Keys.selectedDevice) }
    }

    private let store: UserDefaults

    private enum Keys {
        static let selectedDevice = "pref.selectedDevice"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        selectedDeviceID = store.string(forKey: Keys.selectedDevice)
    }
}
