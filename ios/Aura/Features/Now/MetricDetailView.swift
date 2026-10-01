import SwiftUI

/// The sheet behind each tile's info button: what the metric means, where it sits on the
/// scale, what it has done recently, and what to do about it.
struct MetricDetailView: View {
    let metric: MetricKind

    @EnvironmentObject private var store: AuraStore
    @Environment(\.dismiss) private var dismiss

    @State private var range: TimeRange = .day

    private var scale: DisplayScale { store.preferences.scale(for: metric) }
    private var rawValue: Double? { store.latest?.value(for: metric) }
    private var displayValue: Double? { scale.convert(rawValue) }

    var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground(tint: scale.tint(for: displayValue), intensity: 0.7)

                ScrollView {
                    VStack(spacing: Metrics.cardSpacing) {
                        currentCard
                        chartCard
                        statsCard
                        explainerCard
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraPrimaryText)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var currentCard: some View {
        GlassCard(tint: scale.tint(for: displayValue), padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(scale.format(displayValue))
                        .font(.auraNumeral(52, weight: .bold))
                        .foregroundStyle(Color.auraPrimaryText)
                        .contentTransition(.numericText())

                    Text(scale.unit)
                        .font(.auraDisplay(20, weight: .semibold))
                        .foregroundStyle(scale.tint(for: displayValue))

                    Spacer(minLength: 8)

                    Text(scale.qualityLabel(for: displayValue))
                        .auraChip(tint: scale.tint(for: displayValue))
                }

                ScaleBar(value: rawValue, scale: scale)

                if let advice = metric.advice(for: rawValue) {
                    Label(advice, systemImage: "lightbulb.fill")
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(
                    items: TimeRange.allCases,
                    selection: $range,
                    title: { $0.compactTitle }
                )

                TrendChart(
                    points: points,
                    scale: scale,
                    range: range,
                    style: range == .month ? .bars : .area,
                    height: 210
                )
            }
        }
    }

    /// The detail sheet buckets locally from whatever the store already holds, rather than
    /// issuing its own query — opening a sheet should never cost a round trip.
    private var points: [TrendPoint] {
        let end = store.lastUpdated ?? Date()
        let start = range.start(from: end)
        return Trend.buckets(
            from: store.readings.filter { $0.recordedAt >= start },
            metric: metric,
            interval: range.bucket,
            start: start,
            end: end
        )
    }

    private var statsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Over the last \(store.range.title.lowercased())")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraSecondaryText)

                if let summary = store.summaries[metric] {
                    HStack(spacing: 0) {
                        statColumn("Low", scale.convert(summary.minimum))
                        divider
                        statColumn("Average", scale.convert(summary.average))
                        divider
                        statColumn("Peak", scale.convert(summary.maximum))
                    }

                    RangeBar(summary: summary, scale: scale)

                    Text("\(summary.sampleCount) readings")
                        .font(.auraCaption)
                        .foregroundStyle(Color.auraTertiaryText)
                } else {
                    Text("No readings in this window yet.")
                        .font(.auraLabel)
                        .foregroundStyle(Color.auraTertiaryText)
                }
            }
        }
    }

    private func statColumn(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.auraCaption)
                .foregroundStyle(Color.auraTertiaryText)

            Text(scale.format(value))
                .font(.auraNumeral(20, weight: .bold))
                .foregroundStyle(Color.auraPrimaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.auraHairline)
            .frame(width: 1, height: 28)
    }

    private var explainerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("What this means", systemImage: metric.symbol)
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                Text(metric.explainer)
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Color.auraHairline)

                VStack(spacing: 8) {
                    ForEach(Array(scale.bands.enumerated()), id: \.offset) { index, band in
                        bandRow(index: index, band: band)
                    }
                }
            }
        }
    }

    private func bandRow(index: Int, band: MetricBand) -> some View {
        let lower = index == 0 ? nil : scale.bands[index - 1].upperBound
        let upper = band.upperBound.isFinite ? band.upperBound : nil

        return HStack(spacing: 10) {
            Circle()
                .fill(band.tint)
                .frame(width: 8, height: 8)

            Text(band.label)
                .font(.auraLabel)
                .foregroundStyle(Color.auraPrimaryText)

            Spacer(minLength: 8)

            Text(rangeText(lower: lower, upper: upper))
                .font(.auraNumeral(12))
                .foregroundStyle(Color.auraTertiaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func rangeText(lower: Double?, upper: Double?) -> String {
        switch (lower, upper) {
        case let (nil, .some(high)): "under \(scale.format(high))"
        case let (.some(low), nil): "\(scale.format(low))+"
        case let (.some(low), .some(high)): "\(scale.format(low))–\(scale.format(high))"
        case (nil, nil): "any"
        }
    }
}

#Preview("Detail") {
    MetricDetailView(metric: .co2)
        .environmentObject(AuraStore.preview())
}
