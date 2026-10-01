import AppIntents
import SwiftUI

/// The sensors, as something Siri can be asked about by name.
enum MetricAppValue: String, AppEnum {
    case co2
    case temperature
    case humidity
    case light

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sensor" }

    /// The right-hand strings are what Siri matches against, so each carries the words
    /// someone would actually say rather than only the formal name.
    static var caseDisplayRepresentations: [MetricAppValue: DisplayRepresentation] {
        [
            .co2: DisplayRepresentation(
                title: "CO₂",
                subtitle: "Carbon dioxide",
                synonyms: ["carbon dioxide", "co2", "air quality"]
            ),
            .temperature: DisplayRepresentation(
                title: "Temperature",
                synonyms: ["temp", "how hot", "how cold"]
            ),
            .humidity: DisplayRepresentation(
                title: "Humidity",
                synonyms: ["moisture", "damp"]
            ),
            .light: DisplayRepresentation(
                title: "Light",
                synonyms: ["brightness", "lux"]
            ),
        ]
    }

    var kind: MetricKind {
        switch self {
        case .co2: .co2
        case .temperature: .temperature
        case .humidity: .humidity
        case .light: .light
        }
    }
}

/// "Hey Siri, what's the CO₂ in Aura."
///
/// Answers without opening the app: it reads the same credentials from the keychain the
/// widget does, fetches, and speaks the result. Nothing is cached — if the monitor is offline
/// it says so rather than reading out an old number.
struct RoomReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Check a sensor"
    static var description = IntentDescription(
        "Reads the latest value from your room monitor.",
        categoryName: "Readings"
    )

    /// Answered in place; there is nothing in the app that a one-line answer doesn't cover.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Sensor")
    var metric: MetricAppValue

    static var parameterSummary: some ParameterSummary {
        Summary("Check the \(\.$metric)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let kind = metric.kind
        let snapshot = await RoomReader.current()

        guard let value = snapshot.values[kind] else {
            // `notice` is set when the fetch itself couldn't happen — not signed in, no
            // network. Saying that is more use than "no reading".
            let reason = snapshot.notice ?? "No \(kind.title.lowercased()) reading from your monitor yet."
            return .result(
                dialog: IntentDialog("\(reason)"),
                view: IntentSnippet(snapshot: snapshot, metric: kind)
            )
        }

        let where_ = snapshot.zone.map { " in \($0)" } ?? ""
        let spoken = "\(kind.title)\(where_) is \(kind.format(value)) \(kind.unit). \(kind.label(for: value))."

        return .result(
            dialog: IntentDialog("\(spoken)"),
            view: IntentSnippet(snapshot: snapshot, metric: kind)
        )
    }
}

/// "Hey Siri, how's the air in Aura." — every sensor at once.
struct RoomSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Check the room"
    static var description = IntentDescription(
        "Reads every sensor from your room monitor.",
        categoryName: "Readings"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = await RoomReader.current()

        guard !snapshot.values.isEmpty else {
            let reason = snapshot.notice ?? "Your monitor hasn't reported anything yet."
            return .result(
                dialog: IntentDialog("\(reason)"),
                view: IntentSnippet(snapshot: snapshot, metric: nil)
            )
        }

        let parts = [MetricKind.temperature, .co2, .humidity].compactMap { metric -> String? in
            guard let value = snapshot.values[metric] else { return nil }
            return "\(kindPhrase(metric)) \(metric.format(value)) \(metric.unit)"
        }

        let where_ = snapshot.zone ?? "your room"
        let spoken = "In \(where_): \(parts.joined(separator: ", "))."

        return .result(
            dialog: IntentDialog("\(spoken)"),
            view: IntentSnippet(snapshot: snapshot, metric: nil)
        )
    }

    /// Siri reads the dialog aloud, so these are spoken words rather than the labels the
    /// screen uses.
    private func kindPhrase(_ metric: MetricKind) -> String {
        switch metric {
        case .temperature: "it's"
        case .co2: "CO₂"
        case .humidity: "humidity"
        case .light: "light"
        }
    }
}

/// What Siri offers without being taught, and what appears in the Shortcuts app.
struct AuraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RoomSummaryIntent(),
            phrases: [
                "How's the air in \(.applicationName)",
                "Check my room in \(.applicationName)",
                "What's the room like in \(.applicationName)",
            ],
            shortTitle: "Check the room",
            systemImageName: "house"
        )

        AppShortcut(
            intent: RoomReadingIntent(),
            phrases: [
                "What's the \(\.$metric) in \(.applicationName)",
                "Check the \(\.$metric) in \(.applicationName)",
                "\(.applicationName) \(\.$metric)",
            ],
            shortTitle: "Check a sensor",
            systemImageName: "gauge.medium"
        )
    }
}
