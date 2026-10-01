import Charts
import SwiftUI

/// The main chart. Draws one metric over a time range, as a filled trend line or as bars.
///
/// Both styles colour by value using the metric's own ramp, so a spike is visibly a spike
/// before you read the axis. Dragging scrubs: a lollipop follows the finger with the exact
/// value and timestamp under it.
struct TrendChart: View {
    enum Style: Equatable {
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

    var body: some View {
        // Resolved once per render and handed down. Previously the axis domain was a computed
        // property read inside the mark loop, which re-derived the whole converted series for
        // every point on screen.
        let model = TrendChartModel(points: points, scale: scale, showsComfortBand: showsComfortBand)

        Group {
            if model.points.isEmpty {
                EmptyChartPlaceholder(height: height)
            } else {
                TrendChartCanvas(
                    model: model,
                    range: range,
                    style: style,
                    selectedDate: $selectedDate
                )
            }
        }
        .frame(height: height)
    }
}

// MARK: - Model

/// Everything the chart needs, in display units, computed once.
private struct TrendChartModel {
    let points: [TrendPoint]
    let domain: ClosedRange<Double>
    let comfort: ClosedRange<Double>?
    let scale: DisplayScale

    init(points rawPoints: [TrendPoint], scale: DisplayScale, showsComfortBand: Bool) {
        self.scale = scale

        // Convert into display units, and drop anything non-finite — a NaN would propagate
        // into the axis bounds and trap when they're formed into a range.
        let converted: [TrendPoint] = rawPoints.compactMap { point in
            let value = scale.convert(point.value)
            let minimum = scale.convert(point.minimum)
            let maximum = scale.convert(point.maximum)
            guard value.isFinite, minimum.isFinite, maximum.isFinite else { return nil }
            return TrendPoint(date: point.date, value: value, minimum: minimum, maximum: maximum)
        }

        self.points = converted
        self.domain = Trend.axisRange(for: converted, metric: scale.metric)

        // Clipped to the visible axis so the band never draws inverted.
        if showsComfortBand,
           let band = scale.comfortBand,
           band.lowerBound < domain.upperBound,
           band.upperBound > domain.lowerBound {
            self.comfort = max(band.lowerBound, domain.lowerBound)...min(band.upperBound, domain.upperBound)
        } else {
            self.comfort = nil
        }
    }

    func nearestPoint(to date: Date) -> TrendPoint? {
        points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    var tint: Color {
        scale.tint(for: points.last?.value)
    }

    var areaFill: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.42), tint.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Stroke coloured by height, so the line changes colour as it crosses a band boundary.
    var lineStroke: LinearGradient {
        let span = domain.upperBound - domain.lowerBound
        let nominal = scale.nominalRange
        let nominalSpan = nominal.upperBound - nominal.lowerBound

        guard span > 0, nominalSpan > 0 else {
            return LinearGradient(colors: [tint], startPoint: .bottom, endPoint: .top)
        }

        let stops = scale.gradientStops.compactMap { stop -> Gradient.Stop? in
            // Where this stop sits on the metric's full ramp, re-expressed against the
            // axis the chart is actually drawing.
            let absolute = nominal.lowerBound + Double(stop.location) * nominalSpan
            let location = (absolute - domain.lowerBound) / span
            guard (0...1).contains(location) else { return nil }
            return .init(color: stop.color, location: CGFloat(location))
        }

        guard stops.count > 1 else {
            return LinearGradient(colors: [tint], startPoint: .bottom, endPoint: .top)
        }
        return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }

    var accessibilitySummary: String {
        guard
            !points.isEmpty,
            let low = points.map(\.minimum).min(),
            let high = points.map(\.maximum).max()
        else { return "No data" }

        let average = points.reduce(0) { $0 + $1.value } / Double(points.count)
        return """
        Average \(scale.formatWithUnit(average)), \
        from \(scale.formatWithUnit(low)) to \(scale.formatWithUnit(high)).
        """
    }
}

// MARK: - Canvas

/// The chart itself.
///
/// The marks are assembled from small `@ChartContentBuilder` pieces, and the area and bar
/// styles are separate branches rather than a `switch` inside the mark loop. That keeps the
/// generic type Swift Charts has to instantiate shallow — nesting a conditional *inside* a
/// `ForEach` builds a type deep enough to crash metadata instantiation at runtime.
private struct TrendChartCanvas: View {
    let model: TrendChartModel
    let range: TimeRange
    let style: TrendChart.Style
    @Binding var selectedDate: Date?

    private var scale: DisplayScale { model.scale }

    private var selectedPoint: TrendPoint? {
        selectedDate.flatMap(model.nearestPoint(to:))
    }

    var body: some View {
        Chart {
            comfortBand
            series
            selection
        }
        .chartYScale(domain: model.domain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis { yAxis }
        .chartXAxis { xAxis }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scale.metric.title) over the last \(range.title)")
        .accessibilityValue(model.accessibilitySummary)
    }

    // MARK: Marks

    @ChartContentBuilder
    private var comfortBand: some ChartContent {
        if let comfort = model.comfort {
            RectangleMark(
                yStart: .value("Comfort low", comfort.lowerBound),
                yEnd: .value("Comfort high", comfort.upperBound)
            )
            .foregroundStyle(Color.auraGreen.opacity(0.08))
        }
    }

    @ChartContentBuilder
    private var series: some ChartContent {
        if style == .bars {
            bars
        } else {
            areaAndLine
        }
    }

    @ChartContentBuilder
    private var areaAndLine: some ChartContent {
        ForEach(model.points) { point in
            AreaMark(
                x: .value("Time", point.date),
                yStart: .value("Floor", model.domain.lowerBound),
                yEnd: .value(scale.metric.shortTitle, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(model.areaFill)
        }

        ForEach(model.points) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value(scale.metric.shortTitle, point.value)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(model.lineStroke)
        }
    }

    @ChartContentBuilder
    private var bars: some ChartContent {
        ForEach(model.points) { point in
            BarMark(
                x: .value("Time", point.date),
                y: .value(scale.metric.shortTitle, point.value),
                width: .ratio(0.62)
            )
            .foregroundStyle(scale.tint(for: point.value))
        }
    }

    @ChartContentBuilder
    private var selection: some ChartContent {
        if let point = selectedPoint {
            RuleMark(x: .value("Selected", point.date))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(Color.auraSecondaryText.opacity(0.6))

            PointMark(
                x: .value("Selected", point.date),
                y: .value(scale.metric.shortTitle, point.value)
            )
            .symbolSize(90)
            .foregroundStyle(scale.tint(for: point.value))
            .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                ChartCallout(point: point, scale: scale, range: range)
            }
        }
    }

    // MARK: Axes

    @AxisContentBuilder
    private var yAxis: some AxisContent {
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

    @AxisContentBuilder
    private var xAxis: some AxisContent {
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
