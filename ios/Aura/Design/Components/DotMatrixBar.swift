import SwiftUI

/// A dense grid of dim cells with a bright marker at the current reading.
///
/// The grid itself carries no colour — colour would imply every position means something, and
/// it doesn't. Only the neighbourhood of the marker is tinted, by the severity of the reading
/// standing there: green when it's fine, through yellow and orange, red when it isn't. The
/// wash falls off with distance, so the eye lands on the marker rather than the spread.
///
/// Drawn in a `Canvas` rather than as a grid of `Shape` views: at this density a stack would
/// be hundreds of views per card, and there are three cards.
struct DotMatrixBar: View {
    let metric: MetricKind
    /// Raw value, or nil when there is no reading — which leaves the grid dark and unmarked.
    let value: Double?
    /// The span the grid covers. Defaults to the metric's own, which the store widens for
    /// light when a reading exceeds it.
    var range: ClosedRange<Double>?

    var columns: Int = 96
    var rows: Int = 6
    var height: CGFloat = 18
    /// Cell size as a fraction of the gap between cell centres.
    var fillRatio: CGFloat = 0.6
    /// How far the tint spreads from the marker, as a fraction of the full width.
    var falloff: CGFloat = 0.13

    private var effectiveRange: ClosedRange<Double> { range ?? metric.scale }

    /// Column the marker stands in, or nil when there is nothing to mark.
    private var markerColumn: Double? {
        guard let value else { return nil }
        return metric.position(of: value, in: effectiveRange) * Double(columns - 1)
    }

    private var tint: Color {
        metric.tint(for: value)
    }

    var body: some View {
        Canvas { context, size in
            guard columns > 0, rows > 0, size.width > 0, size.height > 0 else { return }

            let pitchX = size.width / CGFloat(columns)
            let pitchY = size.height / CGFloat(rows)
            let diameter = max(min(pitchX, pitchY) * fillRatio, 0.5)

            drawBed(in: &context, pitchX: pitchX, pitchY: pitchY, diameter: diameter)

            guard let markerColumn else { return }

            drawWash(
                in: &context,
                around: markerColumn,
                pitchX: pitchX,
                pitchY: pitchY,
                diameter: diameter
            )
            drawMarker(in: &context, at: markerColumn, pitchX: pitchX, size: size)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) level")
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit), \(metric.label(for: $0))" } ?? "No reading"
        )
    }

    /// Every cell, dim. One path, one fill.
    private func drawBed(
        in context: inout GraphicsContext,
        pitchX: CGFloat,
        pitchY: CGFloat,
        diameter: CGFloat
    ) {
        var path = Path()
        for column in 0..<columns {
            for row in 0..<rows {
                path.addPath(cell(column: column, row: row, pitchX: pitchX, pitchY: pitchY, diameter: diameter))
            }
        }
        context.fill(path, with: .color(.auraDotOff))
    }

    /// Cells near the marker, tinted and fading out with distance.
    private func drawWash(
        in context: inout GraphicsContext,
        around markerColumn: Double,
        pitchX: CGFloat,
        pitchY: CGFloat,
        diameter: CGFloat
    ) {
        let spread = max(Double(columns) * Double(falloff), 1)
        let first = Int((markerColumn - spread).rounded(.down)).clamped(to: 0...(columns - 1))
        let last = Int((markerColumn + spread).rounded(.up)).clamped(to: 0...(columns - 1))
        guard first <= last else { return }

        for column in first...last {
            let distance = abs(Double(column) - markerColumn) / spread
            guard distance <= 1 else { continue }

            // Eases out, so the tint concentrates on the marker instead of forming a block.
            let intensity = pow(1 - distance, 1.8)
            guard intensity > 0.01 else { continue }

            var path = Path()
            for row in 0..<rows {
                path.addPath(cell(column: column, row: row, pitchX: pitchX, pitchY: pitchY, diameter: diameter))
            }
            context.fill(path, with: .color(tint.opacity(intensity)))
        }
    }

    /// The marker itself: a dark gap to separate it from the grid, then a bright bar.
    private func drawMarker(
        in context: inout GraphicsContext,
        at markerColumn: Double,
        pitchX: CGFloat,
        size: CGSize
    ) {
        let centre = (markerColumn + 0.5) * pitchX
        let barWidth: CGFloat = 2
        let gapWidth = barWidth + 3

        let gap = CGRect(
            x: centre - gapWidth / 2,
            y: -2,
            width: gapWidth,
            height: size.height + 4
        )
        context.fill(Path(gap), with: .color(.auraCard))

        let bar = CGRect(
            x: centre - barWidth / 2,
            y: -1,
            width: barWidth,
            height: size.height + 2
        )
        let path = Path(roundedRect: bar, cornerRadius: barWidth / 2, style: .continuous)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(path, with: .color(tint))
        }
        context.fill(path, with: .color(.white))
    }

    private func cell(
        column: Int,
        row: Int,
        pitchX: CGFloat,
        pitchY: CGFloat,
        diameter: CGFloat
    ) -> Path {
        let rect = CGRect(
            x: (CGFloat(column) + 0.5) * pitchX - diameter / 2,
            y: (CGFloat(row) + 0.5) * pitchY - diameter / 2,
            width: diameter,
            height: diameter
        )
        return Path(roundedRect: rect, cornerRadius: diameter * 0.25, style: .continuous)
    }
}

#Preview("Dot matrix") {
    VStack(alignment: .leading, spacing: 22) {
        ForEach([620.0, 1050.0, 1500.0, 2400.0], id: \.self) { value in
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int(value)) ppm — \(MetricKind.co2.label(for: value))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DotMatrixBar(metric: .co2, value: value)
            }
        }

        DotMatrixBar(metric: .humidity, value: 47)
        DotMatrixBar(metric: .light, value: 280)
        DotMatrixBar(metric: .co2, value: nil)
    }
    .padding(24)
    .background(Color.auraCard)
    .preferredColorScheme(.dark)
}
