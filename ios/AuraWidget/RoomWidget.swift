import SwiftUI
import WidgetKit

struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AuraRoomWidget", provider: RoomProvider()) { entry in
            RoomWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.auraCard }
        }
        .configurationDisplayName("Room")
        .description("Temperature, CO₂, humidity and light where the monitor is.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

/// The home screen's copy of Home: the room's name, its temperature, and the three sensors
/// over the same dot grid the app draws them on.
struct RoomWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RoomEntry

    private var snapshot: RoomSnapshot { entry.snapshot }
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let notice = snapshot.notice, snapshot.isEmpty {
                Spacer(minLength: 0)
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.auraMutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                temperature

                Spacer(minLength: isLarge ? 10 : 6)

                VStack(spacing: isLarge ? 14 : 8) {
                    ForEach(Self.bars) { metric in
                        row(for: metric)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Everything but temperature, which leads the widget in its own right.
    private static let bars: [MetricKind] = [.co2, .humidity, .light]

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text((snapshot.zone ?? "Aura").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.auraPrimaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let recordedAt = snapshot.recordedAt {
                Text(recordedAt.formatted(date: .omitted, time: .shortened).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auraDimText)
            }
        }
    }

    /// The same thin figure Home leads with, sized down to the widget.
    private var temperature: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(wholeDegrees)
                .font(.system(size: isLarge ? 52 : 38, weight: .thin))
                .monospacedDigit()

            Text("°")
                .font(.system(size: isLarge ? 26 : 20, weight: .thin))
                .padding(.top, isLarge ? 3 : 2)
        }
        .foregroundStyle(Color.auraPrimaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.top, isLarge ? 6 : 2)
    }

    private var wholeDegrees: String {
        guard let temperature = snapshot.temperature else { return "––" }
        return temperature.formatted(.number.precision(.fractionLength(0)))
    }

    private func row(for metric: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: isLarge ? 7 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.auraPrimaryText.opacity(0.45))

                Text(metric.format(snapshot.values[metric]))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.auraPrimaryText)

                Text(metric.unitLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auraPrimaryText.opacity(0.5))

                Spacer(minLength: 0)
            }
            .lineLimit(1)

            // Fewer columns than the app's grid: at widget width the app's 96 would land
            // below a point apiece and smear into a line.
            DotMatrixBar(
                metric: metric,
                value: snapshot.values[metric],
                range: snapshot.range(for: metric),
                columns: isLarge ? 60 : 48,
                rows: isLarge ? 5 : 4,
                height: isLarge ? 15 : 11
            )
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Large", as: .systemLarge) {
    RoomWidget()
} timeline: {
    RoomEntry(date: Date(), snapshot: .preview)
    RoomEntry(date: Date(), snapshot: RoomSnapshot(notice: "Open Aura to sign in."))
}

#Preview("Medium", as: .systemMedium) {
    RoomWidget()
} timeline: {
    RoomEntry(date: Date(), snapshot: .preview)
}
