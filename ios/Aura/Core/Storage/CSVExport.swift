import Foundation

/// Writes readings out as a CSV in the temporary directory, ready to hand to a share sheet.
///
/// Values are exported in the units shown in the app, and the header row says which — a file
/// of bare numbers with no units is useless six months later.
enum CSVExport {
    /// Main-actor isolated because it reads `Preferences`, which is. Exports are small and
    /// user-initiated, so building the file on the main thread costs nothing noticeable.
    @MainActor
    static func write(readings: [Reading], day: Date, preferences: Preferences) throws -> URL {
        let scales = Dictionary(
            uniqueKeysWithValues: MetricKind.allCases.map { ($0, preferences.scale(for: $0)) }
        )

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = [
            [
                "recorded_at",
                "device_id",
                "co2_\(scales[.co2]?.unit ?? "ppm")",
                "temperature_\(scales[.temperature]?.unit ?? "C")",
                "humidity_\(scales[.humidity]?.unit ?? "%")",
                "light_\(scales[.light]?.unit ?? "lux")",
            ].joined(separator: ",")
        ]

        for reading in readings {
            let fields: [String] = [
                timestampFormatter.string(from: reading.recordedAt),
                escape(reading.deviceID),
                number(reading.co2, scales[.co2]),
                number(reading.temperature, scales[.temperature]),
                number(reading.humidity, scales[.humidity]),
                number(reading.light, scales[.light]),
            ]
            lines.append(fields.joined(separator: ","))
        }

        let filenameFormatter = DateFormatter()
        filenameFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "aura-\(filenameFormatter.string(from: day)).csv"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Fixed-point, period-separated and unlocalised — a CSV is for machines, not for reading.
    private static func number(_ raw: Double?, _ scale: DisplayScale?) -> String {
        guard let raw, let scale else { return "" }
        return String(format: "%.\(scale.fractionDigits)f", scale.convert(raw))
    }

    /// Quotes a field only when it contains something that would break the row.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
