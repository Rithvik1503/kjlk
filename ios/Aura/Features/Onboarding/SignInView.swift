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
        ZStack {
            AuraBackground(tint: .auraViolet, intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    masthead

                    SegmentedPills(
                        items: Mode.allCases,
                        selection: $mode,
                        title: { $0.title }
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            AuraTextField(
                                title: "Email",
                                placeholder: "you@example.com",
                                text: $email,
                                symbol: "envelope",
                                contentType: .username,
                                keyboard: .emailAddress
                            )
                            .focused($focused, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }

                            AuraTextField(
                                title: "Password",
                                placeholder: "At least 6 characters",
                                text: $password,
                                symbol: "lock",
                                isSecure: true,
                                contentType: mode == .signUp ? .newPassword : .password
                            )
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }

                            if mode == .signIn {
                                Button("Forgot password?") { resetPassword() }
                                    .font(.auraCaption)
                                    .foregroundStyle(Color.auraCyan)
                                    .disabled(!email.contains("@") || isWorking)
                            }
                        }
                    }

                    if let message {
                        Label(
                            message.text,
                            systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.auraLabel)
                        .foregroundStyle(message.isError ? Color.auraRed : Color.auraGreen)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    ProminentButton(
                        title: mode.title,
                        symbol: "arrow.right",
                        tint: .auraViolet,
                        isLoading: isWorking
                    ) {
                        submit()
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)

                    Button {
                        Task { await store.disconnectProject() }
                    } label: {
                        Label("Use a different project", systemImage: "arrow.triangle.2.circlepath")
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 44)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(Motion.snappy, value: mode)
        .animation(Motion.snappy, value: message)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back")
                .font(.auraDisplay(32, weight: .bold))
                .foregroundStyle(Color.auraPrimaryText)

            Text("Sign in with the account that owns your readings.")
                .font(.auraLabel)
                .foregroundStyle(Color.auraSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
                    Haptics.success()

                case .signUp:
                    let signedIn = try await store.signUp(email: email, password: password)
                    if signedIn {
                        Haptics.success()
                    } else {
                        message = Message(
                            text: "Check your inbox for a confirmation link, then sign in.",
                            isError: false
                        )
                        mode = .signIn
                    }
                }
            } catch {
                message = Message(text: error.localizedDescription, isError: true)
                Haptics.error()
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
