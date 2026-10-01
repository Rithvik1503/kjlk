import SwiftUI

@main
struct AuraApp: App {
    @UIApplicationDelegateAdaptor(AuraAppDelegate.self) private var appDelegate
    @StateObject private var store = AuraStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color.auraCyan)
                .task {
                    // The delegate is created by UIKit before the store exists, so the two are
                    // introduced here rather than at init.
                    appDelegate.registrar = store.push
                    if store.preferences.notificationsEnabled {
                        store.push.start()
                    }
                }
        }
    }
}
