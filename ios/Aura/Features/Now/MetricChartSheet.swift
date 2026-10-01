import Charts
import SwiftUI

/// The day's trace for one metric, from midnight to now, scrubbable.
///
/// The line is coloured by height through the metric's severity bands, so it goes green into
/// yellow into red as the reading climbs — the same language as the marker on the card.
struct MetricChartSheet: View {
    let metric: MetricKind
    let readings: [Reading]
    let day: Date
    /// The range the card's grid uses, so the two agree about what "full" means.
    let range: ClosedRange<Double>

    @Environment(\.dismiss) private var dismiss
    @State private var scrubbedAt: Date?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                readout
                chart
                summary
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.auraBase.ignoresSafeArea())
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    // MARK: - Data

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Minute-resolution readings, thinned so the chart never draws more points than a phone
    /// has pixels across.
    private var points: [Point] {
        let raw = readings.compactMap { reading -> Point? in
            guard let value = reading.value(for: metric), value.isFinite else { return nil }
            return Point(date: reading.recordedAt, value: value)
        }

        let limit = 480
        guard raw.count > limit else { return raw }

        let stride = Double(raw.count) / Double(limit)
        return (0..<limit).map { raw[min(Int(Double($0) * stride), raw.count - 1)] }
    }

    private var dayStart: Date { calendar.startOfDay(for: day) }

    private var dayEnd: Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // Today stops at now, so the trace doesn't trail off across empty hours.
        return calendar.isDateInToday(day) ? min(Date(), midnight) : midnight
    }

    /// Framed around the data with headroom, snapped outward, and never inverted.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return range }

        let padding = max((high - low) * 0.15, (range.upperBound - range.lowerBound) * 0.04)
        let lower = max(low - padding, range.lowerBound)
        let upper = high + padding

        guard lower.isFinite, upper.isFinite, upper > lower else { return range }
        return lower...upper
    }

    private var scrubbedPoint: Point? {
        guard let scrubbedAt, !points.isEmpty else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(scrubbedAt)) < abs($1.date.timeIntervalSince(scrubbedAt))
        }
    }

    /// What the big readout shows: the scrubbed point, else the latest.
    private var shown: Point? {
        scrubbedPoint ?? points.last
    }

    // MARK: - Pieces

    private var readout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.format(shown?.value))
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.auraPrimaryText)
                    .contentTransition(.numericText())

                Text(metric.unit)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.auraPrimaryText)
            }

            HStack(spacing: 8) {
                if let shown {
                    Text(shown.date, format: .dateTime.hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text(metric.label(for: shown.value))
                        .font(.subheadline)
                        .foregroundStyle(metric.tint(for: shown.value))
                } else {
                    Text("No readings on this day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: shown?.date)
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.auraCard)
                .frame(height: 260)
                .overlay(
                    Text("Nothing recorded")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                )
        } else {
            // Marks are grouped one kind per ForEach. Nesting a conditional inside a single
            // loop builds a generic type deep enough to crash Swift Charts at runtime.
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Floor", domain.lowerBound),
                        yEnd: .value(metric.unit, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(areaFill)
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(metric.unit, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineStroke)
                }

                if let scrubbedPoint {
                    RuleMark(x: .value("Scrubbed", scrubbedPoint.date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Color.white.opacity(0.5))

                    PointMark(
                        x: .value("Scrubbed", scrubbedPoint.date),
                        y: .value(metric.unit, scrubbedPoint.value)
                    )
                    .symbolSize(80)
                    .foregroundStyle(metric.tint(for: scrubbedPoint.value))
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: dayStart...dayEnd)
            .chartXSelection(value: $scrubbedAt)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric.format(number))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 260)
            .padding(.vertical, 8)
        }
    }

    private var lineStroke: LinearGradient {
        LinearGradient(
            stops: metric.gradientStops(over: domain),
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var areaFill: LinearGradient {
        let stops = metric.gradientStops(over: domain).map {
            Gradient.Stop(color: $0.color.opacity(0.22), location: $0.location)
        }
        return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }

    @ViewBuilder
    private var summary: some View {
        let values = points.map(\.value)

        if !values.isEmpty, let low = values.min(), let high = values.max() {
            HStack(spacing: 0) {
                statistic("Low", low)
                divider
                statistic("Average", values.reduce(0, +) / Double(values.count))
                divider
                statistic("Peak", high)
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.auraCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }

    private func statistic(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.format(value))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.auraPrimaryText)

                Text(metric.unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1, height: 26)
    }
}

#Preview("Chart") {
    MetricChartSheet(
        metric: .co2,
        readings: Reading.sampleSeries(),
        day: Date(),
        range: MetricKind.co2.scale
    )
}
