import SwiftUI

/// Sign in to the Supabase account that owns the readings.
///
/// Readings are filtered by `owner_id` in row level security, so the account signed in here
/// has to be the one whose UUID the edge function writes — the `OWNER_USER_ID` secret.
struct SignInView: View {
    @EnvironmentObject private var store: AuraStore

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: "Sign in"
            case .signUp: "Create account"
            }
        }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: Message?

    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("you@example.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Use the account whose user ID is set as OWNER_USER_ID in your Supabase secrets.")
                }

                if let message {
                    Section {
                        Label(
                            message.text,
                            systemImage: message.isError
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle.fill"
                        )
                        .foregroundStyle(message.isError ? .red : .green)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(mode.title)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)

                    if mode == .signIn {
                        Button("Forgot password?", action: resetPassword)
                            .disabled(!email.contains("@") || isWorking)
                    }
                }

                Section {
                    Button("Use a different project", role: .destructive) {
                        Task { await store.disconnectProject() }
                    }
                }
            }
            .navigationTitle("Aura")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        isWorking = true
        message = nil

        Task {
            do {
                switch mode {
                case .signIn:
                    try await store.signIn(email: email, password: password)

                case .signUp:
                    let signedIn = try await store.signUp(email: email, password: password)
                    if !signedIn {
                        message = Message(
                            text: "Check your inbox for a confirmation link, then sign in.",
                            isError: false
                        )
                        mode = .signIn
                    }
                }
            } catch {
                message = Message(text: error.localizedDescription, isError: true)
            }
            isWorking = false
        }
    }

    private func resetPassword() {
        isWorking = true
        message = nil

        Task {
            do {
                try await store.sendPasswordReset(email: email)
                message = Message(text: "Reset link sent to \(email).", isError: false)
            } catch {
                message = Message(text: error.localizedDescription, isError: true)
            }
            isWorking = false
        }
    }
}

#Preview("Sign in") {
    SignInView()
        .environmentObject(AuraStore())
        .preferredColorScheme(.dark)
}
