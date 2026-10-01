import SwiftUI

/// The one card: how the air is right now, in three rows.
///
/// Verdict and change sit on the same line, the number carries the card, and the matrix
/// underneath says where that number falls without needing an axis.
struct CO2Card: View {
    let value: Double?
    /// Quality word above the number — "Fresh", "Comfortable", "Stuffy".
    let verdict: String
    let tint: Color
    let footnote: String?
    /// Direction of `footnote`, when it describes a change. nil draws no arrow.
    let footnoteDirection: ChangeDirection?

    enum ChangeDirection {
        case up
        case down

        var symbol: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            }
        }

        /// Rising CO₂ is the bad direction, which is the opposite of most dashboards.
        var tint: Color {
            switch self {
            case .up: .auraOrange
            case .down: .auraGreen
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            reading
            DotMatrixBar(metric: .co2, value: value)
        }
        .padding(18)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verdict)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.auraPrimaryText)

            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                // Baseline alignment would hang a bare circle off the text baseline.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }

            Spacer(minLength: 10)

            change
        }
    }

    @ViewBuilder
    private var change: some View {
        if let footnote {
            HStack(spacing: 4) {
                if let footnoteDirection {
                    Image(systemName: footnoteDirection.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(footnoteDirection.tint)
                }

                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(MetricKind.co2.format(value))
                .font(.system(size: 46, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.auraPrimaryText)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(MetricKind.co2.captionedUnit)
                .font(.footnote.weight(.medium))
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
        CO2Card(
            value: 712,
            verdict: "Comfortable",
            tint: .auraLime,
            footnote: "64 ppm in the last hour",
            footnoteDirection: .up
        )

        CO2Card(
            value: 1480,
            verdict: "Poor",
            tint: .auraOrange,
            footnote: "Peak 1,620 ppm",
            footnoteDirection: nil
        )

        CO2Card(
            value: nil,
            verdict: "No reading",
            tint: .auraSlate,
            footnote: nil,
            footnoteDirection: nil
        )
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
