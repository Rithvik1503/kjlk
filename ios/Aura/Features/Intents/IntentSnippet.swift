import SwiftUI

/// What Siri shows under the spoken answer.
///
/// The same dot grid as everywhere else — a number read aloud says what it is, and the grid
/// says whether that's good, which is the part speech is bad at.
struct IntentSnippet: View {
    let snapshot: RoomSnapshot
    /// The sensor that was asked about, or nil for the whole-room answer.
    let metric: MetricKind?

    private var shown: [MetricKind] {
        if let metric { return [metric] }
        return [.co2, .humidity, .light]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text((snapshot.zone ?? "Aura").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.auraPrimaryText)

                Spacer(minLength: 8)

                if let temperature = snapshot.temperature, metric != .temperature {
                    Text("\(temperature.formatted(.number.precision(.fractionLength(0))))°")
                        .font(.system(size: 15, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Color.auraPrimaryText)
                }
            }

            if let notice = snapshot.notice, snapshot.isEmpty {
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.auraMutedText)
            } else {
                ForEach(shown) { metric in
                    row(for: metric)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.auraCard)
    }

    private func row(for metric: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.auraPrimaryText.opacity(0.45))

                Text(metric.format(snapshot.values[metric]))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.auraPrimaryText)

                Text(metric.unitLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auraPrimaryText.opacity(0.5))

                Spacer(minLength: 8)

                Text(metric.label(for: snapshot.values[metric]).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auraDimText)
            }
            .lineLimit(1)

            DotMatrixBar(
                metric: metric,
                value: snapshot.values[metric],
                range: snapshot.range(for: metric),
                columns: 64,
                rows: 5,
                height: 15
            )
        }
    }
}

#Preview("Snippet") {
    VStack(spacing: 16) {
        IntentSnippet(snapshot: .preview, metric: nil)
        IntentSnippet(snapshot: .preview, metric: .co2)
    }
    .padding(20)
    .background(Color.auraBase)
    .preferredColorScheme(.dark)
}
