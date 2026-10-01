import SwiftUI

/// The living backdrop. Its colour is the room's verdict, so the screen reads before the
/// numbers do — green when the air is fine, amber when it's going off, red when it's bad.
///
/// Two blurred blobs drift slowly behind a near-black base. On iOS 18 the same idea is drawn
/// with `MeshGradient`, which gives a softer falloff for the same cost.
struct AuraBackground: View {
    let tint: Color
    var intensity: Double = 1
    var isAnimated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var animates: Bool { isAnimated && !reduceMotion }

    var body: some View {
        ZStack {
            Color.auraVoid

            if #available(iOS 18.0, *) {
                mesh
            } else {
                blobs
            }

            // Keeps text contrast constant no matter how bright the tint gets.
            LinearGradient(
                colors: [.clear, Color.auraVoid.opacity(0.55), Color.auraVoid.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard animates else { return }
            withAnimation(Motion.ambient) { drift = true }
        }
        .auraAnimation(Motion.gentle, value: tint)
        .accessibilityHidden(true)
    }

    @available(iOS 18.0, *)
    private var mesh: some View {
        let warm = tint.opacity(0.55 * intensity)
        let cool = tint.opacity(0.22 * intensity)
        let shift: Float = drift ? 0.12 : -0.08

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5 + shift, 0), .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.45 + shift), .init(1, 0.5),
                .init(0, 1), .init(0.5 - shift, 1), .init(1, 1),
            ],
            colors: [
                warm, cool, Color.auraVoid,
                cool, warm, Color.auraVoid,
                Color.auraVoid, Color.auraVoid, Color.auraVoid,
            ]
        )
        .blur(radius: 40)
        .ignoresSafeArea()
    }

    private var blobs: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Circle()
                    .fill(tint.opacity(0.5 * intensity))
                    .frame(width: size.width * 1.1)
                    .blur(radius: 90)
                    .offset(
                        x: drift ? -size.width * 0.18 : size.width * 0.06,
                        y: -size.height * 0.34
                    )

                Circle()
                    .fill(tint.opacity(0.26 * intensity))
                    .frame(width: size.width * 0.9)
                    .blur(radius: 110)
                    .offset(
                        x: drift ? size.width * 0.3 : size.width * 0.08,
                        y: drift ? -size.height * 0.05 : -size.height * 0.16
                    )
            }
        }
    }
}

/// Fades the top of a scroll view into the background so content doesn't collide with the
/// navigation bar — the alternative is an opaque bar, which would cut the gradient in half.
struct ScrollFadeMask: ViewModifier {
    var height: CGFloat = 60

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.auraVoid.opacity(0.85), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func scrollFadeMask(height: CGFloat = 60) -> some View {
        modifier(ScrollFadeMask(height: height))
    }
}

#Preview("Background") {
    ZStack {
        AuraBackground(tint: .auraOrange)
        VStack {
            Text("Getting stuffy")
                .font(.auraDisplay(28, weight: .bold))
                .foregroundStyle(Color.auraPrimaryText)
        }
    }
}
