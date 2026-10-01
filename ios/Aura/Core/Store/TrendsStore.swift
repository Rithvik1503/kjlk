import Foundation
import SwiftUI

/// Backs the Trends screen: bucketed history for the selected window, anchored on a date.
///
/// Separate from `AuraStore` because it answers a different question — that one is "what is it
/// like right now", this one is "what has it been like" — and because it reloads on a different
/// trigger. It borrows the client rather than opening its own.
@MainActor
final class TrendsStore: ObservableObject {
    @Published var window: TrendWindow = .week
    @Published private(set) var buckets: [MetricBucket] = []
    @Published private(set) var isLoading = false
    /// Set when the aggregate function is missing, so the screen can say which migration.
    @Published private(set) var needsMigration = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient
    private let preferences: Preferences
    private let calendar = Calendar.current

    private var loadTask: Task<Void, Never>?

    init(client: SupabaseClient, preferences: Preferences) {
        self.client = client
        self.preferences = preferences
    }

    // MARK: - Window arithmetic

    /// Start of the first bucket in the window ending at `anchor`.
    func windowStart(endingAt anchor: Date) -> Date {
        if window.isMonthly {
            let thisMonth = startOfMonth(anchor)
            return calendar.date(byAdding: .month, value: -(window.slots - 1), to: thisMonth) ?? thisMonth
        }
        let today = calendar.startOfDay(for: anchor)
        return calendar.date(byAdding: .day, value: -(window.slots - 1), to: today) ?? today
    }

    /// Exclusive end of the window — the start of the bucket after the last one.
    func windowEnd(endingAt anchor: Date) -> Date {
        if window.isMonthly {
            let thisMonth = startOfMonth(anchor)
            return calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
        }
        let today = calendar.startOfDay(for: anchor)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Every slot in the window, oldest first, including the empty ones.
    ///
    /// Gaps are kept rather than compacted away: a missing Wednesday should leave a hole
    /// where Wednesday was, not shuffle Thursday into its place.
    func slots(endingAt anchor: Date) -> [(date: Date, bucket: MetricBucket?)] {
        let start = windowStart(endingAt: anchor)
        let component: Calendar.Component = window.isMonthly ? .month : .day

        let byDate = Dictionary(
            buckets.map { (normalise($0.bucket), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return (0..<window.slots).compactMap { step in
            guard let date = calendar.date(byAdding: component, value: step, to: start) else { return nil }
            return (date, byDate[normalise(date)])
        }
    }

    func values(for metric: MetricKind, endingAt anchor: Date) -> [Double?] {
        slots(endingAt: anchor).map { $0.bucket?.value(for: metric) }
    }

    /// Mean across the window, ignoring empty slots.
    func average(for metric: MetricKind, endingAt anchor: Date) -> Double? {
        let present = values(for: metric, endingAt: anchor).compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    /// Largest value anywhere in the loaded history, which sets the top of the fixed axis.
    func observedMax(for metric: MetricKind) -> Double? {
        buckets.compactMap { $0.value(for: metric) }.filter(\.isFinite).max()
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func normalise(_ date: Date) -> Date {
        window.isMonthly ? startOfMonth(date) : calendar.startOfDay(for: date)
    }

    // MARK: - Stepping

    /// Moves the anchor one whole window back or forward, never past today.
    func step(_ direction: Int, from anchor: Date) -> Date {
        // The unit differs by window; the count is always a whole window's worth of it.
        let component: Calendar.Component = window.isMonthly ? .month : .day

        guard let moved = calendar.date(byAdding: component, value: window.slots * direction, to: anchor) else {
            return anchor
        }
        return min(moved, Date())
    }

    func canStepForward(from anchor: Date) -> Bool {
        if window.isMonthly {
            return startOfMonth(anchor) < startOfMonth(Date())
        }
        return calendar.startOfDay(for: anchor) < calendar.startOfDay(for: Date())
    }

    /// The range shown in the header pill — "25 SEP – 1 OCT", "SEP – OCT 26".
    func rangeLabel(endingAt anchor: Date) -> String {
        let start = windowStart(endingAt: anchor)

        if window.isMonthly {
            let from = start.formatted(.dateTime.month(.abbreviated))
            let to = anchor.formatted(.dateTime.month(.abbreviated).day())
            return "\(from) – \(to)".uppercased()
        }

        let from = start.formatted(.dateTime.day().month(.abbreviated))
        let to = anchor.formatted(.dateTime.day().month(.abbreviated))
        return "\(from) – \(to)".uppercased()
    }

    // MARK: - Loading

    func load(endingAt anchor: Date) async {
        loadTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad(endingAt: anchor)
        }
        loadTask = task
        await task.value
    }

    private func performLoad(endingAt anchor: Date) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await client.metricBuckets(
                from: windowStart(endingAt: anchor),
                to: windowEnd(endingAt: anchor),
                unit: window.bucketUnit,
                timeZone: calendar.timeZone,
                deviceID: preferences.selectedDeviceID
            )
            guard !Task.isCancelled else { return }

            buckets = fetched
            needsMigration = false
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as SupabaseError {
            guard !Task.isCancelled else { return }
            buckets = []

            // PostgREST answers an unknown function with 404; anything else is a real failure.
            if case let .server(status, _) = error, status == 404 {
                needsMigration = true
                errorMessage = nil
            } else {
                needsMigration = false
                errorMessage = error.localizedDescription
            }
        } catch {
            guard !Task.isCancelled else { return }
            buckets = []
            errorMessage = error.localizedDescription
        }
    }
}
