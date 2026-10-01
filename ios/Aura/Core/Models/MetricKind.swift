import SwiftUI

/// The four things the room monitor measures.
enum MetricKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case co2
    case temperature
    case humidity
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .co2: "Carbon dioxide"
        case .temperature: "Temperature"
        case .humidity: "Humidity"
        case .light: "Light"
        }
    }

    var unit: String {
        switch self {
        case .co2: "ppm"
        case .temperature: "°C"
        case .humidity: "%"
        case .light: "lux"
        }
    }

    /// The unit as it appears on screen. Set as a label rather than prose, so it is capitalised.
    var unitLabel: String { unit.uppercased() }

    var fractionDigits: Int {
        switch self {
        case .co2, .humidity, .light: 0
        case .temperature: 1
        }
    }

    /// The span the indicator covers end to end.
    ///
    /// Light's ceiling is a floor, not a limit — direct sun will exceed it, so the store
    /// widens the range when a reading does (see `AuraStore.scale(for:)`).
    var scale: ClosedRange<Double> {
        switch self {
        case .co2: 400...5000
        case .temperature: 10...35
        case .humidity: 0...100
        case .light: 0...5000
        }
    }

    /// Severity steps, lowest threshold first.
    ///
    /// These encode *how bad* a value is, not where it sits — green through red — so a metric
    /// that is bad at both ends, like humidity, walks red → green → red as it climbs.
    var bands: [MetricBand] {
        switch self {
        case .co2:
            [
                MetricBand(upperBound: 800, label: "Fresh", tint: .auraGreen, severity: 0),
                MetricBand(upperBound: 1200, label: "Stuffy", tint: .auraYellow, severity: 1),
                MetricBand(upperBound: 1600, label: "Poor", tint: .auraOrange, severity: 2),
                MetricBand(upperBound: .infinity, label: "Bad", tint: .auraRed, severity: 3),
            ]
        case .humidity:
            [
                MetricBand(upperBound: 20, label: "Very dry", tint: .auraRed, severity: 3),
                MetricBand(upperBound: 30, label: "Dry", tint: .auraOrange, severity: 2),
                MetricBand(upperBound: 40, label: "A bit dry", tint: .auraYellow, severity: 1),
                MetricBand(upperBound: 60, label: "Comfortable", tint: .auraGreen, severity: 0),
                MetricBand(upperBound: 70, label: "Humid", tint: .auraYellow, severity: 1),
                MetricBand(upperBound: 80, label: "Very humid", tint: .auraOrange, severity: 2),
                MetricBand(upperBound: .infinity, label: "Damp", tint: .auraRed, severity: 3),
            ]
        case .light:
            [
                MetricBand(upperBound: 20, label: "Dark", tint: .auraOrange, severity: 2),
                MetricBand(upperBound: 80, label: "Dim", tint: .auraYellow, severity: 1),
                MetricBand(upperBound: .infinity, label: "Bright", tint: .auraGreen, severity: 0),
            ]
        case .temperature:
            // Kept on a cold-to-hot ramp rather than a severity one: the thermal card uses it
            // for a background wash, where blue reading as "cold" is the point.
            [
                MetricBand(upperBound: 16, label: "Cold", tint: .auraBlue, severity: 2),
                MetricBand(upperBound: 19, label: "Cool", tint: .auraCyan, severity: 1),
                MetricBand(upperBound: 25, label: "Comfortable", tint: .auraGreen, severity: 0),
                MetricBand(upperBound: 28, label: "Warm", tint: .auraAmber, severity: 1),
                MetricBand(upperBound: .infinity, label: "Hot", tint: .auraRed, severity: 2),
            ]
        }
    }

    func band(for value: Double) -> MetricBand {
        bands.first { value < $0.upperBound } ?? bands[bands.count - 1]
    }

    func tint(for value: Double?) -> Color {
        guard let value else { return .auraSlate }
        return band(for: value).tint
    }

    func label(for value: Double?) -> String {
        guard let value else { return "No reading" }
        return band(for: value).label
    }

    /// Smallest movement worth reporting. Below this it is sensor noise, not a change.
    var changeThreshold: Double {
        switch self {
        case .co2: 15
        case .temperature: 0.3
        case .humidity: 2
        case .light: 20
        }
    }

    /// How far from ideal a value is, on an arbitrary but monotonic scale.
    ///
    /// The band rank says which step a value is on; this says which way it moved within one,
    /// so an hour that went 620 → 780 ppm still reads as getting worse.
    func distanceFromIdeal(_ value: Double) -> Double {
        switch self {
        case .co2: value
        case .humidity: abs(value - 50)
        case .temperature: abs(value - 22)
        // Darker is worse, up to the point where there is plenty of light either way.
        case .light: -min(value, 500)
        }
    }

    /// Where a value sits across `range`, as 0...1.
    func position(of value: Double, in range: ClosedRange<Double>? = nil) -> Double {
        let range = range ?? scale
        let span = range.upperBound - range.lowerBound
        guard span > 0, value.isFinite else { return 0 }
        return ((value - range.lowerBound) / span).clamped(to: 0...1)
    }

    func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "––" }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Band colours laid out across `domain`, bottom to top — for colouring a chart's line by
    /// height, so it shifts green → yellow → red as the trace climbs through the thresholds.
    func gradientStops(over domain: ClosedRange<Double>) -> [Gradient.Stop] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else {
            return [Gradient.Stop(color: tint(for: domain.lowerBound), location: 0)]
        }

        var stops: [Gradient.Stop] = []
        var lower = domain.lowerBound

        for band in bands {
            guard band.upperBound > lower else { continue }   // entirely below the visible range
            let upper = min(band.upperBound, domain.upperBound)
            guard upper > lower else { break }                // past the top of the range

            let start = CGFloat((lower - domain.lowerBound) / span)
            let end = CGFloat((upper - domain.lowerBound) / span)
            stops.append(Gradient.Stop(color: band.tint, location: start))
            stops.append(Gradient.Stop(color: band.tint, location: end))

            lower = upper
            if lower >= domain.upperBound { break }
        }

        if stops.count < 2 {
            let colour = tint(for: (domain.lowerBound + domain.upperBound) / 2)
            return [
                Gradient.Stop(color: colour, location: 0),
                Gradient.Stop(color: colour, location: 1),
            ]
        }
        return stops
    }
}

/// A metric's movement over some window — how far it went, and whether that was for the worse.
///
/// The two are separate because they disagree: CO₂ falling is an improvement, humidity falling
/// might be either, and the arrow should show what the number did while the colour shows what
/// it meant.
struct MetricChange: Hashable, Sendable {
    let delta: Double
    let isWorse: Bool

    var isRising: Bool { delta > 0 }
    var magnitude: Double { abs(delta) }
}

/// One severity step within a metric — everything below `upperBound` and above the previous band.
struct MetricBand: Hashable, Sendable {
    let upperBound: Double
    let label: String
    let tint: Color
    /// 0 is ideal, 3 is bad. Ordering the bands by position wouldn't work for humidity or
    /// temperature, which are bad at both ends.
    let severity: Int
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
