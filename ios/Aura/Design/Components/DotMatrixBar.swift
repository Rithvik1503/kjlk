import SwiftUI

/// A dot-matrix level indicator — a dense grid of small bright cells, lit left to right.
///
/// Columns carry the reading: every column up to the current value is lit, the rest sit dark.
/// Each lit column takes the band colour at *its own* position on the scale, so the lit run is
/// a slice of the metric's own ramp rather than a flat block, and every lit cell blooms a
/// little so the grid reads as an emissive panel rather than a drawn chart.
struct DotMatrixBar: View {
    let metric: MetricKind
    /// Raw value, or nil when there is no reading — which leaves the whole grid dark.
    let value: Double?

    var columns: Int = 46
    var rows: Int = 4
    var cellSize: CGFloat = 3
    var rowSpacing: CGFloat = 2
    var cornerRadius: CGFloat = 0.75

    private var litColumns: Int {
        guard let value else { return 0 }
        // Round up so any reading above the floor lights at least one column.
        return Int((metric.position(of: value) * Double(columns)).rounded(.up))
            .clamped(to: 0...columns)
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<rows, id: \.self) { _ in
                row
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) level")
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit), \(metric.label(for: $0))" } ?? "No reading"
        )
    }

    private var row: some View {
        HStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { column in
                cell(column: column)
                    // Distributes the columns across whatever width the card gives us,
                    // while each cell itself stays square.
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(column: Int) -> some View {
        let isLit = column < litColumns
        let tint = tint(at: column)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isLit ? tint : Color.auraDotOff)
            .frame(width: cellSize, height: cellSize)
            .shadow(color: isLit ? tint.opacity(0.75) : .clear, radius: 2)
    }

    /// The band colour at this column's own position along the scale.
    private func tint(at column: Int) -> Color {
        let fraction = columns > 1 ? Double(column) / Double(columns - 1) : 0
        return metric.band(for: metric.value(atPosition: fraction)).tint
    }
}

#Preview("Dot matrix") {
    VStack(alignment: .leading, spacing: 26) {
        ForEach([480.0, 720.0, 1100.0, 1700.0], id: \.self) { value in
            VStack(alignment: .leading, spacing: 10) {
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
