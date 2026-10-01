import SwiftUI

/// The four things the room monitor measures.
///
/// Only CO₂ is on screen today, but readings still carry all four, so the others stay defined
/// here — re-surfacing one is a view, not a schema change.
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

    /// How the value reads next to the number — "CO₂ ppm" under the big figure.
    var captionedUnit: String {
        switch self {
        case .co2: "CO₂ ppm"
        case .temperature: "Temperature °C"
        case .humidity: "Humidity %"
        case .light: "Light lux"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .co2, .humidity, .light: 0
        case .temperature: 1
        }
    }

    /// The span the indicator covers end to end.
    var scale: ClosedRange<Double> {
        switch self {
        case .co2: 400...2000
        case .temperature: 10...35
        case .humidity: 0...100
        case .light: 0...1000
        }
    }

    /// Quality steps, lowest threshold first.
    var bands: [MetricBand] {
        switch self {
        case .co2:
            [
                MetricBand(upperBound: 600, label: "Fresh", tint: .auraGreen),
                MetricBand(upperBound: 800, label: "Comfortable", tint: .auraLime),
                MetricBand(upperBound: 1200, label: "Stuffy", tint: .auraAmber),
                MetricBand(upperBound: 1600, label: "Poor", tint: .auraOrange),
                MetricBand(upperBound: 2000, label: "Bad", tint: .auraRed),
                MetricBand(upperBound: .infinity, label: "Severe", tint: .auraViolet),
            ]
        case .temperature:
            [
                MetricBand(upperBound: 16, label: "Cold", tint: .auraBlue),
                MetricBand(upperBound: 19, label: "Cool", tint: .auraCyan),
                MetricBand(upperBound: 25, label: "Comfortable", tint: .auraGreen),
                MetricBand(upperBound: 28, label: "Warm", tint: .auraAmber),
                MetricBand(upperBound: .infinity, label: "Hot", tint: .auraRed),
            ]
        case .humidity:
            [
                MetricBand(upperBound: 30, label: "Dry", tint: .auraAmber),
                MetricBand(upperBound: 40, label: "A bit dry", tint: .auraLime),
                MetricBand(upperBound: 60, label: "Comfortable", tint: .auraGreen),
                MetricBand(upperBound: 70, label: "Humid", tint: .auraCyan),
                MetricBand(upperBound: .infinity, label: "Very humid", tint: .auraBlue),
            ]
        case .light:
            [
                MetricBand(upperBound: 10, label: "Dark", tint: .auraIndigo),
                MetricBand(upperBound: 80, label: "Dim", tint: .auraViolet),
                MetricBand(upperBound: 300, label: "Soft", tint: .auraCyan),
                MetricBand(upperBound: 800, label: "Bright", tint: .auraAmber),
                MetricBand(upperBound: .infinity, label: "Very bright", tint: .auraYellow),
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

    /// Where a value sits across `scale`, as 0...1.
    func position(of value: Double) -> Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0, value.isFinite else { return 0 }
        return ((value - scale.lowerBound) / span).clamped(to: 0...1)
    }

    /// The value at a fraction along `scale` — used to colour each dot of the indicator.
    func value(atPosition fraction: Double) -> Double {
        scale.lowerBound + fraction.clamped(to: 0...1) * (scale.upperBound - scale.lowerBound)
    }

    func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "––" }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
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

/// One quality step within a metric — everything below `upperBound` and above the previous band.
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
