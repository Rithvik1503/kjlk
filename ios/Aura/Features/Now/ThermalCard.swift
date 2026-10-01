import SwiftUI

/// Temperature, given more room than the other sensors.
///
/// A large light figure on the left, and on the right the day's average with how it compares
/// to the week before it.
struct ThermalCard: View {
    /// Current temperature in °C, or the day's average when viewing a past day.
    let temperature: Double?
    /// Mean across the whole selected day.
    let dayAverage: Double?
    /// "Hotter than usual", "About usual", or a plain description when there is no baseline.
    let comparison: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            figure

            VStack(alignment: .leading, spacing: 4) {
                Text(averageText)
                    .font(.headline)
                    .foregroundStyle(Color.auraPrimaryText)

                Text(comparison)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)

            Spacer(minLength: 0)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal reading")
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
        return "\(now) degrees. \(averageText). \(comparison)."
    }
}

#Preview("Thermal") {
    VStack(spacing: 16) {
        ThermalCard(temperature: 25, dayAverage: 21.4, comparison: "Hotter than usual")
        ThermalCard(temperature: 17, dayAverage: 18.2, comparison: "Colder than usual")
        ThermalCard(temperature: 22, dayAverage: 22.1, comparison: "Comfortable")
        ThermalCard(temperature: nil, dayAverage: nil, comparison: "No readings")
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
