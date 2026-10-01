import SwiftUI
import UIKit

@main
struct AuraApp: App {
    @StateObject private var store = AuraStore()

    init() {
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color.auraCyan)
        }
    }

    /// The app is dark everywhere, so the few UIKit surfaces SwiftUI still falls back to —
    /// the share sheet's navigation bar, alert tints — are told about it up front.
    @MainActor
    private static func configureAppearance() {
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Color.auraCyan)
    }
}
