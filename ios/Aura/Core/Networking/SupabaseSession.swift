import Foundation

/// A signed-in Supabase session: the bearer token, how to renew it, and who it belongs to.
struct SupabaseSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?

    /// Treated as expired a minute early so a request never races the expiry.
    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    private enum UserKeys: String, CodingKey {
        case id
        case email
    }

    init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)

        // The token endpoint sends `expires_in` (seconds); our own cache writes `expires_at`.
        if let absolute = try container.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else if let relative = try container.decodeIfPresent(Double.self, forKey: .expiresIn) {
            expiresAt = Date().addingTimeInterval(relative)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }

        let user = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        userID = try user.decode(String.self, forKey: .id)
        email = try user.decodeIfPresent(String.self, forKey: .email)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)

        var user = container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        try user.encode(userID, forKey: .id)
        try user.encodeIfPresent(email, forKey: .email)
    }
}
