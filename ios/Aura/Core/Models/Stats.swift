import Foundation

/// Minimum, average and maximum for one metric over a window of readings.
///
/// This is what the range bars on the dashboard draw: the track spans `min...max`,
/// the floating pill sits at `latest`, and the headline number is `average`.
struct MetricSummary: Hashable, Sendable {
    let metric: MetricKind
    let minimum: Double
    let average: Double
    let maximum: Double
    let latest: Double
    let sampleCount: Int

    /// Where `latest` falls between `minimum` and `maximum`, as 0...1.
    var latestPosition: Double {
        let span = maximum - minimum
        guard span > 0 else { return 0.5 }
        return ((latest - minimum) / span).clamped(to: 0...1)
    }

    static func make(metric: MetricKind, readings: [Reading]) -> MetricSummary? {
        let values = readings.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return nil }

        // `readings` is ordered oldest to newest, so the last non-nil value is the current one.
        let latest = readings.reversed().compactMap { $0.value(for: metric) }.first ?? values[values.count - 1]

        return MetricSummary(
            metric: metric,
            minimum: values.min() ?? latest,
            average: values.reduce(0, +) / Double(values.count),
            maximum: values.max() ?? latest,
            latest: latest,
            sampleCount: values.count
        )
    }
}

/// A time-bucketed point used by the charts. One bar or one vertex of the trend line.
struct TrendPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let value: Double
    let minimum: Double
    let maximum: Double

    var id: Date { date }
}

/// How much of the past the dashboard and history screens show.
enum TimeRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case sixHours
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sixHours: "6 Hours"
        case .day: "24 Hours"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }

    var compactTitle: String {
        switch self {
        case .sixHours: "6H"
        case .day: "24H"
        case .week: "7D"
        case .month: "30D"
        }
    }

    var symbol: String {
        switch self {
        case .sixHours, .day: "clock"
        case .week, .month: "chart.bar.fill"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .sixHours: 6 * 3600
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        }
    }

    /// Width of one chart bucket. Chosen so every range lands on 36–72 bars.
    var bucket: TimeInterval {
        switch self {
        case .sixHours: 10 * 60
        case .day: 30 * 60
        case .week: 3 * 3600
        case .month: 12 * 3600
        }
    }

    /// Upper bound on rows fetched for this range, so a month never pulls 43k readings.
    var rowLimit: Int {
        switch self {
        case .sixHours: 600
        case .day: 2000
        case .week: 6000
        case .month: 12000
        }
    }

    func start(from reference: Date = Date()) -> Date {
        reference.addingTimeInterval(-duration)
    }
}

// MARK: - Bucketing

enum Trend {
    /// Collapses raw readings into evenly spaced buckets.
    ///
    /// Buckets with no readings are dropped rather than zero-filled — a gap in the chart is
    /// honest about the device having been offline, a zero is not.
    static func buckets(
        from readings: [Reading],
        metric: MetricKind,
        interval: TimeInterval,
        start: Date,
        end: Date
    ) -> [TrendPoint] {
        guard interval > 0, end > start else { return [] }

        var sums: [Int: (total: Double, count: Int, min: Double, max: Double)] = [:]
        let origin = start.timeIntervalSince1970

        for reading in readings {
            guard let value = reading.value(for: metric) else { continue }
            let offset = reading.recordedAt.timeIntervalSince1970 - origin
            guard offset >= 0 else { continue }
            let index = Int(offset / interval)

            if var existing = sums[index] {
                existing.total += value
                existing.count += 1
                existing.min = Swift.min(existing.min, value)
                existing.max = Swift.max(existing.max, value)
                sums[index] = existing
            } else {
                sums[index] = (value, 1, value, value)
            }
        }

        return sums.keys.sorted().compactMap { index in
            guard let entry = sums[index] else { return nil }
            let date = Date(timeIntervalSince1970: origin + (Double(index) + 0.5) * interval)
            return TrendPoint(
                date: date,
                value: entry.total / Double(entry.count),
                minimum: entry.min,
                maximum: entry.max
            )
        }
    }

    /// Y-axis bounds that frame the data with a little headroom, snapped to round numbers.
    static func axisRange(for points: [TrendPoint], metric: MetricKind) -> ClosedRange<Double> {
        let values = points.flatMap { [$0.minimum, $0.maximum] }
        guard let low = values.min(), let high = values.max() else { return metric.nominalRange }

        let span = high - low
        let padding = max(span * 0.18, metric.axisMinimumPadding)
        let lower = low - padding
        let upper = high + padding

        let step = metric.axisStep
        let snappedLower = (lower / step).rounded(.down) * step
        let snappedUpper = (upper / step).rounded(.up) * step

        let floor = metric.axisFloor
        let result = max(snappedLower, floor)...max(snappedUpper, floor + step)
        return result
    }
}

private extension MetricKind {
    var axisStep: Double {
        switch self {
        case .co2: 100
        case .temperature: 1
        case .humidity: 5
        case .light: 50
        }
    }

    var axisMinimumPadding: Double {
        switch self {
        case .co2: 50
        case .temperature: 0.5
        case .humidity: 3
        case .light: 25
        }
    }

    /// Values below this are physically impossible, so the axis never goes there.
    var axisFloor: Double {
        switch self {
        case .co2: 0
        case .temperature: -40
        case .humidity: 0
        case .light: 0
        }
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
