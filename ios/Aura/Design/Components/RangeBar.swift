import SwiftUI

/// A gradient track spanning the period's low to high, with the current value floating on it.
///
/// The track is coloured by the metric's own ramp, clipped to the span actually observed — so
/// a day that never left the comfort band draws an entirely green bar, and a day that spiked
/// shows exactly where it crossed over.
///
/// The indicator has a fixed width rather than a measured one: the content is an icon and at
/// most four digits, and a stable width means the pill never twitches as the value ticks.
struct RangeBar: View {
    let summary: MetricSummary
    let scale: DisplayScale
    var showsIndicator: Bool = true

    private let trackHeight: CGFloat = 6
    private let indicatorWidth: CGFloat = 82
    private let indicatorHeight: CGFloat = 34

    private var low: Double { scale.convert(summary.minimum) }
    private var high: Double { scale.convert(summary.maximum) }
    private var current: Double { scale.convert(summary.latest) }

    /// Where the current value sits between the observed low and high, 0...1.
    private var position: Double {
        let span = high - low
        guard span > 0 else { return 0.5 }
        return ((current - low) / span).clamped(to: 0...1)
    }

    /// The slice of the metric's full colour ramp that this low–high span covers.
    private var trackStops: [Gradient.Stop] {
        let full = scale.nominalRange
        let fullSpan = full.upperBound - full.lowerBound
        guard fullSpan > 0, high > low else {
            return [
                .init(color: scale.tint(for: current), location: 0),
                .init(color: scale.tint(for: current), location: 1),
            ]
        }

        let startFraction = CGFloat(((low - full.lowerBound) / fullSpan).clamped(to: 0...1))
        let endFraction = CGFloat(((high - full.lowerBound) / fullSpan).clamped(to: 0...1))
        let window = max(endFraction - startFraction, 0.0001)

        // Re-map the full ramp into the window, keeping only the stops that fall inside it.
        var remapped: [Gradient.Stop] = scale.gradientStops.compactMap { stop in
            guard stop.location >= startFraction, stop.location <= endFraction else { return nil }
            return .init(color: stop.color, location: (stop.location - startFraction) / window)
        }

        remapped.insert(.init(color: scale.tint(for: low), location: 0), at: 0)
        remapped.append(.init(color: scale.tint(for: high), location: 1))
        return remapped
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let travel = max(width - indicatorWidth, 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(stops: trackStops, startPoint: .leading, endPoint: .trailing))
                        .frame(height: trackHeight)
                        .frame(maxHeight: .infinity, alignment: .center)

                    // End caps, so the track reads as a measured span rather than a progress bar.
                    HStack {
                        endCap(color: scale.tint(for: low))
                        Spacer(minLength: 0)
                        endCap(color: scale.tint(for: high))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    if showsIndicator {
                        indicator
                            .offset(x: travel * CGFloat(position))
                            .auraAnimation(Motion.value, value: position)
                    }
                }
                .frame(width: width, height: indicatorHeight)
            }
            .frame(height: indicatorHeight)

            HStack(alignment: .firstTextBaseline) {
                extremeLabel(title: "Lowest", value: low, symbol: "arrow.down")
                Spacer(minLength: 8)
                extremeLabel(title: "Peak", value: high, symbol: "arrow.up", alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.metric.title)
        .accessibilityValue(
            """
            Now \(scale.formatWithUnit(current)). \
            Low \(scale.formatWithUnit(low)), peak \(scale.formatWithUnit(high)).
            """
        )
    }

    private var indicator: some View {
        HStack(spacing: 5) {
            Image(systemName: summary.metric.symbol)
                .font(.system(size: 11, weight: .bold))

            Text(scale.format(current))
                .font(.auraNumeral(15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Color.white)
        .frame(width: indicatorWidth, height: indicatorHeight)
        .background(
            Capsule()
                .fill(scale.tint(for: current))
                .shadow(color: scale.tint(for: current).opacity(0.5), radius: 10, y: 3)
        )
        .overlay(
            Capsule().strokeBorder(Color.auraSurface, lineWidth: 3)
        )
    }

    private func endCap(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(Color.auraSurface, lineWidth: 2))
    }

    private func extremeLabel(
        title: String,
        value: Double,
        symbol: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.auraCaption)
                .foregroundStyle(Color.auraTertiaryText)

            Text(scale.format(value))
                .font(.auraNumeral(13, weight: .semibold))
                .foregroundStyle(Color.auraSecondaryText)

            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(scale.tint(for: value))
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// The dashboard card built around a `RangeBar` — the layout from the heart-rate reference:
/// average on the left, freshness on the right, the span underneath.
struct MetricRangeCard: View {
    let summary: MetricSummary
    let scale: DisplayScale
    let rangeTitle: String
    let lastReadingAt: Date?

    var body: some View {
        GlassCard(tint: scale.tint(for: scale.convert(summary.latest))) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(rangeTitle) average")
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraSecondaryText)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(scale.format(scale.convert(summary.average)))
                                .font(.auraNumeral(32, weight: .bold))
                                .foregroundStyle(Color.auraPrimaryText)

                            Text(scale.unit)
                                .font(.auraDisplay(17, weight: .semibold))
                                .foregroundStyle(scale.tint(for: scale.convert(summary.average)))
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last reading")
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraSecondaryText)

                        Text(lastReadingAt.map { RelativeTime.string(for: $0) } ?? "––")
                            .font(.auraDisplay(17, weight: .semibold))
                            .foregroundStyle(Color.auraPrimaryText)
                    }
                }

                RangeBar(summary: summary, scale: scale)
            }
        }
    }
}

/// "2 min ago", "just now" — short enough to sit in a card corner.
enum RelativeTime {
    static func string(for date: Date, reference: Date = Date()) -> String {
        let seconds = reference.timeIntervalSince(date)
        if seconds < 45 { return "just now" }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds < 3600 ? [.minute] : (seconds < 86400 ? [.hour] : [.day])

        guard let value = formatter.string(from: seconds) else { return "––" }
        return "\(value) ago"
    }
}

#Preview("Range card") {
    let preferences = Preferences()
    let readings = Reading.sampleSeries()

    ZStack {
        Color.auraBase.ignoresSafeArea()

        VStack(spacing: 14) {
            ForEach(MetricKind.allCases) { metric in
                if let summary = MetricSummary.make(metric: metric, readings: readings) {
                    MetricRangeCard(
                        summary: summary,
                        scale: preferences.scale(for: metric),
                        rangeTitle: "Daily",
                        lastReadingAt: readings.last?.recordedAt
                    )
                }
            }
        }
        .padding()
    }
}
