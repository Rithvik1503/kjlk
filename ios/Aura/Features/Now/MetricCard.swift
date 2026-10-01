import SwiftUI

/// One sensor: the number, its unit, and where it falls on its own scale.
///
/// The same card serves all four metrics. Nothing says in words whether the number is good —
/// that is the matrix's job, by how far it runs and what colour it reaches.
struct MetricCard: View {
    let metric: MetricKind
    /// Raw value in the metric's own units, or nil when there is no reading.
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            reading
            DotMatrixBar(metric: metric, value: value)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.auraCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(metric.format(value))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.auraPrimaryText)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(metric.captionedUnit)
                // Kept below the figure's 15pt so the unit still reads as secondary to it.
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit)" } ?? "No reading"
        )
    }
}

#Preview("Cards") {
    VStack(spacing: 14) {
        MetricCard(metric: .co2, value: 712)
        MetricCard(metric: .temperature, value: 22.4)
        MetricCard(metric: .humidity, value: 47)
        MetricCard(metric: .light, value: 284)
        MetricCard(metric: .co2, value: nil)
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
