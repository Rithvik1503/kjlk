import SwiftUI

/// What the number means, and what counts as good — a plain system list.
struct MetricInfoSheet: View {
    let metric: MetricKind

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(metric.explainer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Levels") {
                    ForEach(Array(metric.bands.enumerated()), id: \.offset) { index, band in
                        LabeledContent {
                            Text(rangeText(at: index, band: band))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            Label {
                                Text(band.label)
                            } icon: {
                                Circle()
                                    .fill(band.tint)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }

                Section {
                    Text("Readings come from an SCD40 sensor, sampled every few seconds and uploaded once a minute.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "under 600", "600–800", "2,000+" — bounded by the previous band's ceiling.
    private func rangeText(at index: Int, band: MetricBand) -> String {
        let lower = index == 0 ? nil : metric.bands[index - 1].upperBound
        let upper = band.upperBound.isFinite ? band.upperBound : nil

        switch (lower, upper) {
        case let (nil, .some(high)): return "under \(metric.format(high))"
        case let (.some(low), nil): return "\(metric.format(low))+"
        case let (.some(low), .some(high)): return "\(metric.format(low))–\(metric.format(high))"
        case (nil, nil): return "any"
        }
    }
}

#Preview("Info") {
    MetricInfoSheet(metric: .co2)
        .preferredColorScheme(.dark)
}
