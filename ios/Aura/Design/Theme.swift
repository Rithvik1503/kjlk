import SwiftUI

/// The palette.
///
/// Two families: a near-black set of surfaces that the cards and backgrounds are built from,
/// and a saturated set of accents that carry meaning — each one is tied to a quality band in
/// `MetricKind`, never chosen for decoration.
extension Color {
    // Surfaces, darkest first.
    static let auraVoid = Color(hex: 0x070709)
    static let auraBase = Color(hex: 0x0D0E12)
    static let auraSurface = Color(hex: 0x15171D)
    static let auraSurfaceRaised = Color(hex: 0x1D2027)
    static let auraHairline = Color(hex: 0x2A2E37)

    // Text.
    static let auraPrimaryText = Color(hex: 0xF5F6F8)
    static let auraSecondaryText = Color(hex: 0x9BA1AE)
    static let auraTertiaryText = Color(hex: 0x646B7A)

    // Accents, cold to hot.
    static let auraIndigo = Color(hex: 0x5B5BD6)
    static let auraViolet = Color(hex: 0x8B5CF6)
    static let auraBlue = Color(hex: 0x3B82F6)
    static let auraCyan = Color(hex: 0x22D3EE)
    static let auraGreen = Color(hex: 0x34D399)
    static let auraLime = Color(hex: 0xA3E635)
    static let auraYellow = Color(hex: 0xFACC15)
    static let auraAmber = Color(hex: 0xFBBF24)
    static let auraOrange = Color(hex: 0xFB7B3A)
    static let auraRed = Color(hex: 0xF4603E)

    /// Stand-in when a value is missing — deliberately desaturated so a gap never reads as data.
    static let auraSlate = Color(hex: 0x4A515F)

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Shared geometry, so corners and insets stay consistent across screens.
enum Metrics {
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 28
    static let innerRadius: CGFloat = 20
    static let pillRadius: CGFloat = 999
    static let cardSpacing: CGFloat = 14
}

/// Motion. One place to tune the feel, and one switch to calm it all down.
enum Motion {
    static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.88)
    static let value = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let ambient = Animation.easeInOut(duration: 9).repeatForever(autoreverses: true)
}

// MARK: - Type

extension Font {
    /// Big readouts. Rounded, tight, and monospaced on the digits so the number doesn't
    /// jitter sideways every time a value ticks over.
    static func auraNumeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func auraDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let auraSectionTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let auraCardTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let auraLabel = Font.system(size: 13, weight: .medium, design: .rounded)
    static let auraCaption = Font.system(size: 11, weight: .medium, design: .rounded)
}

// MARK: - Shared modifiers

extension View {
    /// Soft capsule used for metadata — "2 min ago", a device name, a quality word.
    func auraChip(tint: Color = .auraSecondaryText) -> some View {
        self
            .font(.auraCaption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(tint.opacity(0.14))
            )
    }

    /// Applies an animation unless the user has asked for less motion, in Settings or in iOS.
    func auraAnimation<V: Equatable>(_ animation: Animation, value: V, enabled: Bool = true) -> some View {
        modifier(ConditionalAnimation(animation: animation, value: value, enabled: enabled))
    }
}

private struct ConditionalAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let animation: Animation
    let value: V
    let enabled: Bool

    func body(content: Content) -> some View {
        content.animation((enabled && !systemReduceMotion) ? animation : nil, value: value)
    }
}
