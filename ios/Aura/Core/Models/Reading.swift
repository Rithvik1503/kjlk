import Foundation

/// One sample from the ESP32: CO₂, temperature, humidity and light, taken at the same instant.
///
/// Mirrors a row of `public.readings`. Every measurement is optional because a sensor can
/// drop out independently of the others — the SCD40 can fail to produce a reading while the
/// BH1750 keeps working, and we would rather plot a gap than a zero.
struct Reading: Identifiable, Hashable, Sendable {
    let id: Int64
    let deviceID: String
    let recordedAt: Date
    let co2: Double?
    let temperature: Double?
    let humidity: Double?
    let light: Double?

    init(
        id: Int64,
        deviceID: String,
        recordedAt: Date,
        co2: Double? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil,
        light: Double? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.recordedAt = recordedAt
        self.co2 = co2
        self.temperature = temperature
        self.humidity = humidity
        self.light = light
    }

    func value(for metric: MetricKind) -> Double? {
        switch metric {
        case .co2: co2
        case .temperature: temperature
        case .humidity: humidity
        case .light: light
        }
    }

    /// True when at least one sensor reported something we can draw.
    var hasAnyValue: Bool {
        MetricKind.allCases.contains { value(for: $0) != nil }
    }
}

// MARK: - Decoding

extension Reading: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case recordedAt = "recorded_at"
        case co2 = "co2_ppm"
        case temperature = "temperature_c"
        case humidity = "humidity_percent"
        case light = "light_lux"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // PostgREST returns `bigint` as a JSON number, but a Realtime `record` payload can
        // deliver the same column as a string. Accept either rather than failing the row.
        if let numeric = try? container.decode(Int64.self, forKey: .id) {
            id = numeric
        } else if let text = try? container.decode(String.self, forKey: .id), let parsed = Int64(text) {
            id = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Reading id was neither a number nor a numeric string"
            )
        }

        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? "unknown"

        let timestamp = try container.decode(String.self, forKey: .recordedAt)
        guard let date = PostgresDate.parse(timestamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .recordedAt,
                in: container,
                debugDescription: "Unrecognised timestamp \(timestamp)"
            )
        }
        recordedAt = date

        co2 = Self.lenientDouble(container, .co2)
        temperature = Self.lenientDouble(container, .temperature)
        humidity = Self.lenientDouble(container, .humidity)
        light = Self.lenientDouble(container, .light)
    }

    /// Reads a measurement that may arrive as a number, a numeric string, or null.
    ///
    /// A sensor value we can't parse becomes `nil`, which draws as a gap — the same as a
    /// missing one. Throwing here would discard the other three sensors in the same row.
    private static func lenientDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(text).flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }
}

// MARK: - Local cache encoding

extension Reading: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(PostgresDate.string(from: recordedAt), forKey: .recordedAt)
        try container.encodeIfPresent(co2, forKey: .co2)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(humidity, forKey: .humidity)
        try container.encodeIfPresent(light, forKey: .light)
    }
}

// MARK: - Timestamps

/// Postgres hands back timestamps like `2026-10-01T03:04:05.123456+00:00`.
///
/// `ISO8601DateFormatter` only accepts up to three fractional digits, so anything with
/// microsecond precision fails to parse. We normalise first, then try the strict parsers.
enum PostgresDate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        let normalised = normalise(raw)
        return withFraction.date(from: normalised) ?? withoutFraction.date(from: normalised)
    }

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// Clamps the fractional second to three digits and makes sure a zone is present.
    private static func normalise(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Postgres sometimes uses a space instead of the ISO `T` separator.
        if let space = value.firstIndex(of: " "), !value.contains("T") {
            value.replaceSubrange(space...space, with: "T")
        }

        if let dot = value.firstIndex(of: ".") {
            let afterDot = value.index(after: dot)
            // Digits that belong to the fractional second, stopping at the zone designator.
            var cursor = afterDot
            while cursor < value.endIndex, value[cursor].isNumber {
                cursor = value.index(after: cursor)
            }
            let digitCount = value.distance(from: afterDot, to: cursor)
            if digitCount > 3 {
                let keepUntil = value.index(afterDot, offsetBy: 3)
                value.removeSubrange(keepUntil..<cursor)
            } else if digitCount < 3 {
                value.insert(contentsOf: String(repeating: "0", count: 3 - digitCount), at: cursor)
            }
        } else if let zone = zoneStart(in: value) {
            value.insert(contentsOf: ".000", at: zone)
        } else {
            value += ".000Z"
            return value
        }

        if zoneStart(in: value) == nil {
            value += "Z"
        }
        return value
    }

    /// Index where the timezone designator begins, searching only the time portion.
    private static func zoneStart(in value: String) -> String.Index? {
        guard let timeStart = value.firstIndex(of: "T") else { return nil }
        var cursor = value.index(after: timeStart)
        while cursor < value.endIndex {
            let character = value[cursor]
            if character == "Z" || character == "+" || character == "-" {
                return cursor
            }
            cursor = value.index(after: cursor)
        }
        return nil
    }
}
