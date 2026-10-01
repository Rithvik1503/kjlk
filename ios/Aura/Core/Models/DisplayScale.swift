import SwiftUI

/// A metric expressed in the units the user actually sees.
///
/// All of the physics stays in SI: bands, comfort scores and gradients are defined in Celsius,
/// ppm, percent and lux. Nothing downstream should convert anything by hand — a view asks for
/// a `DisplayScale` and then works entirely in display space, so a Fahrenheit chart gets
/// Fahrenheit axis ticks, Fahrenheit band colours and a Fahrenheit comfort band for free.
///
/// Converting after aggregating is safe because every conversion here is affine: the mean of
/// converted values equals the conversion of the mean.
struct DisplayScale: Equatable {
    let metric: MetricKind
    let unit: String
    let fractionDigits: Int
    let nominalRange: ClosedRange<Double>
    let comfortBand: ClosedRange<Double>?
    let bands: [MetricBand]

    /// Raw SI value to display value. For temperature this folds in the calibration offset.
    private let transform: @Sendable (Double) -> Double

    init(metric: MetricKind, temperatureUnit: TemperatureUnit, temperatureOffset: Double) {
        self.metric = metric
        self.unit = metric.unit(temperatureUnit)
        self.fractionDigits = metric.fractionDigits

        if metric == .temperature {
            // The offset corrects the sensor; the unit converts for the reader. Thresholds
            // defined against real room temperature only shift for the unit, not the offset.
            self.transform = { temperatureUnit.convert($0 + temperatureOffset) }
            let scale: @Sendable (Double) -> Double = { temperatureUnit.convert($0) }

            self.nominalRange = scale(metric.nominalRange.lowerBound)...scale(metric.nominalRange.upperBound)
            self.comfortBand = metric.comfortBand.map { scale($0.lowerBound)...scale($0.upperBound) }
            self.bands = metric.bands.map { band in
                MetricBand(
                    upperBound: band.upperBound.isFinite ? scale(band.upperBound) : .infinity,
                    label: band.label,
                    tint: band.tint
                )
            }
        } else {
            self.transform = { $0 }
            self.nominalRange = metric.nominalRange
            self.comfortBand = metric.comfortBand
            self.bands = metric.bands
        }
    }

    func convert(_ raw: Double) -> Double { transform(raw) }

    func convert(_ raw: Double?) -> Double? { raw.map(transform) }

    // MARK: - Interpretation

    func band(for displayValue: Double) -> MetricBand {
        bands.first { displayValue < $0.upperBound } ?? bands[bands.count - 1]
    }

    func tint(for displayValue: Double?) -> Color {
        guard let displayValue else { return .auraSlate }
        return band(for: displayValue).tint
    }

    func qualityLabel(for displayValue: Double?) -> String {
        guard let displayValue else { return "No data" }
        return band(for: displayValue).label
    }

    // MARK: - Formatting

    func format(_ displayValue: Double?) -> String {
        guard let displayValue else { return "––" }
        return displayValue.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    func formatWithUnit(_ displayValue: Double?) -> String {
        guard displayValue != nil else { return "––" }
        // Degrees sit tight against the number; everything else gets a space.
        let separator = unit.hasPrefix("°") ? "" : " "
        return format(displayValue) + separator + unit
    }

    // MARK: - Colour ramp

    /// Colour stops across `nominalRange`, used by scale bars and chart fills.
    var gradientStops: [Gradient.Stop] {
        let span = nominalRange.upperBound - nominalRange.lowerBound
        guard span > 0 else { return [Gradient.Stop(color: .auraSlate, location: 0)] }

        var stops: [Gradient.Stop] = []
        var previousUpper = nominalRange.lowerBound

        for band in bands {
            let start = max(previousUpper, nominalRange.lowerBound)
            guard start <= nominalRange.upperBound else { break }
            let end = min(band.upperBound, nominalRange.upperBound)

            stops.append(.init(color: band.tint, location: CGFloat((start - nominalRange.lowerBound) / span)))
            if end > start {
                stops.append(.init(color: band.tint, location: CGFloat((end - nominalRange.lowerBound) / span)))
            }
            previousUpper = band.upperBound
            if previousUpper >= nominalRange.upperBound { break }
        }

        if stops.isEmpty {
            stops = [.init(color: .auraSlate, location: 0), .init(color: .auraSlate, location: 1)]
        }
        if let last = stops.last, last.location < 1 {
            stops.append(.init(color: last.color, location: 1))
        }
        return stops
    }

    var gradient: LinearGradient {
        LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing)
    }

    /// Where a value sits across `nominalRange`, as 0...1, for positioning an indicator.
    func position(of displayValue: Double) -> Double {
        let span = nominalRange.upperBound - nominalRange.lowerBound
        guard span > 0 else { return 0.5 }
        return ((displayValue - nominalRange.lowerBound) / span).clamped(to: 0...1)
    }

    /// Evenly spaced tick values for the scale bar underneath a gradient.
    func ticks(count: Int = 5) -> [Double] {
        guard count > 1 else { return [nominalRange.lowerBound] }
        let step = (nominalRange.upperBound - nominalRange.lowerBound) / Double(count - 1)
        return (0..<count).map { nominalRange.lowerBound + Double($0) * step }
    }

    static func == (lhs: DisplayScale, rhs: DisplayScale) -> Bool {
        lhs.metric == rhs.metric
            && lhs.unit == rhs.unit
            && lhs.nominalRange == rhs.nominalRange
            && lhs.bands == rhs.bands
    }
}

extension Preferences {
    func scale(for metric: MetricKind) -> DisplayScale {
        DisplayScale(
            metric: metric,
            temperatureUnit: temperatureUnit,
            temperatureOffset: temperatureOffset
        )
    }
}
