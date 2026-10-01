import SwiftUI

/// The one card: how the air is right now, in four lines.
///
/// Reads top to bottom as verdict → number → level → what changed, which is the order you'd
/// answer "how's the air in here" out loud.
struct CO2Card: View {
    let value: Double?
    /// Quality word above the number — "Fresh", "Comfortable", "Stuffy".
    let verdict: String
    let tint: Color
    let footnote: String?
    /// Direction of `footnote`, when it describes a change. nil draws no arrow.
    let footnoteDirection: ChangeDirection?
    let onInfo: () -> Void

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
        VStack(alignment: .leading, spacing: 22) {
            header
            reading
            DottedBar(metric: .co2, value: value)
            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.auraSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(verdict)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.auraPrimaryText)

            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)

            Spacer(minLength: 8)

            Button(action: onInfo) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityLabel("About carbon dioxide")
        }
        .accessibilityElement(children: .combine)
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MetricKind.co2.format(value))
                .font(.system(size: 56, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundStyle(Color.auraPrimaryText)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(MetricKind.co2.captionedUnit)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carbon dioxide")
        .accessibilityValue(
            value.map { "\(MetricKind.co2.format($0)) parts per million" } ?? "No reading"
        )
    }

    @ViewBuilder
    private var footer: some View {
        if let footnote {
            HStack(spacing: 6) {
                if let footnoteDirection {
                    Image(systemName: footnoteDirection.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(footnoteDirection.tint)
                }

                Text(footnote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Card") {
    VStack(spacing: 20) {
        CO2Card(
            value: 712,
            verdict: "Comfortable",
            tint: .auraLime,
            footnote: "64 ppm in the last hour",
            footnoteDirection: .up,
            onInfo: {}
        )

        CO2Card(
            value: 1480,
            verdict: "Poor",
            tint: .auraOrange,
            footnote: "Peak 1,620 ppm · 284 readings",
            footnoteDirection: nil,
            onInfo: {}
        )

        CO2Card(
            value: nil,
            verdict: "No reading",
            tint: .auraSlate,
            footnote: nil,
            footnoteDirection: nil,
            onInfo: {}
        )
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
