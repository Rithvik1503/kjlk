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
        .presentationDetents([.medium, .large])
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(metric.format(shown?.value))
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.auraPrimaryText)
                    .contentTransition(.numericText())

                Text(metric.unitLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auraPrimaryText.opacity(0.5))
            }

            Spacer(minLength: 0)

            if let shown {
                HStack(spacing: 7) {
                    Text(shown.date.formatted(.dateTime.hour().minute()).uppercased())
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(metric.label(for: shown.value).uppercased())
                        .foregroundStyle(metric.tint(for: shown.value).opacity(0.85))
                }
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .monospacedDigit()
            } else {
                Text("NO READINGS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
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
                .frame(height: 190)
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
                // Values only — no gridlines, and nothing along the bottom. Scrubbing reports
                // the time, so an axis of hours is a row of noise under the trace.
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric.format(number))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 190)
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

                Text(metric.unitLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.auraPrimaryText.opacity(0.45))
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
