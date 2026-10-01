import SwiftUI

/// First run: point the app at a Supabase project.
///
/// Both fields are safe to type here. The anon key is meant to ship in clients — it is the
/// public half of the pair, and row level security is what actually protects the data. The
/// service role key and the device ingest token must never be entered, so the screen says so.
struct ConnectView: View {
    @EnvironmentObject private var store: AuraStore

    @State private var urlText = ""
    @State private var anonKey = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    @FocusState private var focused: Field?

    private enum Field { case url, key }

    private var canSubmit: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty
            && !anonKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://yourproject.supabase.co", text: $urlText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focused = .key }

                    SecureField("Anon (public) key", text: $anonKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .key)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } header: {
                    Text("Project")
                } footer: {
                    Text("Project Settings → API. Use the anon public key — never the service role key or your device token.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text("Connect")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Connect")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await store.configure(urlString: urlText, anonKey: anonKey)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview("Connect") {
    ConnectView()
        .environmentObject(AuraStore())
        .preferredColorScheme(.dark)
}
