import SwiftUI

/// A dense row of dots that fills to show where a reading sits on its scale.
///
/// Each lit dot is coloured by the value *at its own position*, not by the current reading, so
/// the filled run is a slice of the metric's own ramp — green at the left, climbing through
/// amber and into red as it extends. The dot under the reading is the brightest thing on the
/// card, and the unlit remainder stays dim enough to read as "not reached".
struct DottedBar: View {
    let metric: MetricKind
    /// Raw value, or nil when there is no reading — which draws the track unlit.
    let value: Double?

    var dotCount: Int = 36
    var dotSize: CGFloat = 7

    private var litCount: Int {
        guard let value else { return 0 }
        // Round up so any reading above the floor lights at least one dot.
        return Int((metric.position(of: value) * Double(dotCount)).rounded(.up))
            .clamped(to: 0...dotCount)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<dotCount, id: \.self) { index in
                dot(at: index)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: dotSize * 2.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) level")
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit), \(metric.label(for: $0))" } ?? "No reading"
        )
    }

    @ViewBuilder
    private func dot(at index: Int) -> some View {
        let isLit = index < litCount
        let isLeading = index == litCount - 1

        Circle()
            .fill(isLit ? tint(at: index) : Color.auraHairline)
            .frame(width: dotSize, height: dotSize)
            // Only the leading dot glows, so the row reads as a level rather than a light strip.
            .shadow(
                color: isLeading ? tint(at: index).opacity(0.9) : .clear,
                radius: isLeading ? 6 : 0
            )
            .scaleEffect(isLeading ? 1.25 : 1)
    }

    /// The band colour at this dot's own position along the scale.
    private func tint(at index: Int) -> Color {
        let fraction = dotCount > 1 ? Double(index) / Double(dotCount - 1) : 0
        return metric.band(for: metric.value(atPosition: fraction)).tint
    }
}

#Preview("Dotted bar") {
    VStack(spacing: 28) {
        ForEach([520.0, 760.0, 1150.0, 1750.0], id: \.self) { value in
            VStack(alignment: .leading, spacing: 10) {
                Text("\(Int(value)) ppm — \(MetricKind.co2.label(for: value))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DottedBar(metric: .co2, value: value)
            }
        }

        DottedBar(metric: .co2, value: nil)
    }
    .padding(24)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
