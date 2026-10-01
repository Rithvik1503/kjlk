import SwiftUI

/// A row of dot-matrix bars.
///
/// Each slot's bar height is proportional to its value, and dots are brightest at the top of
/// the bar, fading toward the baseline. A `nil` slot draws a single dim row along the
/// baseline rather than nothing, so a missing day reads as "no data" and still occupies its
/// position instead of letting the next one slide into it.
struct DitheredBars: View {
    let values: [Double?]

    var color: Color = .white
    var height: CGFloat = 150
    var gap: CGFloat = 3
    var grid: CGFloat = 4
    var dotRadius: CGFloat = 0.85
    /// Floor on bar height, so a value at the very bottom of the axis still shows something.
    var minFraction: CGFloat = 0.07
    /// When set, every other column is dimmed — used while scrubbing.
    var highlightIndex: Int?
    /// Fixed axis. Without one the bars self-scale to the window, which makes a bar's height
    /// mean something different in every window.
    var axis: (from: Double, to: Double)?

    var body: some View {
        Canvas { context, size in
            let count = values.count
            guard count > 0, size.width > 0, size.height > 0 else { return }

            let present = values.compactMap { $0 }
            guard let high = present.max(), let low = present.min() else { return }

            // Self-scaling expands the low end a little, so day-to-day variation stays
            // visible instead of every bar sitting at full height.
            let floorValue = axis?.from ?? (low - (high - low) * 0.25 - 0.0001)
            let span = max((axis?.to ?? high) - floorValue, 1e-6)
            let columnWidth = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            guard columnWidth > 0 else { return }

            for (index, raw) in values.enumerated() {
                let dim: Double = (highlightIndex == nil || highlightIndex == index) ? 1 : 0.18
                let originX = CGFloat(index) * (columnWidth + gap)

                guard let value = raw else {
                    drawBaseline(
                        in: &context,
                        originX: originX,
                        columnWidth: columnWidth,
                        size: size,
                        dim: dim
                    )
                    continue
                }

                let fraction = max(minFraction, min(1, CGFloat((value - floorValue) / span)))
                let barHeight = size.height * fraction
                let topY = size.height - barHeight

                // Rows are laid from the baseline up, so every bar's bottom row sits on the
                // same line. Stepping down from each bar's own top instead left bases at
                // slightly different heights depending on where topY fell between rows.
                var y = size.height - dotRadius
                while y >= topY - 0.01 {
                    let alpha = 1 - 0.85 * Double((y - topY) / max(barHeight, 1))
                    var x = originX + grid / 2
                    while x <= originX + columnWidth - grid / 2 + 0.01 {
                        context.fill(
                            dot(x: x, y: y),
                            with: .color(color.opacity(max(0.15, alpha) * dim))
                        )
                        x += grid
                    }
                    y -= grid
                }
            }
        }
        .frame(height: height)
    }

    private func drawBaseline(
        in context: inout GraphicsContext,
        originX: CGFloat,
        columnWidth: CGFloat,
        size: CGSize,
        dim: Double
    ) {
        let y = size.height - dotRadius
        var x = originX + grid / 2
        while x <= originX + columnWidth - grid / 2 + 0.01 {
            context.fill(dot(x: x, y: y), with: .color(color.opacity(0.22 * dim)))
            x += grid
        }
    }

    private func dot(x: CGFloat, y: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: x - dotRadius,
            y: y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
    }
}

/// The small preview in a collapsed Trends row.
///
/// Always lays out a fixed number of slots, right-aligned and padded with empty ones, so a
/// bar is the same width whether there are two days of history or two hundred.
struct MiniDitheredBars: View {
    /// Date-aligned values, newest last. `nil` is a gap, and internal gaps are preserved.
    let values: [Double?]
    var color: Color = .white
    var axis: (from: Double, to: Double)?
    var slots: Int = 7
    var width: CGFloat = 78
    var height: CGFloat = 26

    private var padded: [Double?] {
        let recent = Array(values.suffix(slots))
        let padding = [Double?](repeating: nil, count: max(0, slots - recent.count))
        return padding + recent
    }

    var body: some View {
        DitheredBars(
            values: padded,
            color: color,
            height: height,
            gap: 2,
            grid: 3,
            dotRadius: 0.6,
            minFraction: 0.12,
            axis: axis
        )
        .frame(width: width)
    }
}

/// The six-month average line.
///
/// A plain `Canvas` path rather than Swift Charts: it is a handful of points at a fixed
/// height, and it can never blow out its container or cost a chart's worth of generics.
struct TrendLine: View {
    let points: [Double?]
    var color: Color = .white
    var height: CGFloat = 150
    var highlightIndex: Int?

    /// Horizontal inset, so the first and last dots aren't clipped by the canvas edge.
    static let horizontalInset: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let present = points.enumerated().compactMap { index, value in
                value.map { (index, $0) }
            }
            guard !present.isEmpty else { return }

            let values = present.map(\.1)
            guard let high = values.max(), let low = values.min() else { return }
            let span = max(high - low, 1e-6)
            let count = points.count
            let padY = max(6, size.height * 0.14)
            let padX = Self.horizontalInset

            func position(_ index: Int, _ value: Double) -> CGPoint {
                let x = count == 1
                    ? size.width / 2
                    : padX + (size.width - 2 * padX) * CGFloat(index) / CGFloat(count - 1)
                let y = size.height - padY - (size.height - 2 * padY) * CGFloat((value - low) / span)
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            for (step, entry) in present.enumerated() {
                let point = position(entry.0, entry.1)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(
                path,
                with: .color(color.opacity(highlightIndex == nil ? 1 : 0.3)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            for (index, value) in present {
                let point = position(index, value)
                let isHighlighted = highlightIndex == index
                let radius: CGFloat = isHighlighted ? 3.5 : 2.5
                let opacity: Double = (highlightIndex == nil || isHighlighted) ? 1 : 0.3

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(color.opacity(opacity))
                )
            }
        }
        .frame(height: height)
    }
}

#Preview("Bars") {
    VStack(alignment: .leading, spacing: 24) {
        DitheredBars(
            values: [812, 640, nil, 1180, 1420, 760, 690],
            axis: (0, 1500)
        )

        MiniDitheredBars(values: [812, 640, nil, 1180, 1420, 760, 690], axis: (0, 1500))

        TrendLine(points: [780, 820, nil, 910, 870, 760])
    }
    .padding(24)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
