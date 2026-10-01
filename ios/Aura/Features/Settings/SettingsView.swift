import SwiftUI

/// Units, calibration, device selection, and the way out.
struct SettingsView: View {
    @EnvironmentObject private var store: AuraStore
    @State private var showingSignOutConfirmation = false
    @State private var showingDisconnectConfirmation = false

    private var preferences: Preferences { store.preferences }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                header
                deviceCard
                unitsCard
                calibrationCard
                updatesCard
                accountCard
                aboutCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await store.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your cached readings on this phone will be cleared.")
        }
        .confirmationDialog(
            "Disconnect this project?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await store.disconnectProject() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need the project URL and anon key to connect again.")
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.auraDisplay(26, weight: .bold))
                .foregroundStyle(Color.auraPrimaryText)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Device

    private var deviceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Device")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                if store.devices.isEmpty {
                    Text(preferences.selectedDeviceID ?? "All devices")
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraSecondaryText)

                    Text("Only one monitor is reporting, so there's nothing to choose between.")
                        .font(.auraCaption)
                        .foregroundStyle(Color.auraTertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            deviceChip(title: "All", deviceID: nil)
                            ForEach(store.devices, id: \.self) { device in
                                deviceChip(title: device, deviceID: device)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func deviceChip(title: String, deviceID: String?) -> some View {
        let isSelected = preferences.selectedDeviceID == deviceID

        return Button {
            Haptics.selection()
            Task { await store.selectDevice(deviceID) }
        } label: {
            Text(title)
                .font(.auraLabel)
                .foregroundStyle(isSelected ? Color.auraVoid : Color.auraSecondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(isSelected ? Color.auraPrimaryText : Color.auraSurfaceRaised))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Units

    private var unitsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Temperature unit")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                SegmentedPills(
                    items: TemperatureUnit.allCases,
                    selection: Binding(
                        get: { preferences.temperatureUnit },
                        set: { preferences.temperatureUnit = $0 }
                    ),
                    title: { "\($0.title) (\($0.suffix))" }
                )
            }
        }
    }

    // MARK: - Calibration

    private var calibrationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Temperature offset")
                        .font(.auraCardTitle)
                        .foregroundStyle(Color.auraPrimaryText)

                    Spacer()

                    Text(offsetLabel)
                        .font(.auraNumeral(15, weight: .bold))
                        .foregroundStyle(Color.auraCyan)
                }

                Slider(
                    value: Binding(
                        get: { preferences.temperatureOffset },
                        set: { preferences.temperatureOffset = ($0 * 10).rounded() / 10 }
                    ),
                    in: -10...10,
                    step: 0.1
                )
                .tint(Color.auraCyan)

                Text("The SCD40 sits inside its own case and usually reads warm. Compare against a thermometer you trust and nudge this until they agree.")
                    .font(.auraCaption)
                    .foregroundStyle(Color.auraTertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.temperatureOffset != 0 {
                    Button("Reset to zero") {
                        Haptics.light()
                        preferences.temperatureOffset = 0
                    }
                    .font(.auraCaption)
                    .foregroundStyle(Color.auraCyan)
                }
            }
        }
    }

    /// Offsets are stored in Celsius; show the equivalent span in whichever unit is in use.
    private var offsetLabel: String {
        let shown = preferences.temperatureUnit.convertDelta(preferences.temperatureOffset)
        let sign = shown > 0 ? "+" : ""
        return sign + shown.formatted(.number.precision(.fractionLength(1))) + preferences.temperatureUnit.suffix
    }

    // MARK: - Updates

    private var updatesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { preferences.liveUpdatesEnabled },
                    set: { newValue in
                        preferences.liveUpdatesEnabled = newValue
                        if newValue {
                            store.startLiveUpdates()
                        } else {
                            store.stopLiveUpdates()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live updates")
                            .font(.auraCardTitle)
                            .foregroundStyle(Color.auraPrimaryText)

                        Text(store.isLiveConnected ? "Connected" : "Reconnecting…")
                            .font(.auraCaption)
                            .foregroundStyle(store.isLiveConnected ? Color.auraGreen : Color.auraTertiaryText)
                    }
                }
                .tint(Color.auraGreen)

                Divider().overlay(Color.auraHairline)

                Toggle(isOn: Binding(
                    get: { preferences.reduceMotion },
                    set: { preferences.reduceMotion = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calm background")
                            .font(.auraCardTitle)
                            .foregroundStyle(Color.auraPrimaryText)

                        Text("Stops the backdrop from drifting.")
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                }
                .tint(Color.auraGreen)

                Divider().overlay(Color.auraHairline)

                HStack {
                    Text("Last refreshed")
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraSecondaryText)

                    Spacer()

                    Text(store.lastUpdated.map { RelativeTime.string(for: $0) } ?? "Never")
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraPrimaryText)
                }
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Account")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                if let email = store.accountEmail {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.auraTertiaryText)

                        Text(email)
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 10) {
                    PillButton(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right") {
                        showingSignOutConfirmation = true
                    }

                    PillButton(title: "Disconnect", symbol: "xmark.circle", tint: .auraRed) {
                        showingDisconnectConfirmation = true
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Aura")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                Text("Room monitor for an ESP32 with an SCD40 and a BH1750.")
                    .font(.auraCaption)
                    .foregroundStyle(Color.auraTertiaryText)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.auraCaption)
                        .foregroundStyle(Color.auraTertiaryText)
                }
            }
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(AuraStore.preview())
        .background(Color.auraBase)
        .preferredColorScheme(.dark)
}
