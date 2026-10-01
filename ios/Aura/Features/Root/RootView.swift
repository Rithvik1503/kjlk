import SwiftUI

/// Decides what the app shows: setup, sign-in, or the day.
///
/// There is no tab bar — settings is a sheet from the header, and there is nowhere else to go.
struct RootView: View {
    @EnvironmentObject private var store: AuraStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch store.phase {
            case .launching:
                LaunchView()

            case .needsConfiguration:
                ConnectView()

            case .needsSignIn:
                SignInView()

            case .ready:
                NowView()
            }
        }
        .preferredColorScheme(.dark)
        .animation(.default, value: store.phase)
        .task { await store.start() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: store.handleForeground()
            case .background: store.handleBackground()
            default: break
            }
        }
    }
}

/// Shown for the fraction of a second while the keychain is read.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.auraVoid.ignoresSafeArea()
            ProgressView()
        }
    }
}
