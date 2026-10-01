import SwiftUI

/// Device, account, and the way out — a stock `Form`, presented as a sheet from the header.
struct SettingsView: View {
    @EnvironmentObject private var store: AuraStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingSignOut = false
    @State private var confirmingDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                deviceSection
                accountSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await store.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Readings cached on this phone will be cleared.")
            }
            .confirmationDialog(
                "Disconnect this project?",
                isPresented: $confirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        await store.disconnectProject()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need the project URL and anon key to connect again.")
            }
        }
    }

    @ViewBuilder
    private var deviceSection: some View {
        Section {
            if store.devices.isEmpty {
                LabeledContent("Monitor", value: store.preferences.selectedDeviceID ?? "All devices")
            } else {
                Picker("Monitor", selection: deviceBinding) {
                    Text("All devices").tag(String?.none)
                    ForEach(store.devices, id: \.self) { device in
                        Text(device).tag(String?.some(device))
                    }
                }
            }
        } header: {
            Text("Device")
        } footer: {
            if store.devices.count > 1 {
                Text("Readings are filtered to the selected monitor.")
            }
        }
    }

    private var deviceBinding: Binding<String?> {
        Binding(
            get: { store.preferences.selectedDeviceID },
            set: { newValue in Task { await store.selectDevice(newValue) } }
        )
    }

    private var accountSection: some View {
        Section("Account") {
            if let email = store.accountEmail {
                LabeledContent("Signed in as") {
                    Text(email)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Button("Sign out") { confirmingSignOut = true }

            Button("Disconnect project", role: .destructive) {
                confirmingDisconnect = true
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Sensors", value: "SCD40 · BH1750")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("Version", value: version)
            }
        } header: {
            Text("About")
        } footer: {
            Text("Aura shows carbon dioxide from an ESP32 room monitor.")
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(AuraStore.preview())
        .preferredColorScheme(.dark)
}
