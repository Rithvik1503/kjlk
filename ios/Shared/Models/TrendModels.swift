import Foundation
import SwiftUI

/// One bucket of history — a day or a month — flattened to the mean of each sensor.
struct MetricBucket: Identifiable, Hashable, Sendable {
    let bucket: Date
    let co2: Double?
    let temperature: Double?
    let humidity: Double?
    let light: Double?
    let sampleCount: Int

    var id: Date { bucket }

    func value(for metric: MetricKind) -> Double? {
        switch metric {
        case .co2: co2
        case .temperature: temperature
        case .humidity: humidity
        case .light: light
        }
    }
}

extension MetricBucket: Decodable {
    private enum CodingKeys: String, CodingKey {
        case bucket
        case co2 = "co2_ppm"
        case temperature = "temperature_c"
        case humidity = "humidity_percent"
        case light = "light_lux"
        case sampleCount = "sample_count"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let stamp = try container.decode(String.self, forKey: .bucket)
        guard let date = PostgresDate.parse(stamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bucket,
                in: container,
                debugDescription: "Unrecognised bucket timestamp \(stamp)"
            )
        }
        bucket = date

        co2 = try container.decodeIfPresent(Double.self, forKey: .co2)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        humidity = try container.decodeIfPresent(Double.self, forKey: .humidity)
        light = try container.decodeIfPresent(Double.self, forKey: .light)
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
    }
}

/// One bucket of history for one zone. Only the two metrics the Areas section shows.
struct ZoneBucket: Identifiable, Hashable, Sendable {
    let bucket: Date
    let zone: String
    let co2: Double?
    let humidity: Double?

    var id: String { "\(zone)@\(bucket.timeIntervalSince1970)" }

    func value(for metric: MetricKind) -> Double? {
        switch metric {
        case .co2: co2
        case .humidity: humidity
        // The section covers CO2 and humidity only; nothing asks for the others.
        case .temperature, .light: nil
        }
    }
}

extension ZoneBucket: Decodable {
    private enum CodingKeys: String, CodingKey {
        case bucket
        case zone
        case co2 = "co2_ppm"
        case humidity = "humidity_percent"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let stamp = try container.decode(String.self, forKey: .bucket)
        guard let date = PostgresDate.parse(stamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bucket,
                in: container,
                debugDescription: "Unrecognised bucket timestamp \(stamp)"
            )
        }
        bucket = date
        zone = try container.decodeIfPresent(String.self, forKey: .zone) ?? "Unlabelled"
        co2 = try container.decodeIfPresent(Double.self, forKey: .co2)
        humidity = try container.decodeIfPresent(Double.self, forKey: .humidity)
    }
}

/// How far back Trends looks, and at what resolution.
enum TrendWindow: Int, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case halfYear

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: "7 DAY"
        case .month: "MONTH"
        case .halfYear: "6 MONTH"
        }
    }

    /// How many bars or points the chart lays out.
    var slots: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .halfYear: 6
        }
    }

    /// Months rather than days, which also switches the chart from bars to a line.
    var isMonthly: Bool { self == .halfYear }

    var bucketUnit: String { isMonthly ? "month" : "day" }

    /// Heading above the chart.
    var resolutionLabel: String { isMonthly ? "Monthly" : "Daily" }

    /// Label on the right of that heading.
    var sampleLabel: String {
        switch self {
        case .week: "7 DAYS"
        case .month: "30 DAYS"
        case .halfYear: "6 MONTHS"
        }
    }

    /// Prefix on the period-average line — "7D AVG 812 PPM".
    var averageLabel: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .halfYear: "6M"
        }
    }
}

/// Fixed y-axis for a metric's trend chart.
///
/// Bars are drawn against this rather than the window's own min and max, so a bar's height
/// means the same thing in every window and a quiet week doesn't get stretched to look like a
/// dramatic one.
struct TrendScale: Sendable {
    /// Axis bottom. Zero except where it would squash the signal flat.
    var from: Double = 0
    /// Axis top never falls below this.
    var atLeast: Double
    /// Headroom above the observed maximum once it passes `atLeast`.
    var buffer: Double = 0

    func top(observedMax: Double?) -> Double {
        guard let observedMax, observedMax > atLeast else { return atLeast }
        return (observedMax + buffer).rounded(.up)
    }
}

extension MetricKind {
    /// The axis this metric's trend bars are drawn against.
    var trendScale: TrendScale {
        switch self {
        case .co2: TrendScale(from: 0, atLeast: 1500, buffer: 100)
        case .humidity: TrendScale(from: 0, atLeast: 100)
        case .light: TrendScale(from: 0, atLeast: 1000, buffer: 100)
        // From zero a room's temperature would sit as a flat band near the top, so the
        // axis starts where a habitable room starts.
        case .temperature: TrendScale(from: 10, atLeast: 30, buffer: 1)
        }
    }

    /// Order the Trends list shows them in.
    static let trendOrder: [MetricKind] = [.co2, .humidity, .light, .temperature]

    /// The two the Areas section breaks down per room.
    static let areaMetrics: [MetricKind] = [.co2, .humidity]
}
