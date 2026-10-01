import UIKit

/// Thin wrapper over UIFeedbackGenerator.
///
/// Generators are created per call rather than cached: the taps here are infrequent, and a
/// long-lived generator keeps the Taptic Engine warm for no benefit.
/// `UIFeedbackGenerator` and its subclasses are main-actor isolated, so this is too. Every
/// call site is a button action, which already runs there.
@MainActor
enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
