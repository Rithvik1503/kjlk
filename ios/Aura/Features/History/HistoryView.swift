import SwiftUI
import UIKit

/// Pick a day, see exactly what the room did on it.
///
/// Each day is fetched on demand and cached in memory for the session, so flicking between
/// days you've already looked at is instant.
struct HistoryView: View {
    @EnvironmentObject private var store: AuraStore

    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var daysWithData: Set<Date> = []
    @State private var dayReadings: [Reading] = []

    @State private var isLoadingDay = false
    @State private var isLoadingMonth = false
    @State private var loadError: String?

    @State private var chartMetric: MetricKind = .co2
    @State private var exportURL: URL?

    /// Days already fetched this session.
    @State private var cachedDays: [Date: [Reading]] = [:]

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.cardSpacing) {
                header
                calendarCard

                if isLoadingDay && dayReadings.isEmpty {
                    loadingCard
                } else if dayReadings.isEmpty {
                    emptyDayCard
                } else {
                    summaryCard
                    chartCard
                    metricBreakdown
                    exportButton
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .task { await loadMonth() }
        .task(id: selectedDate) { await loadDay() }
        .refreshable {
            cachedDays.removeValue(forKey: calendar.startOfDay(for: selectedDate))
            await loadDay()
            await loadMonth()
        }
        .sheet(item: Binding(
            get: { exportURL.map { ExportFile(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { file in
            ShareSheet(items: [file.url])
        }
        .overlay(alignment: .top) {
            if let loadError {
                ErrorBanner(message: loadError) { self.loadError = nil }
                    .padding(.horizontal, Metrics.screenPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: loadError)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.auraDisplay(26, weight: .bold))
                    .foregroundStyle(Color.auraPrimaryText)

                Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraSecondaryText)
            }

            Spacer(minLength: 8)

            if !calendar.isDateInToday(selectedDate) {
                PillButton(title: "Today", symbol: "arrow.uturn.left") {
                    withAnimation(Motion.snappy) {
                        selectedDate = Date()
                        visibleMonth = Date()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var calendarCard: some View {
        GlassCard {
            CalendarMonthView(
                selectedDate: $selectedDate,
                visibleMonth: $visibleMonth,
                daysWithData: daysWithData,
                isLoading: isLoadingMonth,
                onMonthChange: { _ in
                    Task { await loadMonth() }
                }
            )
        }
    }

    // MARK: - Day states

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading that day…")
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 30)
        }
    }

    private var emptyDayCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.auraTertiaryText)

                Text("Nothing recorded")
                    .font(.auraCardTitle)
                    .foregroundStyle(Color.auraPrimaryText)

                Text("The monitor didn't report on this day.")
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraTertiaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
    }

    // MARK: - Day detail

    private var dayStatus: RoomStatus {
        // The verdict for a past day is the average of it, not whatever it happened to end on.
        guard !dayReadings.isEmpty else { return .unknown }

        let averaged = Reading(
            id: 0,
            deviceID: dayReadings[0].deviceID,
            recordedAt: selectedDate,
            co2: average(of: \.co2),
            temperature: average(of: \.temperature),
            humidity: average(of: \.humidity),
            light: average(of: \.light)
        )
        return RoomStatus.evaluate(averaged)
    }

    private func average(of keyPath: KeyPath<Reading, Double?>) -> Double? {
        let values = dayReadings.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var summaryCard: some View {
        let status = dayStatus

        return GlassCard(tint: status.tint, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Day score")
                            .font(.auraLabel)
                            .foregroundStyle(Color.auraSecondaryText)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(status.score.formatted(.number.precision(.fractionLength(0))))
                                .font(.auraNumeral(42, weight: .bold))
                                .foregroundStyle(Color.auraPrimaryText)

                            Text("/ 100")
                                .font(.auraDisplay(15, weight: .semibold))
                                .foregroundStyle(Color.auraTertiaryText)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(status.headline)
                            .auraChip(tint: status.tint)

                        Text("\(dayReadings.count) readings")
                            .font(.auraCaption)
                            .foregroundStyle(Color.auraTertiaryText)

                        if let first = dayReadings.first, let last = dayReadings.last {
                            Text("\(first.recordedAt.formatted(date: .omitted, time: .shortened)) – \(last.recordedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.auraCaption)
                                .foregroundStyle(Color.auraTertiaryText)
                        }
                    }
                }

                Text(status.detail)
                    .font(.auraLabel)
                    .foregroundStyle(Color.auraSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(chartMetric.title, subtitle: "Across the day")

                metricPicker

                TrendChart(
                    points: dayPoints(for: chartMetric),
                    scale: store.preferences.scale(for: chartMetric),
                    range: .day,
                    height: 210
                )
            }
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MetricKind.allCases) { metric in
                    let isSelected = metric == chartMetric
                    let scale = store.preferences.scale(for: metric)
                    let tint = scale.tint(for: scale.convert(average(of: keyPath(for: metric))))

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
                        .background(Capsule().fill(isSelected ? tint : Color.auraSurfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func keyPath(for metric: MetricKind) -> KeyPath<Reading, Double?> {
        switch metric {
        case .co2: \.co2
        case .temperature: \.temperature
        case .humidity: \.humidity
        case .light: \.light
        }
    }

    /// Buckets the selected day into 15-minute steps, anchored to local midnight.
    private func dayPoints(for metric: MetricKind) -> [TrendPoint] {
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return Trend.buckets(
            from: dayReadings,
            metric: metric,
            interval: 15 * 60,
            start: start,
            end: end
        )
    }

    private var metricBreakdown: some View {
        VStack(spacing: Metrics.cardSpacing) {
            ForEach(MetricKind.allCases) { metric in
                if let summary = MetricSummary.make(metric: metric, readings: dayReadings) {
                    MetricRangeCard(
                        summary: summary,
                        scale: store.preferences.scale(for: metric),
                        rangeTitle: "Day",
                        lastReadingAt: dayReadings.last?.recordedAt
                    )
                }
            }
        }
    }

    private var exportButton: some View {
        ProminentButton(title: "Export this day as CSV", symbol: "square.and.arrow.up", tint: .auraIndigo) {
            export()
        }
        .padding(.top, 4)
    }

    private func export() {
        do {
            exportURL = try CSVExport.write(
                readings: dayReadings,
                day: selectedDate,
                preferences: store.preferences
            )
            Haptics.success()
        } catch {
            loadError = "Couldn't build the CSV: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    // MARK: - Loading

    private func loadDay() async {
        let key = calendar.startOfDay(for: selectedDate)

        if let cached = cachedDays[key] {
            dayReadings = cached
            return
        }

        isLoadingDay = true
        defer { isLoadingDay = false }

        do {
            let fetched = try await store.readings(forDayContaining: selectedDate)
            guard calendar.startOfDay(for: selectedDate) == key else { return } // Selection moved on.
            cachedDays[key] = fetched
            dayReadings = fetched
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            dayReadings = []
            loadError = error.localizedDescription
        }
    }

    private func loadMonth() async {
        isLoadingMonth = true
        defer { isLoadingMonth = false }

        do {
            let days = try await store.daysWithData(inMonthOf: visibleMonth)
            // Merge rather than replace, so dots for other months survive navigation.
            daysWithData.formUnion(days)
        } catch is CancellationError {
            return
        } catch {
            // Dots are decoration; failing to fetch them shouldn't raise an alarm.
        }
    }
}

/// Wrapper so a URL can drive `.sheet(item:)`.
private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Bridges `UIActivityViewController`, which SwiftUI's `ShareLink` can't fully replace here
/// because the file is written lazily at the moment of tapping.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("History") {
    HistoryView()
        .environmentObject(AuraStore.preview())
        .background(Color.auraBase)
        .preferredColorScheme(.dark)
}
