import SwiftUI

/// One sensor: the number, its unit, and a marker showing where it stands.
///
/// Tapping opens the day's trace. The whole card is the target rather than the grid alone —
/// a 18pt-tall strip is a poor thing to ask a thumb to find.
struct MetricCard: View {
    let metric: MetricKind
    /// Raw value in the metric's own units, or nil when there is no reading.
    let value: Double?
    /// The span the grid covers, widened past the metric's default where readings demand it.
    let range: ClosedRange<Double>
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                reading
                DotMatrixBar(metric: metric, value: value, range: range)
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
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit), \(metric.label(for: $0))" } ?? "No reading"
        )
        .accessibilityHint("Shows the day's readings")
        .accessibilityAddTraits(.isButton)
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric.format(value))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(metric.unitLabel)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.auraPrimaryText.opacity(0.5))
        }
        .foregroundStyle(Color.auraPrimaryText)
    }
}

#Preview("Cards") {
    VStack(spacing: 14) {
        MetricCard(metric: .co2, value: 712, range: MetricKind.co2.scale) {}
        MetricCard(metric: .co2, value: 2400, range: MetricKind.co2.scale) {}
        MetricCard(metric: .humidity, value: 47, range: MetricKind.humidity.scale) {}
        MetricCard(metric: .light, value: 284, range: MetricKind.light.scale) {}
        MetricCard(metric: .co2, value: nil, range: MetricKind.co2.scale) {}
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
