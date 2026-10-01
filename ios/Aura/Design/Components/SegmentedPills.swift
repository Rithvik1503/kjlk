import SwiftUI

/// The pill picker from the references — a white capsule sliding behind the selected label.
///
/// `matchedGeometryEffect` moves the highlight rather than cross-fading two of them, so the
/// selection feels physically attached to the finger.
struct SegmentedPills<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var symbol: ((Item) -> String?)?
    var tint: Color = .auraPrimaryText

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isSelected = item == selection

                Button {
                    guard !isSelected else { return }
                    Haptics.selection()
                    if reduceMotion {
                        selection = item
                    } else {
                        withAnimation(Motion.snappy) { selection = item }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = symbol?(item) {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(title(item))
                            .font(.auraLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Color.auraVoid : Color.auraSecondaryText)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(tint)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.auraSurface)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

/// A bordered capsule button used for secondary actions — export, change device, pick a date.
struct PillButton: View {
    let title: String
    var symbol: String?
    var tint: Color = .auraPrimaryText
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.auraLabel)
            }
            .foregroundStyle(isProminent ? Color.auraVoid : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isProminent ? tint : Color.auraSurfaceRaised)
            )
            .overlay(
                Capsule().strokeBorder(
                    isProminent ? Color.clear : Color.white.opacity(0.08),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

/// The primary action at the bottom of a screen — the blue "7-Day Forecast" shape.
struct ProminentButton: View {
    let title: String
    var symbol: String?
    var tint: Color = .auraBlue
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                }

                Text(title)
                    .font(.auraDisplay(16, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(tint)
                    .shadow(color: tint.opacity(0.45), radius: 18, y: 8)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
    }
}

/// Shrinks slightly on press. Used anywhere a tap should feel like it landed.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("Controls") {
    @Previewable @State var range: TimeRange = .day

    ZStack {
        Color.auraBase.ignoresSafeArea()

        VStack(spacing: 20) {
            SegmentedPills(
                items: TimeRange.allCases,
                selection: $range,
                title: { $0.title },
                symbol: { $0.symbol }
            )

            HStack {
                PillButton(title: "Today", symbol: "calendar") {}
                PillButton(title: "Export", symbol: "square.and.arrow.up", isProminent: true) {}
            }

            ProminentButton(title: "Open history", symbol: "chart.xyaxis.line") {}
        }
        .padding()
    }
}
