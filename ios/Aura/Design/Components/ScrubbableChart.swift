import SwiftUI
import UIKit

/// A transparent overlay that reports horizontal drags and ignores vertical ones.
///
/// A SwiftUI `DragGesture` with a zero minimum distance would win against the enclosing
/// `ScrollView` and the page would stop scrolling wherever a chart happened to be. This uses
/// a pan recogniser that fails itself the moment a touch moves more vertically than
/// horizontally, so a scroll stays a scroll and a scrub stays a scrub.
struct HorizontalScrubOverlay: UIViewRepresentable {
    let onScrub: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recogniser = HorizontalPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        view.addGestureRecognizer(recogniser)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onScrub = onScrub
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrub: onScrub, onEnd: onEnd)
    }

    final class Coordinator {
        var onScrub: (CGPoint) -> Void
        var onEnd: () -> Void

        init(onScrub: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
            self.onScrub = onScrub
            self.onEnd = onEnd
        }

        @objc func handle(_ recogniser: UIPanGestureRecognizer) {
            guard let view = recogniser.view else { return }

            switch recogniser.state {
            case .began, .changed:
                onScrub(recogniser.location(in: view))
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }
    }
}

/// Claims a touch only once it has moved further across than down.
private final class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    private var start: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        start = touches.first?.location(in: view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        guard state == .possible, let start, let current = touches.first?.location(in: view) else {
            return
        }

        let dx = abs(current.x - start.x)
        let dy = abs(current.y - start.y)
        guard dx > 4 || dy > 4 else { return }

        if dy > dx {
            state = .failed      // a scroll — let the ScrollView have it
        } else {
            state = .began
        }
    }

    override func reset() {
        super.reset()
        start = nil
    }
}

/// Dot-matrix bars with drag-to-scrub over the top.
///
/// Dragging moves a vertical highlight to the nearest column that has data and reports its
/// index, so the row header can mirror that slot's value and date under the finger.
struct ScrubbableChart: View {
    let values: [Double?]
    var color: Color = .white
    var axis: (from: Double, to: Double)?
    var height: CGFloat = 150

    @Binding var activeIndex: Int?
    let onScrub: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let count = max(values.count, 1)

            ZStack(alignment: .topLeading) {
                DitheredBars(
                    values: values,
                    color: color,
                    height: height,
                    highlightIndex: activeIndex,
                    axis: axis
                )

                if let activeIndex, values.indices.contains(activeIndex) {
                    Rectangle()
                        .fill(color.opacity(0.55))
                        .frame(width: 1, height: height)
                        .position(x: Self.centreX(activeIndex, count: count, width: width), y: height / 2)
                }
            }
            .contentShape(Rectangle())
            .overlay(
                HorizontalScrubOverlay(
                    onScrub: { point in
                        let raw = Self.index(atX: point.x, count: count, width: width)
                        guard let index = nearestPresent(to: raw), index != activeIndex else { return }
                        activeIndex = index
                        onScrub(index)
                    },
                    onEnd: { activeIndex = nil }
                )
            )
        }
        .frame(height: height)
    }

    /// Centre of column `index` — the same geometry `DitheredBars` draws on and the axis row
    /// lays its labels out on.
    static func centreX(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        let gap = DitheredBars.gap
        let columnWidth = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        return CGFloat(index) * (columnWidth + gap) + columnWidth / 2
    }

    private static func index(atX x: CGFloat, count: Int, width: CGFloat) -> Int {
        let gap = DitheredBars.gap
        let columnWidth = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        guard columnWidth > 0 else { return 0 }
        return Int(min(max(x, 0), width) / (columnWidth + gap)).clamped(to: 0...(count - 1))
    }

    /// Nearest column that actually holds a value — an empty slot can't be selected.
    private func nearestPresent(to index: Int) -> Int? {
        guard !values.isEmpty else { return nil }
        if values.indices.contains(index), values[index] != nil { return index }

        for distance in 1..<values.count {
            let before = index - distance
            let after = index + distance
            if values.indices.contains(before), values[before] != nil { return before }
            if values.indices.contains(after), values[after] != nil { return after }
        }
        return nil
    }
}
