import SwiftUI

/// The one card: the CO₂ reading, and where it falls.
///
/// No verdict, no timestamp, no commentary — the matrix already says whether the number is
/// good, by how far it runs and what colour it gets there.
struct CO2Card: View {
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            reading
            DotMatrixBar(metric: .co2, value: value)
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(MetricKind.co2.format(value))
                .font(.system(size: 36, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.auraPrimaryText)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(MetricKind.co2.captionedUnit)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carbon dioxide")
        .accessibilityValue(
            value.map { "\(MetricKind.co2.format($0)) parts per million" } ?? "No reading"
        )
    }
}

#Preview("Card") {
    VStack(spacing: 16) {
        CO2Card(value: 712)
        CO2Card(value: 1480)
        CO2Card(value: nil)
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
