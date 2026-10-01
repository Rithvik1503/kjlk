import Foundation

/// What the widget draws: one room, at one moment.
///
/// Values are resolved per metric rather than taken from a single row, the same way Home
/// does it — a sample where the BH1750 didn't answer shouldn't blank the light figure while
/// the SCD40 beside it is reporting fine.
struct RoomSnapshot {
    var zone: String?
    var values: [MetricKind: Double] = [:]
    var recordedAt: Date?
    /// Set when there is nothing to draw and the reason is worth saying.
    var notice: String?

    var temperature: Double? { values[.temperature] }

    var isEmpty: Bool { values.isEmpty }

    /// The span the light grid covers, widened to the next round thousand when direct sun
    /// runs past the default — otherwise a sunny windowsill pins the marker at the end.
    func range(for metric: MetricKind) -> ClosedRange<Double> {
        guard metric == .light, let value = values[.light], value > metric.scale.upperBound else {
            return metric.scale
        }
        let top = (value / 1000).rounded(.up) * 1000
        return metric.scale.lowerBound...max(top, metric.scale.upperBound)
    }

    static func resolved(from readings: [Reading]) -> RoomSnapshot {
        var snapshot = RoomSnapshot()
        guard !readings.isEmpty else { return snapshot }

        let newestFirst = readings.sorted { $0.recordedAt > $1.recordedAt }

        for metric in MetricKind.allCases {
            if let value = newestFirst.lazy.compactMap({ $0.value(for: metric) }).first {
                snapshot.values[metric] = value
            }
        }
        snapshot.zone = newestFirst.lazy.compactMap(\.zone).first
        snapshot.recordedAt = newestFirst.first?.recordedAt
        return snapshot
    }

    /// Stand-in for the widget gallery, which renders before any credentials are available.
    static let preview = RoomSnapshot(
        zone: "My Room",
        values: [.temperature: 22.4, .co2: 712, .humidity: 47, .light: 284],
        recordedAt: Date()
    )
}
