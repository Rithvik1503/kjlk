import SwiftUI

/// Decides what the app shows: setup, sign-in, or the day.
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
                HomeTabView()
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

/// The system tab bar. Settings is a sheet from either screen's header rather than a tab.
///
/// Using `TabView` rather than a hand-rolled bar means it picks up Liquid Glass on iOS 26
/// without a single availability check.
struct HomeTabView: View {
    @EnvironmentObject private var store: AuraStore

    var body: some View {
        TabView {
            NowView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            TrendsView(trends: store.trends)
                .tabItem {
                    Label("Trends", systemImage: "chart.xyaxis.line")
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
