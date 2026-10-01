import SwiftUI

/// One metric in the Trends list: a row that drops down into its own chart.
///
/// Collapsed it shows the title, a dot-matrix preview and the window's latest value.
/// Expanded, the preview gives way to the full chart, an axis, and the period average.
struct TrendRow: View {
    let metric: MetricKind
    let window: TrendWindow
    /// One entry per slot in the window, oldest first; nil where nothing was recorded.
    let slots: [(date: Date, value: Double?)]
    let windowAverage: Double?
    /// Largest value in the loaded history, which sets the top of the fixed axis.
    let observedMax: Double?

    @State private var isExpanded = false
    @State private var activeIndex: Int?

    private var values: [Double?] { slots.map(\.value) }

    private var axis: (from: Double, to: Double) {
        let scale = metric.trendScale
        return (scale.from, scale.top(observedMax: observedMax))
    }

    /// The most recent slot that holds a value.
    private var latest: Double? {
        values.reversed().compactMap { $0 }.first
    }

    /// What the right-hand figure shows: the scrubbed slot, else the latest.
    private var shownValue: Double? {
        if let activeIndex, slots.indices.contains(activeIndex) {
            return slots[activeIndex].value
        }
        return latest
    }

    private var scrubLabel: String? {
        guard let activeIndex, slots.indices.contains(activeIndex) else { return nil }
        let date = slots[activeIndex].date
        let format: Date.FormatStyle = window.isMonthly
            ? .dateTime.month(.abbreviated).year()
            : .dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return date.formatted(format).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
                if !isExpanded { activeIndex = nil }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 16)

                chart
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.auraCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Text(metric.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.auraPrimaryText)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            // The preview stands in for the chart, so it goes once the chart is on screen.
            if !isExpanded, values.contains(where: { $0 != nil }) {
                MiniDitheredBars(values: values, axis: axis)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(shownValue.map(metric.format) ?? "—")
                    .font(.system(size: 20))
                    .monospacedDigit()
                    .foregroundStyle(shownValue == nil ? Color.auraMutedText : Color.auraPrimaryText)

                if let scrubLabel {
                    Text(scrubLabel)
                        .font(.auraMono(8.5))
                        .tracking(0.8)
                        .foregroundStyle(Color.auraDimText)
                }
            }
            .frame(minWidth: 56, alignment: .trailing)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.auraDimText)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(latest.map { "\(metric.format($0)) \(metric.unit)" } ?? "No data")
        .accessibilityHint(isExpanded ? "Collapses the chart" : "Expands the chart")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(averageLine)
                .font(.auraMono(10))
                .tracking(1.4)
                .foregroundStyle(Color.auraMutedText)

            HStack(alignment: .firstTextBaseline) {
                Text(window.resolutionLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.auraPrimaryText)

                Spacer()

                Text(window.sampleLabel)
                    .font(.auraMono(10))
                    .tracking(1.2)
                    .foregroundStyle(Color.auraMutedText)
            }

            if values.allSatisfy({ $0 == nil }) {
                Text("No data in this window")
                    .font(.auraMono(11))
                    .foregroundStyle(Color.auraMutedText)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    verticalAxis
                    ScrubbableChart(
                        values: values,
                        axis: axis,
                        height: 150,
                        activeIndex: $activeIndex
                    ) { _ in }
                }

                horizontalAxis
                    .padding(.leading, Self.axisWidth + 6)
            }
        }
        .onChange(of: window) { _, _ in activeIndex = nil }
    }

    private var averageLine: String {
        let value = windowAverage.map(metric.format) ?? "—"
        return "\(window.averageLabel) AVG \(value) \(metric.unitLabel)"
    }

    private static let axisWidth: CGFloat = 30

    /// Top, middle and bottom of the fixed scale, beside the bars.
    private var verticalAxis: some View {
        let (low, high) = axis
        let ticks = [high, (high + low) / 2, low]

        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                Text(metric.format(tick))
                    .font(.auraMono(8))
                    .foregroundStyle(Color.auraDimText)
                    .frame(
                        maxHeight: .infinity,
                        alignment: index == 0 ? .top : (index == ticks.count - 1 ? .bottom : .center)
                    )
            }
        }
        .frame(width: Self.axisWidth, height: 150)
    }

    /// Weekdays across a week and months across six; a month gets first, middle and last
    /// date instead, since thirty labels would be a smear.
    @ViewBuilder
    private var horizontalAxis: some View {
        let dates = slots.map(\.date)

        switch window {
        case .week:
            evenly(dates.map { $0.formatted(.dateTime.weekday(.abbreviated)).uppercased() })
        case .halfYear:
            evenly(dates.map { $0.formatted(.dateTime.month(.abbreviated)).uppercased() })
        case .month:
            HStack {
                Text(label(dates.first))
                Spacer()
                Text(label(dates.indices.contains(dates.count / 2) ? dates[dates.count / 2] : nil))
                Spacer()
                Text(label(dates.last))
            }
            .font(.auraMono(9))
            .tracking(0.8)
            .foregroundStyle(Color.auraMutedText)
        }
    }

    private func label(_ date: Date?) -> String {
        date.map { $0.formatted(.dateTime.day().month(.abbreviated)).uppercased() } ?? ""
    }

    /// Equal cells at the bars' own spacing, so each label's centre lands on the centre of
    /// the column above it.
    private func evenly(_ labels: [String]) -> some View {
        HStack(spacing: DitheredBars.gap) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.auraMono(9))
                    .tracking(0.8)
                    .foregroundStyle(Color.auraMutedText)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
