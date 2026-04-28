import Foundation

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let nickname: String?
    let country: String?
    let city: String?
    let emailContact: String?
    let avatarUrl: String?
    let referralCode: String?

    enum CodingKeys: String, CodingKey {
        case id, email, country, city, nickname
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case emailContact = "email_contact"
        case avatarUrl = "avatar_url"
        case referralCode = "referral_code"
    }

    var displayName: String? {
        let full = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let full, !full.isEmpty { return full }

        let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !combined.isEmpty { return combined }

        let nick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nick, !nick.isEmpty { return nick }

        return nil
    }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct StoredAuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    init(session: AuthSession, now: Date = Date()) {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        self.expiresAt = now.addingTimeInterval(TimeInterval(session.expiresIn))
        self.user = session.user
    }
}

enum AuthError: LocalizedError {
    case missingConfiguration(String)
    case invalidResponse
    case invalidCredentials
    case server(String)
    case decoding
    case missingPresenter

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key): return "Missing auth configuration: \(key)"
        case .invalidResponse: return "Invalid auth response."
        case .invalidCredentials: return "Invalid email or password."
        case .server(let message): return message
        case .decoding: return "Could not decode auth response."
        case .missingPresenter: return "Could not open Google Sign-In."
        }
    }
}
