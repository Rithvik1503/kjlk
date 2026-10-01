import SwiftUI

/// One sensor: the number, its unit, how it has moved, and a marker showing where it stands.
///
/// Tapping opens the day's trace. The whole card is the target rather than the grid alone —
/// an 18pt-tall strip is a poor thing to ask a thumb to find.
struct MetricCard: View {
    let metric: MetricKind
    /// Raw value in the metric's own units, or nil when there is no reading.
    let value: Double?
    /// The span the grid covers, widened past the metric's default where readings demand it.
    let range: ClosedRange<Double>
    /// Movement over the last hour. Absent on a past day, which has no last hour.
    let change: MetricChange?
    /// True when the figure is a whole day's mean rather than a current reading.
    let isAverage: Bool
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
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows the day's readings")
        .accessibilityAddTraits(.isButton)
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(metric.format(value))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.auraPrimaryText)

            Text(metric.unitLabel)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.auraPrimaryText.opacity(0.5))

            Spacer(minLength: 8)

            trailing
        }
    }

    /// The hour's movement, or — on a past day — a note that the figure is a mean.
    @ViewBuilder
    private var trailing: some View {
        if isAverage {
            Text("DAY AVERAGE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.auraPrimaryText.opacity(0.35))
        } else if let change {
            HStack(spacing: 3) {
                Image(systemName: change.isRising ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))

                Text("\(metric.format(change.magnitude)) SINCE LAST HOUR")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .monospacedDigit()
            }
            // The arrow is what the number did; the colour is what that meant.
            .foregroundStyle(change.isWorse ? Color.auraRed : Color.auraGreen)
            .lineLimit(1)
        }
    }

    private var accessibilityValue: String {
        guard let value else { return "No reading" }

        var parts = ["\(metric.format(value)) \(metric.unit)", metric.label(for: value)]
        if isAverage {
            parts.append("day average")
        } else if let change {
            let direction = change.isRising ? "up" : "down"
            let sense = change.isWorse ? "worse" : "better"
            parts.append("\(direction) \(metric.format(change.magnitude)) since last hour, \(sense)")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Cards") {
    VStack(spacing: 14) {
        MetricCard(
            metric: .co2,
            value: 712,
            range: MetricKind.co2.scale,
            change: MetricChange(delta: 64, isWorse: true),
            isAverage: false
        ) {}

        MetricCard(
            metric: .humidity,
            value: 47,
            range: MetricKind.humidity.scale,
            change: MetricChange(delta: -4, isWorse: false),
            isAverage: false
        ) {}

        MetricCard(
            metric: .light,
            value: 284,
            range: MetricKind.light.scale,
            change: nil,
            isAverage: true
        ) {}

        MetricCard(
            metric: .co2,
            value: nil,
            range: MetricKind.co2.scale,
            change: nil,
            isAverage: false
        ) {}
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
