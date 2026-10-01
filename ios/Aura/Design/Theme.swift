import SwiftUI

/// The palette.
///
/// Surfaces are a near-black ramp the card sits on; accents carry meaning and are tied to a
/// quality band in `MetricKind`, never chosen for decoration. Type and controls come from the
/// system, so there is nothing here for them.
extension Color {
    // Surfaces, darkest first.
    static let auraVoid = Color(hex: 0x070709)
    static let auraBase = Color(hex: 0x0D0E12)
    static let auraSurface = Color(hex: 0x15171D)
    static let auraHairline = Color(hex: 0x2A2E37)

    static let auraPrimaryText = Color(hex: 0xF5F6F8)

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

    /// Stand-in when a value is missing — desaturated, so a gap never reads as data.
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
