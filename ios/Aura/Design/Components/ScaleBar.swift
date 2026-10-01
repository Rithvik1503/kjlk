import SwiftUI

/// The full-spectrum scale from the air-quality reference: the metric's entire colour ramp
/// with a marker showing where the current reading falls, and tick labels underneath.
///
/// Where `RangeBar` answers "how much did it move today", this answers "is that number good".
struct ScaleBar: View {
    /// Raw SI value, as stored. Converted to display units here, so no caller has to.
    let value: Double?
    let scale: DisplayScale
    var showsTicks: Bool = true
    var height: CGFloat = 12

    private var displayValue: Double? { scale.convert(value) }

    private var position: Double? {
        displayValue.map { scale.position(of: $0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(scale.gradient)
                        .frame(height: height)

                    if let position {
                        marker
                            .position(x: markerX(for: position, width: width), y: height / 2)
                            .auraAnimation(Motion.value, value: position)
                    }
                }
                .frame(height: height)
            }
            .frame(height: height)

            if showsTicks {
                ticks
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scale.metric.title) scale")
        .accessibilityValue(
            displayValue.map { "\(scale.formatWithUnit($0)), \(scale.qualityLabel(for: $0))" } ?? "No reading"
        )
    }

    private var markerInset: CGFloat { height / 2 + 3 }

    /// Keeps the marker's rounded cap inside the track at both extremes.
    private func markerX(for position: Double, width: CGFloat) -> CGFloat {
        let upper = max(width - markerInset, markerInset)
        return (CGFloat(position) * width).clamped(to: markerInset...upper)
    }

    private var marker: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 5, height: height + 10)
            .shadow(color: .black.opacity(0.55), radius: 5)
            .overlay(
                Capsule().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
            )
    }

    private var ticks: some View {
        HStack(spacing: 0) {
            ForEach(Array(scale.ticks().enumerated()), id: \.offset) { index, tick in
                Text(scale.format(tick))
                    .font(.auraCaption)
                    .foregroundStyle(Color.auraTertiaryText)
                    .frame(
                        maxWidth: .infinity,
                        alignment: alignment(for: index, of: scale.ticks().count)
                    )
            }
        }
    }

    private func alignment(for index: Int, of count: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }
}

/// One of the small metric squares under the hero reading — the PM10 / PM2.5 / PM1 row.
struct MetricTile: View {
    let metric: MetricKind
    /// Raw SI value, as stored. Converted to display units here, so no caller has to.
    let value: Double?
    let scale: DisplayScale
    /// Raw values for the sparkline. Only the shape matters, so these need no conversion.
    var trend: [Double] = []
    var onInfo: (() -> Void)?

    private var displayValue: Double? { scale.convert(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(metric.shortTitle)
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraSecondaryText)

                Spacer(minLength: 0)

                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About \(metric.title)")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(scale.format(displayValue))
                    .font(.auraNumeral(26, weight: .bold))
                    .foregroundStyle(Color.auraPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(scale.unit)
                    .font(.auraDisplay(12, weight: .semibold))
                    .foregroundStyle(Color.auraTertiaryText)
            }

            if trend.count > 1 {
                Sparkline(values: trend, tint: scale.tint(for: displayValue))
                    .frame(height: 22)
            } else {
                Text(scale.qualityLabel(for: displayValue))
                    .font(.auraCaption)
                    .foregroundStyle(scale.tint(for: displayValue))
                    .frame(height: 22, alignment: .center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
                .fill(Color.auraSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
                        .fill(scale.tint(for: displayValue).opacity(0.10))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(scale.formatWithUnit(displayValue)), \(scale.qualityLabel(for: displayValue))")
    }
}

/// A tiny filled line chart, no axes — just the shape of the last few hours.
struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = normalisedPoints(in: size)

            ZStack {
                if points.count > 1 {
                    linePath(points)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    fillPath(points, height: size.height)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalisedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }

        // A flat series would divide by zero; draw it down the middle instead.
        let span = high - low
        let step = size.width / CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            let ratio = span > 0 ? (value - low) / span : 0.5
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(ratio) * size.height
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: points[0].x, y: height))
            path.addLine(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
            path.closeSubpath()
        }
    }
}

#Preview("Scale and tiles") {
    let preferences = Preferences()
    let readings = Reading.sampleSeries()

    ZStack {
        Color.auraBase.ignoresSafeArea()

        VStack(spacing: 24) {
            ScaleBar(value: 980, scale: preferences.scale(for: .co2))

            HStack(spacing: 10) {
                ForEach([MetricKind.temperature, .humidity, .light]) { metric in
                    MetricTile(
                        metric: metric,
                        value: readings.last?.value(for: metric),
                        scale: preferences.scale(for: metric),
                        trend: readings.suffix(40).compactMap { $0.value(for: metric) },
                        onInfo: {}
                    )
                }
            }
        }
        .padding()
    }
}
