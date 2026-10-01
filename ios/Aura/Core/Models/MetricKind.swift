import SwiftUI

/// The four things the room monitor measures.
///
/// Everything visual hangs off this type: the gradient behind a chart, the colour of a
/// value, the scale a range bar draws, the copy in a detail sheet. Adding a fifth sensor
/// means adding a case here and the UI follows.
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

    var shortTitle: String {
        switch self {
        case .co2: "CO₂"
        case .temperature: "Temp"
        case .humidity: "Humidity"
        case .light: "Light"
        }
    }

    var symbol: String {
        switch self {
        case .co2: "aqi.medium"
        case .temperature: "thermometer.medium"
        case .humidity: "humidity.fill"
        case .light: "sun.max.fill"
        }
    }

    /// Unit shown next to a value. Temperature is resolved against the user's preference.
    func unit(_ temperatureUnit: TemperatureUnit = .celsius) -> String {
        switch self {
        case .co2: "ppm"
        case .temperature: temperatureUnit.suffix
        case .humidity: "%"
        case .light: "lux"
        }
    }

    /// Decimal places used when printing a value.
    var fractionDigits: Int {
        switch self {
        case .co2: 0
        case .temperature: 1
        case .humidity: 0
        case .light: 0
        }
    }

    /// The span a range bar or chart axis covers when no data argues otherwise.
    var nominalRange: ClosedRange<Double> {
        switch self {
        case .co2: 400...2000
        case .temperature: 10...35
        case .humidity: 0...100
        case .light: 0...1000
        }
    }

    /// What "good" looks like — drawn as a soft band behind the trend line.
    var comfortBand: ClosedRange<Double>? {
        switch self {
        case .co2: 400...800
        case .temperature: 20...24
        case .humidity: 40...60
        case .light: nil
        }
    }

    /// Ordered quality bands, lowest threshold first. Used for colour and for plain-language labels.
    var bands: [MetricBand] {
        switch self {
        case .co2:
            [
                MetricBand(upperBound: 600, label: "Fresh", tint: .auraGreen),
                MetricBand(upperBound: 800, label: "Good", tint: .auraLime),
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

    // Interpreting a value — which band it falls in, what colour that is, what to call it —
    // lives on `DisplayScale`, because it has to happen in the units on screen. Everything
    // here defines the metric in SI and leaves presentation to that type.

    /// Short explainer shown in the metric detail sheet.
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
            Measured by the SCD40 next to the CO₂ cell. The sensor sits inside its own enclosure, \
            so it usually reads a little warmer than the room — use the offset in Settings to \
            correct it against a thermometer you trust.
            """
        case .humidity:
            """
            Relative humidity. Below 30% skin, eyes and wooden furniture dry out and static \
            builds up. Above 60% the room starts to feel heavy and mould gets comfortable. \
            Between 40% and 60% is the sweet spot.
            """
        case .light:
            """
            Illuminance at the sensor, in lux. A dim living room is around 50 lux, a well lit \
            desk 300–500 lux, and an overcast day outdoors is well over 1000 lux. Useful for \
            seeing when a room actually gets used.
            """
        }
    }

    /// Practical advice shown under the explainer, keyed off the current band.
    func advice(for value: Double?) -> String? {
        guard let value else { return nil }
        switch self {
        case .co2:
            if value < 800 { return "Nothing to do — the air in here is turning over nicely." }
            if value < 1200 { return "Crack a window or open the door for a few minutes." }
            return "Ventilate now. Open a window wide, or step out for a bit."
        case .temperature:
            if value < 18 { return "On the cold side for sitting still." }
            if value > 26 { return "Warm enough to affect sleep and concentration." }
            return nil
        case .humidity:
            if value < 30 { return "Dry air. A bowl of water near a radiator helps more than you'd think." }
            if value > 65 { return "Damp. Worth running a fan or dehumidifier." }
            return nil
        case .light:
            if value < 50 { return "Dark enough that reading will tire your eyes." }
            return nil
        }
    }
}

/// One quality step within a metric — everything below `upperBound` and above the previous band.
struct MetricBand: Hashable, Sendable {
    let upperBound: Double
    let label: String
    let tint: Color
}

/// Celsius or Fahrenheit, chosen in Settings.
enum TemperatureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var suffix: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    var title: String {
        switch self {
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    /// Converts a Celsius reading into this unit.
    func convert(_ celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// Converts a span expressed in Celsius — a difference, not a point on the scale.
    func convertDelta(_ celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5
        }
    }
}
