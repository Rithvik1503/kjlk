import SwiftUI

/// A dot-matrix level indicator — a dense grid of small bright cells, lit left to right.
///
/// Columns carry the reading: every column up to the current value is lit, the rest sit dark.
/// Each lit column takes the band colour at *its own* position on the scale, so the lit run is
/// a slice of the metric's own ramp rather than a flat block, and the lit cells bloom so the
/// grid reads as an emissive panel rather than a drawn chart.
///
/// Drawn in a `Canvas` rather than as a grid of `Shape` views: at this density a stack would
/// be hundreds of views per card, each carrying its own shadow, and four cards means a few
/// thousand. One canvas draws the same thing in two passes.
struct DotMatrixBar: View {
    let metric: MetricKind
    /// Raw value, or nil when there is no reading — which leaves the whole grid dark.
    let value: Double?

    var columns: Int = 96
    var rows: Int = 6
    var height: CGFloat = 18
    /// Cell size as a fraction of the gap between cell centres. Much above 0.7 and the cells
    /// touch, turning the grid into a solid bar.
    var fillRatio: CGFloat = 0.6

    private var litColumns: Int {
        guard let value else { return 0 }
        // Round up so any reading above the floor lights at least one column.
        return Int((metric.position(of: value) * Double(columns)).rounded(.up))
            .clamped(to: 0...columns)
    }

    var body: some View {
        Canvas { context, size in
            guard columns > 0, rows > 0, size.width > 0, size.height > 0 else { return }

            let pitchX = size.width / CGFloat(columns)
            let pitchY = size.height / CGFloat(rows)
            let diameter = max(min(pitchX, pitchY) * fillRatio, 0.5)

            drawUnlit(in: &context, pitchX: pitchX, pitchY: pitchY, diameter: diameter)

            guard litColumns > 0 else { return }

            // Bloom first, then the same cells sharp on top, so the glow sits behind each dot
            // rather than washing it out.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: diameter * 0.9))
                layer.opacity = 0.85
                drawLit(in: &layer, pitchX: pitchX, pitchY: pitchY, diameter: diameter * 1.3)
            }
            drawLit(in: &context, pitchX: pitchX, pitchY: pitchY, diameter: diameter)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) level")
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit), \(metric.label(for: $0))" } ?? "No reading"
        )
    }

    private func drawUnlit(
        in context: inout GraphicsContext,
        pitchX: CGFloat,
        pitchY: CGFloat,
        diameter: CGFloat
    ) {
        guard litColumns < columns else { return }

        var path = Path()
        for column in litColumns..<columns {
            for row in 0..<rows {
                path.addPath(cell(column: column, row: row, pitchX: pitchX, pitchY: pitchY, diameter: diameter))
            }
        }
        context.fill(path, with: .color(.auraDotOff))
    }

    /// One fill per column, since the colour only varies along the x axis.
    private func drawLit(
        in context: inout GraphicsContext,
        pitchX: CGFloat,
        pitchY: CGFloat,
        diameter: CGFloat
    ) {
        for column in 0..<litColumns {
            var path = Path()
            for row in 0..<rows {
                path.addPath(cell(column: column, row: row, pitchX: pitchX, pitchY: pitchY, diameter: diameter))
            }
            context.fill(path, with: .color(tint(at: column)))
        }
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

    /// The band colour at this column's own position along the scale.
    private func tint(at column: Int) -> Color {
        let fraction = columns > 1 ? Double(column) / Double(columns - 1) : 0
        return metric.band(for: metric.value(atPosition: fraction)).tint
    }
}

#Preview("Dot matrix") {
    VStack(alignment: .leading, spacing: 22) {
        ForEach([480.0, 720.0, 1100.0, 1700.0], id: \.self) { value in
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int(value)) ppm — \(MetricKind.co2.label(for: value))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DotMatrixBar(metric: .co2, value: value)
            }
        }

        DotMatrixBar(metric: .co2, value: nil)
    }
    .padding(24)
    .background(Color.auraCard)
    .preferredColorScheme(.dark)
}
