import SwiftUI

@main
struct AuraApp: App {
    @StateObject private var store = AuraStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color.auraCyan)
        }
    }
}
