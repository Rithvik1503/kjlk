import SwiftUI

/// The other three sensors, in one card under the CO₂ reading.
///
/// Temperature and humidity come from the SCD40, light from the BH1750. Each value carries a
/// dot in its own band colour, which is the only thing saying whether the number is good — the
/// same job the matrix does for CO₂.
struct SensorRow: View {
    /// Raw values keyed by metric; a missing entry draws as "––".
    let values: [MetricKind: Double]

    private let metrics: [MetricKind] = [.temperature, .humidity, .light]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 1, height: 28)
                }

                column(for: metric)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.auraCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func column(for metric: MetricKind) -> some View {
        let value = values[metric]

        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Circle()
                    .fill(metric.tint(for: value))
                    .frame(width: 5, height: 5)

                Text(metric.shortTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.format(value))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.auraPrimaryText)

                Text(metric.unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(
            value.map { "\(metric.format($0)) \(metric.unit), \(metric.label(for: $0))" } ?? "No reading"
        )
    }
}

#Preview("Sensors") {
    VStack(spacing: 16) {
        SensorRow(values: [.temperature: 22.4, .humidity: 47, .light: 284])
        SensorRow(values: [.temperature: 29.1, .humidity: 24, .light: 4])
        SensorRow(values: [:])
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
