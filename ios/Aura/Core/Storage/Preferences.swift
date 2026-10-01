import Foundation

/// User choices. Settings, not data.
///
/// Readings are never written to the phone — every number and every chart comes from
/// Supabase on demand. What lives here is which monitor to show and whether to be told when
/// the air is getting worse.
@MainActor
final class Preferences: ObservableObject {
    /// Which monitor to show, or nil for whichever reported most recently.
    @Published var selectedDeviceID: String? {
        didSet { store.set(selectedDeviceID, forKey: Keys.selectedDevice) }
    }

    /// Whether to post a local notification when a sensor's band gets worse.
    @Published var notificationsEnabled: Bool {
        didSet { store.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    private let store: UserDefaults

    private enum Keys {
        static let selectedDevice = "pref.selectedDevice"
        static let notifications = "pref.notifications"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        selectedDeviceID = store.string(forKey: Keys.selectedDevice)
        notificationsEnabled = store.object(forKey: Keys.notifications) as? Bool ?? false
    }
}
