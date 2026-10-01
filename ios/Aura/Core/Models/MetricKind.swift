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
                MetricBand(upperBound: 800, label: "Fresh", tint: .auraGreen),
                MetricBand(upperBound: 1200, label: "Stuffy", tint: .auraYellow),
                MetricBand(upperBound: 1600, label: "Poor", tint: .auraOrange),
                MetricBand(upperBound: .infinity, label: "Bad", tint: .auraRed),
            ]
        case .humidity:
            [
                MetricBand(upperBound: 20, label: "Very dry", tint: .auraRed),
                MetricBand(upperBound: 30, label: "Dry", tint: .auraOrange),
                MetricBand(upperBound: 40, label: "A bit dry", tint: .auraYellow),
                MetricBand(upperBound: 60, label: "Comfortable", tint: .auraGreen),
                MetricBand(upperBound: 70, label: "Humid", tint: .auraYellow),
                MetricBand(upperBound: 80, label: "Very humid", tint: .auraOrange),
                MetricBand(upperBound: .infinity, label: "Damp", tint: .auraRed),
            ]
        case .light:
            [
                MetricBand(upperBound: 20, label: "Dark", tint: .auraOrange),
                MetricBand(upperBound: 80, label: "Dim", tint: .auraYellow),
                MetricBand(upperBound: .infinity, label: "Bright", tint: .auraGreen),
            ]
        case .temperature:
            // Kept on a cold-to-hot ramp rather than a severity one: the thermal card uses it
            // for a background wash, where blue reading as "cold" is the point.
            [
                MetricBand(upperBound: 16, label: "Cold", tint: .auraBlue),
                MetricBand(upperBound: 19, label: "Cool", tint: .auraCyan),
                MetricBand(upperBound: 25, label: "Comfortable", tint: .auraGreen),
                MetricBand(upperBound: 28, label: "Warm", tint: .auraAmber),
                MetricBand(upperBound: .infinity, label: "Hot", tint: .auraRed),
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

    var explainer: String {
        switch self {
        case .co2:
            """
            Carbon dioxide builds up when a room is sealed and someone is breathing in it. \
            Outdoor air sits around 420 ppm. Above roughly 1000 ppm most people start to feel \
            drowsy and find it harder to concentrate; above 1600 ppm the room badly needs air.
            """
        case .temperature:
            """
            Measured by the SCD40 next to the CO₂ cell. The sensor sits inside its own \
            enclosure, so it usually reads a little warmer than the room.
            """
        case .humidity:
            """
            Relative humidity. Below 30% skin and eyes dry out; above 60% the room starts to \
            feel heavy. Between 40% and 60% is the sweet spot.
            """
        case .light:
            """
            Illuminance at the sensor, in lux. A dim living room is around 50 lux, a well lit \
            desk 300–500 lux, and an overcast day outdoors is well over 1000 lux.
            """
        }
    }
}

/// One severity step within a metric — everything below `upperBound` and above the previous band.
struct MetricBand: Hashable, Sendable {
    let upperBound: Double
    let label: String
    let tint: Color
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
