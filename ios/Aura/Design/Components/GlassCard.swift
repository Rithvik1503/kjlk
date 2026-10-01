import SwiftUI

/// The surface everything sits on: a dark rounded rectangle with a hairline that catches
/// light at the top edge, so stacked cards stay separable against a dark background.
struct GlassCard<Content: View>: View {
    var tint: Color = .clear
    var padding: CGFloat = Metrics.cardPadding
    var radius: CGFloat = Metrics.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.auraSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.16), tint.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.03),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
    }
}

/// Small heading above a card or a group of them.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var accessory: AnyView?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = nil
    }

    init<Accessory: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.auraSectionTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraTertiaryText)
                }
            }

            Spacer(minLength: 12)
            accessory
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A dot that pulses while the realtime socket is connected, and sits still when it isn't.
struct LiveDot: View {
    let isLive: Bool
    @State private var pulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(Color.auraGreen.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulsing ? 1.5 : 0.8)
                    .opacity(pulsing ? 0 : 1)
            }

            Circle()
                .fill(isLive ? Color.auraGreen : Color.auraTertiaryText)
                .frame(width: 7, height: 7)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            guard isLive, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
        .onChange(of: isLive) { _, newValue in
            guard !reduceMotion else { return }
            if newValue {
                pulsing = false
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            } else {
                withAnimation(.default) { pulsing = false }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Card") {
    ZStack {
        Color.auraBase.ignoresSafeArea()
        VStack(spacing: 16) {
            SectionHeader("Right now", subtitle: "Living room") {
                LiveDot(isLive: true)
            }
            GlassCard(tint: .auraGreen) {
                Text("Contents")
                    .foregroundStyle(Color.auraPrimaryText)
            }
        }
        .padding()
    }
}
