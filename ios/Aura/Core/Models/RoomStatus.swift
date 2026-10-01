import SwiftUI

/// A single verdict on the room, derived from the latest reading.
///
/// The dashboard leads with this: one number, one colour, one sentence. CO₂ dominates the
/// score because it is the metric that changes fastest and the one you can actually act on.
struct RoomStatus: Hashable, Sendable {
    /// 0 (bad) to 100 (ideal).
    let score: Double
    let headline: String
    let detail: String
    let tint: Color
    /// The metric dragging the score down, if any one of them clearly is.
    let limitingMetric: MetricKind?

    static let unknown = RoomStatus(
        score: 0,
        headline: "Waiting for the sensor",
        detail: "No readings have arrived yet.",
        tint: .auraSlate,
        limitingMetric: nil
    )

    static func evaluate(_ reading: Reading?) -> RoomStatus {
        guard let reading, reading.hasAnyValue else { return .unknown }

        var scores: [(metric: MetricKind, score: Double, weight: Double)] = []

        if let co2 = reading.co2 {
            scores.append((.co2, co2Score(co2), 0.55))
        }
        if let temperature = reading.temperature {
            scores.append((.temperature, temperatureScore(temperature), 0.25))
        }
        if let humidity = reading.humidity {
            scores.append((.humidity, humidityScore(humidity), 0.20))
        }

        guard !scores.isEmpty else { return .unknown }

        let totalWeight = scores.reduce(0) { $0 + $1.weight }
        let weighted = scores.reduce(0) { $0 + $1.score * $1.weight } / totalWeight

        // Only call out a weak link if it is meaningfully worse than the overall picture.
        let weakest = scores.min { $0.score < $1.score }
        let limiting = (weakest.map { $0.score < 70 && $0.score < weighted - 5 } ?? false) ? weakest?.metric : nil

        return RoomStatus(
            score: weighted,
            headline: headline(for: weighted),
            detail: detail(for: weighted, limiting: limiting, reading: reading),
            tint: tint(for: weighted),
            limitingMetric: limiting
        )
    }

    // MARK: - Per-metric scoring

    /// 420 ppm is outdoor air; 2000 ppm is a sealed room full of people.
    private static func co2Score(_ value: Double) -> Double {
        let curve = (value - 420) / (1800 - 420)
        return ((1 - curve) * 100).clamped(to: 0...100)
    }

    /// Peaks at 22 °C and falls away in both directions.
    private static func temperatureScore(_ value: Double) -> Double {
        let distance = abs(value - 22)
        return (100 - distance * 9).clamped(to: 0...100)
    }

    /// Peaks across 40–60% and falls away outside it.
    private static func humidityScore(_ value: Double) -> Double {
        if (40...60).contains(value) { return 100 }
        let distance = value < 40 ? 40 - value : value - 60
        return (100 - distance * 3.5).clamped(to: 0...100)
    }

    // MARK: - Copy

    private static func headline(for score: Double) -> String {
        switch score {
        case 85...: "Great air in here"
        case 70..<85: "Comfortable"
        case 50..<70: "Getting stuffy"
        case 30..<50: "Needs some air"
        default: "Open a window"
        }
    }

    private static func tint(for score: Double) -> Color {
        switch score {
        case 85...: .auraGreen
        case 70..<85: .auraLime
        case 50..<70: .auraAmber
        case 30..<50: .auraOrange
        default: .auraRed
        }
    }

    private static func detail(for score: Double, limiting: MetricKind?, reading: Reading) -> String {
        if let limiting, let value = reading.value(for: limiting), let advice = limiting.advice(for: value) {
            return advice
        }
        if score >= 85 {
            return "Everything is sitting where you'd want it."
        }
        if let co2 = reading.co2, let advice = MetricKind.co2.advice(for: co2) {
            return advice
        }
        return "Keep an eye on it."
    }
}
