import SwiftUI
import UIKit

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
        ZStack {
            AuraBackground(tint: .auraCyan, intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    masthead

                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            AuraTextField(
                                title: "Project URL",
                                placeholder: "https://yourproject.supabase.co",
                                text: $urlText,
                                symbol: "link",
                                contentType: .URL,
                                keyboard: .URL
                            )
                            .focused($focused, equals: .url)
                            .submitLabel(.next)
                            .onSubmit { focused = .key }

                            AuraTextField(
                                title: "Anon (public) key",
                                placeholder: "eyJhbGciOi…",
                                text: $anonKey,
                                symbol: "key",
                                isSecure: true
                            )
                            .focused($focused, equals: .key)
                            .submitLabel(.go)
                            .onSubmit { submit() }

                            Label(
                                "Use the anon key from Project Settings → API. Never paste the service role key or your device token into an app.",
                                systemImage: "lock.shield"
                            )
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ProminentButton(
                        title: "Connect",
                        symbol: "arrow.right",
                        tint: .auraCyan,
                        isLoading: isWorking
                    ) {
                        submit()
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)

                    helpCard
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "aqi.medium")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.auraCyan)

            Text("Aura")
                .font(.auraDisplay(36, weight: .bold))
                .foregroundStyle(Color.auraPrimaryText)

            Text("Connect to the Supabase project your ESP32 uploads to.")
                .font(.auraLabel)
                .foregroundStyle(Color.auraSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var helpCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where do I find these?")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.auraNumeral(11, weight: .bold))
                            .foregroundStyle(Color.auraVoid)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.auraCyan))

                        Text(step)
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private let steps = [
        "Open your project on supabase.com.",
        "Go to Project Settings, then API.",
        "Copy the Project URL and the anon public key.",
    ]

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await store.configure(urlString: urlText, anonKey: anonKey)
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
                Haptics.error()
            }
            isWorking = false
        }
    }
}

/// A dark-styled text field with a label above it, used across onboarding and settings.
struct AuraTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var symbol: String?
    var isSecure: Bool = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.auraCaption)
                .foregroundStyle(Color.auraSecondaryText)

            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.auraTertiaryText)
                        .frame(width: 16)
                }

                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(.auraLabel)
                .foregroundStyle(Color.auraPrimaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(contentType)
                .keyboardType(keyboard)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRevealed ? "Hide" : "Show")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.auraSurfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }
}

#Preview("Connect") {
    ConnectView()
        .environmentObject(AuraStore())
        .preferredColorScheme(.dark)
}
