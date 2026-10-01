import Foundation
import UserNotifications

/// Posts a local notification when a sensor's reading drops into a worse band than it was in
/// an hour ago.
///
/// Band crossings, not raw movement: 620 → 780 ppm is a rise but still fresh air, and a
/// notification for it would be noise. Each metric is also held down for an hour after it
/// fires, so a value hovering on a threshold can't buzz the phone every refresh.
///
/// These are *local* notifications, so they are posted when the app evaluates — in the
/// foreground, or during a background refresh if that capability is turned on (see the README).
/// Alerting while the app has not run for hours needs push from the server, which this is not.
@MainActor
final class AirQualityNotifier: ObservableObject {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let store: UserDefaults
    private let calendar = Calendar.current

    /// How far back "an hour ago" looks, and how long a metric stays quiet after firing.
    private let comparisonWindow: TimeInterval = 3600
    private let cooldown: TimeInterval = 3600

    init(center: UNUserNotificationCenter = .current(), store: UserDefaults = .standard) {
        self.center = center
        self.store = store
    }

    // MARK: - Authorisation

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Returns whether alerts may now be posted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    // MARK: - Evaluation

    /// Checks every metric for a band it has fallen out of in the last hour.
    ///
    /// Takes the day's readings rather than querying: the screen has already loaded them, and
    /// a notification is not worth a round trip.
    func evaluate(readings: [Reading], enabled: Bool) async {
        guard enabled, authorization == .authorized, readings.count > 1 else { return }

        let now = Date()
        let cutoff = now.addingTimeInterval(-comparisonWindow)

        // Only compare against a reading that is genuinely about an hour old; a device that
        // came online ten minutes ago has nothing to say about the last hour.
        guard let earlier = readings.last(where: { $0.recordedAt <= cutoff }) else { return }

        for metric in MetricKind.allCases {
            guard
                let current = latestValue(of: metric, in: readings),
                let previous = earlier.value(for: metric)
            else { continue }

            let currentBand = metric.band(for: current)
            let previousBand = metric.band(for: previous)
            guard currentBand.severity > previousBand.severity else { continue }
            guard !isCoolingDown(metric, now: now) else { continue }

            await post(metric: metric, value: current, band: currentBand)
            markNotified(metric, at: now)
        }
    }

    private func latestValue(of metric: MetricKind, in readings: [Reading]) -> Double? {
        readings.reversed().lazy.compactMap { $0.value(for: metric) }.first
    }

    private func post(metric: MetricKind, value: Double, band: MetricBand) async {
        let content = UNMutableNotificationContent()
        content.title = title(for: metric, band: band)
        content.body = body(for: metric, value: value, band: band)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "aura.deterioration.\(metric.rawValue).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil      // nil fires it immediately
        )
        try? await center.add(request)
    }

    private func title(for metric: MetricKind, band: MetricBand) -> String {
        switch metric {
        case .co2: "Air getting stuffy"
        case .temperature: band.label == "Hot" ? "Room heating up" : "Room cooling down"
        case .humidity: "Humidity drifting"
        case .light: "Light dropping"
        }
    }

    private func body(for metric: MetricKind, value: Double, band: MetricBand) -> String {
        let reading = "\(metric.format(value)) \(metric.unit)"

        switch metric {
        case .co2:
            return "CO₂ is up to \(reading) — \(band.label.lowercased()). Worth opening a window."
        case .temperature:
            return "Now \(reading), \(band.label.lowercased()), and moving the wrong way."
        case .humidity:
            return "Humidity is \(reading) — \(band.label.lowercased())."
        case .light:
            return "Down to \(reading) — \(band.label.lowercased())."
        }
    }

    // MARK: - Cooldown

    private func key(for metric: MetricKind) -> String {
        "notify.last.\(metric.rawValue)"
    }

    private func isCoolingDown(_ metric: MetricKind, now: Date) -> Bool {
        let last = store.double(forKey: key(for: metric))
        guard last > 0 else { return false }
        return now.timeIntervalSince1970 - last < cooldown
    }

    private func markNotified(_ metric: MetricKind, at date: Date) {
        store.set(date.timeIntervalSince1970, forKey: key(for: metric))
    }
}
