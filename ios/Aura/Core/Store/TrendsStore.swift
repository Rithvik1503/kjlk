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
    @Published private(set) var zoneBuckets: [ZoneBucket] = []
    /// Set when only the per-zone function is missing, so Areas can say so without hiding
    /// the rest of the screen.
    @Published private(set) var zonesUnavailable = false
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

    // MARK: - Areas

    /// Zones that reported in this window, in the order they should be listed.
    ///
    /// Sorted by how much they recorded rather than alphabetically — the room the monitor
    /// actually sat in should lead, not whichever name starts with an A.
    var zones: [String] {
        var totals: [String: Int] = [:]
        for bucket in zoneBuckets {
            totals[bucket.zone, default: 0] += 1
        }
        return totals.keys.sorted { left, right in
            let a = totals[left] ?? 0
            let b = totals[right] ?? 0
            return a == b ? left < right : a > b
        }
    }

    /// One value per slot for a metric within a single zone, gaps included.
    func values(for metric: MetricKind, zone: String, endingAt anchor: Date) -> [Double?] {
        let start = windowStart(endingAt: anchor)
        let component: Calendar.Component = window.isMonthly ? .month : .day

        let byDate = Dictionary(
            zoneBuckets
                .filter { $0.zone == zone }
                .map { (normalise($0.bucket), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return (0..<window.slots).compactMap { step in
            guard let date = calendar.date(byAdding: component, value: step, to: start) else { return nil }
            return byDate[normalise(date)]?.value(for: metric)
        }
    }

    func average(for metric: MetricKind, zone: String, endingAt anchor: Date) -> Double? {
        let present = values(for: metric, zone: zone, endingAt: anchor).compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    /// Axis top for a metric across every zone, so one room's bars are comparable with
    /// another's rather than each being scaled to itself.
    func zoneObservedMax(for metric: MetricKind) -> Double? {
        zoneBuckets.compactMap { $0.value(for: metric) }.filter(\.isFinite).max()
    }

    // MARK: - Whole-window series

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

    /// Areas is additive — a project without migration 0005 still gets the rest of the
    /// screen, and a note in that one section.
    private func loadZones(endingAt anchor: Date) async {
        do {
            zoneBuckets = try await client.zoneBuckets(
                from: windowStart(endingAt: anchor),
                to: windowEnd(endingAt: anchor),
                unit: window.bucketUnit,
                timeZone: calendar.timeZone,
                deviceID: preferences.selectedDeviceID
            )
            zonesUnavailable = false
        } catch is CancellationError {
            return
        } catch {
            zoneBuckets = []
            // PostgREST answers an unknown function with 404.
            if let supabaseError = error as? SupabaseError,
               case let .server(status, _) = supabaseError,
               status == 404 {
                zonesUnavailable = true
            }
        }
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

            await loadZones(endingAt: anchor)
        } catch is CancellationError {
            return
        } catch let error as SupabaseError {
            guard !Task.isCancelled else { return }
            buckets = []
            zoneBuckets = []

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
