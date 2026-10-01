import SwiftUI

/// Decides what the app shows: setup, sign-in, or the dashboard.
struct RootView: View {
    @EnvironmentObject private var store: AuraStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch store.phase {
            case .launching:
                LaunchView()
                    .transition(.opacity)

            case .needsConfiguration:
                ConnectView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .needsSignIn:
                SignInView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .ready:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(Motion.gentle, value: store.phase)
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
            AuraBackground(tint: .auraCyan, intensity: 0.5)

            VStack(spacing: 18) {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.auraCyan)

                ProgressView()
                    .tint(Color.auraSecondaryText)
            }
        }
    }
}

/// The three sections, behind a floating capsule bar rather than the system tab bar — the
/// system bar would need an opaque background and would slice the gradient off at the bottom.
struct MainTabView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case now
        case history
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .now: "Now"
            case .history: "History"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .now: "waveform.path.ecg"
            case .history: "calendar"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @EnvironmentObject private var store: AuraStore
    @State private var tab: Tab = .now

    var body: some View {
        ZStack(alignment: .bottom) {
            AuraBackground(
                tint: store.status.tint,
                isAnimated: !store.preferences.reduceMotion
            )

            Group {
                switch tab {
                case .now: NowView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .transition(.opacity)

            TabBar(selection: $tab)
                .padding(.horizontal, 36)
                .padding(.bottom, 6)
        }
        .animation(Motion.snappy, value: tab)
    }
}

private struct TabBar: View {
    @Binding var selection: MainTabView.Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTabView.Tab.allCases) { tab in
                let isSelected = tab == selection

                Button {
                    guard !isSelected else { return }
                    Haptics.selection()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? Color.auraPrimaryText : Color.auraTertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.09))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.auraVoid.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
    }
}
