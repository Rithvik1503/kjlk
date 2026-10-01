import Charts
import SwiftUI

/// The main chart. Draws one metric over a time range, as a filled trend line or as bars.
///
/// Both styles colour by value using the metric's own ramp, so a spike is visibly a spike
/// before you read the axis. Dragging scrubs: a lollipop follows the finger with the exact
/// value and timestamp under it.
struct TrendChart: View {
    enum Style {
        /// Smoothed line with a gradient fill. Best when points are dense.
        case area
        /// One bar per bucket, coloured by value. Best for coarse buckets — the 30-day view.
        case bars
    }

    let points: [TrendPoint]
    let scale: DisplayScale
    let range: TimeRange
    var style: Style = .area
    var height: CGFloat = 200
    var showsComfortBand: Bool = true

    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points converted into display units once, up front.
    private var plotted: [TrendPoint] {
        guard scale.metric == .temperature else { return points }
        return points.map {
            TrendPoint(
                date: $0.date,
                value: scale.convert($0.value),
                minimum: scale.convert($0.minimum),
                maximum: scale.convert($0.maximum)
            )
        }
    }

    private var domain: ClosedRange<Double> {
        Trend.axisRange(for: plotted, metric: scale.metric)
    }

    private var selectedPoint: TrendPoint? {
        guard let selectedDate, !plotted.isEmpty else { return nil }
        return plotted.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Group {
            if plotted.isEmpty {
                EmptyChartPlaceholder(height: height)
            } else {
                chart
            }
        }
        .frame(height: height)
    }

    private var chart: some View {
        Chart {
            if showsComfortBand, let comfort = scale.comfortBand {
                RectangleMark(
                    yStart: .value("Comfort low", max(comfort.lowerBound, domain.lowerBound)),
                    yEnd: .value("Comfort high", min(comfort.upperBound, domain.upperBound))
                )
                .foregroundStyle(Color.auraGreen.opacity(0.08))
            }

            ForEach(plotted) { point in
                switch style {
                case .area:
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Floor", domain.lowerBound),
                        yEnd: .value(scale.metric.shortTitle, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(areaFill)

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(scale.metric.shortTitle, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineStroke)

                case .bars:
                    BarMark(
                        x: .value("Time", point.date),
                        y: .value(scale.metric.shortTitle, point.value),
                        width: .ratio(0.62)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(scale.tint(for: point.value))
                }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Color.auraSecondaryText.opacity(0.6))

                PointMark(
                    x: .value("Selected", selectedPoint.date),
                    y: .value(scale.metric.shortTitle, selectedPoint.value)
                )
                .symbolSize(90)
                .foregroundStyle(scale.tint(for: selectedPoint.value))
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                    ChartCallout(point: selectedPoint, scale: scale, range: range)
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(scale.format(number))
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range.axisTickCount)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: range.axisFormat)
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                }
            }
        }
        .auraAnimation(Motion.gentle, value: plotted.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scale.metric.title) over the last \(range.title)")
        .accessibilityValue(accessibilitySummary)
    }

    private var areaFill: LinearGradient {
        let tint = scale.tint(for: plotted.last?.value ?? domain.lowerBound)
        return LinearGradient(
            colors: [tint.opacity(0.42), tint.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Stroke coloured by height, so the line changes colour as it crosses a band boundary.
    private var lineStroke: LinearGradient {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else {
            return LinearGradient(colors: [scale.tint(for: domain.lowerBound)], startPoint: .bottom, endPoint: .top)
        }

        let nominal = scale.nominalRange
        let nominalSpan = nominal.upperBound - nominal.lowerBound

        let stops = scale.gradientStops.compactMap { stop -> Gradient.Stop? in
            // Where this stop sits on the metric's full ramp, re-expressed against the
            // axis the chart is actually drawing.
            let absolute = nominal.lowerBound + Double(stop.location) * nominalSpan
            let location = (absolute - domain.lowerBound) / span
            guard (0...1).contains(location) else { return nil }
            return .init(color: stop.color, location: CGFloat(location))
        }

        guard stops.count > 1 else {
            return LinearGradient(
                colors: [scale.tint(for: (domain.lowerBound + domain.upperBound) / 2)],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }

    private var accessibilitySummary: String {
        guard
            let low = plotted.map(\.minimum).min(),
            let high = plotted.map(\.maximum).max(),
            !plotted.isEmpty
        else { return "No data" }

        let average = plotted.reduce(0) { $0 + $1.value } / Double(plotted.count)
        return """
        Average \(scale.formatWithUnit(average)), \
        from \(scale.formatWithUnit(low)) to \(scale.formatWithUnit(high)).
        """
    }
}

/// The bubble that follows the finger while scrubbing.
private struct ChartCallout: View {
    let point: TrendPoint
    let scale: DisplayScale
    let range: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(scale.formatWithUnit(point.value))
                .font(.auraNumeral(14, weight: .bold))
                .foregroundStyle(Color.auraPrimaryText)

            Text(point.date, format: range.calloutFormat)
                .font(.auraCaption)
                .foregroundStyle(Color.auraTertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.auraSurfaceRaised)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Shown where a chart would be when there is nothing in the window to draw.
struct EmptyChartPlaceholder: View {
    var height: CGFloat = 200
    var message: String = "No readings in this window"

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
            .fill(Color.auraSurfaceRaised.opacity(0.4))
            .frame(height: height)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.auraTertiaryText)

                    Text(message)
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraTertiaryText)
                        .multilineTextAlignment(.center)
                }
                .padding()
            )
    }
}

// MARK: - Axis formatting

extension TimeRange {
    var axisTickCount: Int {
        switch self {
        case .sixHours: 4
        case .day: 5
        case .week: 4
        case .month: 4
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .sixHours, .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.day().month(.abbreviated)
        }
    }

    var calloutFormat: Date.FormatStyle {
        switch self {
        case .sixHours, .day: .dateTime.hour().minute()
        case .week, .month: .dateTime.weekday(.abbreviated).hour()
        }
    }
}

#Preview("Trend chart") {
    let preferences = Preferences()
    let readings = Reading.sampleSeries()
    let points = Trend.buckets(
        from: readings,
        metric: .co2,
        interval: TimeRange.day.bucket,
        start: TimeRange.day.start(),
        end: Date()
    )

    ZStack {
        Color.auraBase.ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard {
                TrendChart(points: points, scale: preferences.scale(for: .co2), range: .day)
            }
            GlassCard {
                TrendChart(
                    points: points,
                    scale: preferences.scale(for: .co2),
                    range: .day,
                    style: .bars
                )
            }
        }
        .padding()
    }
}
