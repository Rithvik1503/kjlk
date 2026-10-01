import SwiftUI

/// The dashboard: what the room is like right now, and how it got here.
///
/// Reading order is deliberate — the verdict first, then the number behind it, then the scale
/// that makes the number mean something, then the supporting sensors, then the trend.
struct NowView: View {
    @EnvironmentObject private var store: AuraStore

    @State private var chartMetric: MetricKind = .co2
    @State private var detailMetric: MetricKind?

    private var latest: Reading? { store.latest }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                header
                heroCard
                tiles
                trendCard
                rangeCards
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            // Clears the floating tab bar.
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .sheet(item: $detailMetric) { metric in
            MetricDetailView(metric: metric)
                .environmentObject(store)
        }
        .overlay(alignment: .top) {
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.dismissError() }
                    .padding(.horizontal, Metrics.screenPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: store.errorMessage)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraSecondaryText)

                Text(store.preferences.selectedDeviceID ?? "Room monitor")
                    .font(.auraDisplay(26, weight: .bold))
                    .foregroundStyle(Color.auraPrimaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                LiveDot(isLive: store.isLiveConnected)

                Text(store.isLiveConnected ? "Live" : "Polling")
                    .font(.auraCaption)
                    .foregroundStyle(Color.auraSecondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.auraSurface.opacity(0.8)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(store.isLiveConnected ? "Live updates connected" : "Polling for updates")
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<22: "Good evening"
        default: "Tonight"
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        let scale = store.preferences.scale(for: .co2)
        let status = store.status

        return GlassCard(tint: status.tint, padding: 22) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: statusSymbol(for: status.score))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(status.tint)

                        Text(status.headline)
                            .font(.auraDisplay(19, weight: .semibold))
                            .foregroundStyle(Color.auraPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scale.format(scale.convert(latest?.co2)))
                            .font(.auraNumeral(58, weight: .bold))
                            .foregroundStyle(Color.auraPrimaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .auraAnimation(Motion.value, value: latest?.co2)

                        Text("CO₂ ppm")
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraSecondaryText)

                        Text(freshnessText)
                            .font(.auraCaption)
                            .foregroundStyle(store.isStale ? Color.auraAmber : Color.auraTertiaryText)
                    }
                }

                ScaleBar(value: latest?.co2, scale: scale)

                Text(status.detail)
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusSymbol(for score: Double) -> String {
        switch score {
        case 85...: "hand.thumbsup.fill"
        case 70..<85: "checkmark.seal.fill"
        case 50..<70: "wind"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var freshnessText: String {
        guard let latest else { return "No readings yet" }
        let relative = RelativeTime.string(for: latest.recordedAt)
        return store.isStale ? "Last seen \(relative)" : "Updated \(relative)"
    }

    // MARK: - Supporting sensors

    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach([MetricKind.temperature, .humidity, .light]) { metric in
                MetricTile(
                    metric: metric,
                    value: latest?.value(for: metric),
                    scale: store.preferences.scale(for: metric),
                    trend: sparklineValues(for: metric),
                    onInfo: { detailMetric = metric }
                )
            }
        }
    }

    /// The tail of the series, thinned to a readable number of points for a 70pt-wide tile.
    private func sparklineValues(for metric: MetricKind) -> [Double] {
        let values = store.readings.compactMap { $0.value(for: metric) }
        guard values.count > 2 else { return [] }

        let wanted = 32
        guard values.count > wanted else { return values }

        let stride = Double(values.count) / Double(wanted)
        return (0..<wanted).map { values[min(Int(Double($0) * stride), values.count - 1)] }
    }

    // MARK: - Trend

    private var trendCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SegmentedPills(
                    items: TimeRange.allCases,
                    selection: Binding(
                        get: { store.range },
                        set: { store.range = $0 }
                    ),
                    title: { $0.title },
                    symbol: { $0.symbol }
                )

                metricPicker

                TrendChart(
                    points: store.trend(for: chartMetric),
                    scale: store.preferences.scale(for: chartMetric),
                    range: store.range,
                    style: store.range == .month ? .bars : .area,
                    height: 190
                )

                if store.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Refreshing")
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)
                    }
                }
            }
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MetricKind.allCases) { metric in
                    let isSelected = metric == chartMetric
                    let tint = store.preferences
                        .scale(for: metric)
                        .tint(for: store.preferences.scale(for: metric).convert(latest?.value(for: metric)))

                    Button {
                        Haptics.selection()
                        withAnimation(Motion.snappy) { chartMetric = metric }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: metric.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(metric.shortTitle)
                                .font(.auraLabel)
                        }
                        .foregroundStyle(isSelected ? Color.auraVoid : Color.auraSecondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? tint : Color.auraSurfaceRaised)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Ranges

    private var rangeCards: some View {
        VStack(spacing: Metrics.cardSpacing) {
            ForEach(MetricKind.allCases) { metric in
                if let summary = store.summaries[metric] {
                    MetricRangeCard(
                        summary: summary,
                        scale: store.preferences.scale(for: metric),
                        rangeTitle: store.range.title,
                        lastReadingAt: latest?.recordedAt
                    )
                    .onTapGesture { detailMetric = metric }
                }
            }
        }
    }
}

/// A dismissible red bar for transient failures — a dropped refresh shouldn't blank the screen.
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.auraRed)

            Text(message)
                .font(.auraLabel)
                .foregroundStyle(Color.auraPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.auraSecondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.auraSurfaceRaised)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.auraRed.opacity(0.35), lineWidth: 1)
        )
    }
}

#Preview("Now") {
    NowView()
        .environmentObject(AuraStore.preview())
        .background(Color.auraBase)
        .preferredColorScheme(.dark)
}
