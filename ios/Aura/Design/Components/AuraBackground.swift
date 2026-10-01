import SwiftUI

/// A dark backdrop with a single soft glow in the current band's colour, so the screen reads
/// before the number does — green when the air is fine, amber when it is going off.
///
/// Static. The colour changes when the reading crosses a band, and nothing moves otherwise.
struct AuraBackground: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color.auraVoid

            GeometryReader { proxy in
                let size = proxy.size

                Circle()
                    .fill(tint.opacity(0.4))
                    .frame(width: size.width * 1.15)
                    .blur(radius: 100)
                    .offset(x: -size.width * 0.1, y: -size.height * 0.3)
            }

            // Holds text contrast steady no matter how bright the tint gets.
            LinearGradient(
                colors: [.clear, Color.auraVoid.opacity(0.6), Color.auraVoid.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: tint)
        .accessibilityHidden(true)
    }
}

#Preview("Background") {
    ZStack {
        AuraBackground(tint: .auraAmber)
        Text("Stuffy")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(Color.auraPrimaryText)
    }
}
