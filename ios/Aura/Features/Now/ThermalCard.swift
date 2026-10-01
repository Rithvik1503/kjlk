import SwiftUI

/// Temperature, leading the screen unboxed.
///
/// A large light figure, and set to its right the day's average. No card around it — it is
/// the first thing on the page, and a box would put it on the same footing as the sensors
/// below rather than above them.
struct ThermalCard: View {
    /// Current temperature in °C, or the day's average when viewing a past day.
    let temperature: Double?
    /// Mean across the whole selected day.
    let dayAverage: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            figure

            Text(averageText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                // Sits against the lower half of the figure rather than its cap height, so
                // the pair reads as one block instead of two things starting at once.
                .padding(.top, 36)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperature")
        .accessibilityValue(accessibilityValue)
    }

    /// Whole degrees, with the symbol riding at the cap height of the digits.
    private var figure: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(wholeDegrees)
                .font(.system(size: 58, weight: .thin))
                .monospacedDigit()

            Text("°")
                .font(.system(size: 28, weight: .thin))
                .padding(.top, 4)
        }
        .foregroundStyle(Color.auraPrimaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        // Nudged off the left edge, so the figure sits nearer the middle of the pair.
        .padding(.leading, 14)
    }

    private var wholeDegrees: String {
        guard let temperature else { return "––" }
        return temperature.formatted(.number.precision(.fractionLength(0)))
    }

    private var averageText: String {
        guard let dayAverage else { return "No average yet" }
        let value = dayAverage.formatted(.number.precision(.fractionLength(1)))
        return "Day's average \(value)°"
    }

    private var accessibilityValue: String {
        guard let temperature else { return "No reading" }
        let now = temperature.formatted(.number.precision(.fractionLength(1)))
        return "\(now) degrees. \(averageText)."
    }
}

#Preview("Thermal") {
    VStack(spacing: 24) {
        ThermalCard(temperature: 25, dayAverage: 21.4)
        ThermalCard(temperature: 17, dayAverage: 18.2)
        ThermalCard(temperature: nil, dayAverage: nil)
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
