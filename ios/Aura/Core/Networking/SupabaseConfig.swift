import Foundation

/// Where the app talks to, and with which public key.
///
/// The anon key is designed to ship inside clients — it grants nothing on its own, because
/// every table is behind row level security. The thing that must never be in here is the
/// service role key or the device ingest token.
struct SupabaseConfig: Equatable, Codable, Sendable {
    var url: URL
    var anonKey: String

    var restURL: URL { url.appendingPathComponent("rest/v1") }
    var authURL: URL { url.appendingPathComponent("auth/v1") }

    /// `wss://<project>.supabase.co/realtime/v1/websocket`
    var realtimeURL: URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = (components.scheme == "http") ? "ws" : "wss"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: anonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        return components.url
    }

    init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Accepts a bare project ref, a hostname, or a full URL, and trims any trailing path.
    init?(rawURL: String, anonKey: String) {
        let trimmedKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedKey.isEmpty else { return nil }

        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        if !trimmed.contains("://") {
            // A bare project ref like `abcdefghijklmno` expands to the hosted URL.
            trimmed = trimmed.contains(".") ? "https://\(trimmed)" : "https://\(trimmed).supabase.co"
        }

        guard let parsed = URL(string: trimmed), parsed.host != nil else { return nil }
        self.init(url: parsed, anonKey: trimmedKey)
    }

    /// Defaults baked in at build time via `Config.plist`, when the developer added one.
    ///
    /// Keeps the Simulator one tap from useful without putting credentials in source control.
    static var bundled: SupabaseConfig? {
        guard
            let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
            let values = NSDictionary(contentsOfFile: path) as? [String: Any],
            let rawURL = values["SupabaseURL"] as? String,
            let key = values["SupabaseAnonKey"] as? String,
            !rawURL.hasPrefix("YOUR_"),
            !key.hasPrefix("YOUR_")
        else { return nil }
        return SupabaseConfig(rawURL: rawURL, anonKey: key)
    }
}

/// Everything that can go wrong between the app and Supabase, in language worth showing a user.
enum SupabaseError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case invalidCredentials
    case emailNotConfirmed
    case rateLimited
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Aura isn't connected to a Supabase project yet."
        case .notSignedIn:
            "You're signed out."
        case .invalidCredentials:
            "That email and password combination didn't work."
        case .emailNotConfirmed:
            "Confirm your email address first — check your inbox for the link from Supabase."
        case .rateLimited:
            "Too many attempts. Wait a minute and try again."
        case let .server(status, message):
            message ?? "Supabase returned an error (\(status))."
        case let .transport(detail):
            detail
        case let .decoding(detail):
            "Couldn't read the response: \(detail)"
        }
    }

    /// Hints at whether retrying the same call might work.
    var isRetryable: Bool {
        switch self {
        case .transport, .rateLimited: true
        case let .server(status, _): status >= 500
        default: false
        }
    }
}
