import Foundation

final class KGenAuthClient {
    static let shared = KGenAuthClient()

    private let baseURL: URL
    private let appKey: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(bundle: Bundle = .main, session: URLSession = .shared) {
        let info = bundle.infoDictionary ?? [:]
        let base = (info["KGEN_AUTH_BASE"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (info["KGEN_APP_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.baseURL = URL(string: base?.isEmpty == false ? base! : "https://wvsixcvsfndhoygbkzkj.supabase.co/functions/v1/auth-mobile")!
        self.appKey = key ?? ""
        self.session = session
    }

    func login(email: String, password: String) async throws -> AuthSession {
        let data = try await request(action: "login", body: [
            "email": normalizeEmail(email),
            "password": password,
        ])
        return try decodeSession(data)
    }

    func signup(
        email: String,
        password: String,
        fullName: String?,
        country: String?,
        city: String?,
        referralCode: String?
    ) async throws -> AuthSession {
        let data = try await request(action: "signup", body: [
            "email": normalizeEmail(email),
            "password": password,
            "full_name": fullName,
            "country": country,
            "city": city,
            "referral_code": referralCode,
        ])
        return try decodeSession(data)
    }

    func google(idToken: String, accessToken: String?, referralCode: String?) async throws -> AuthSession {
        let data = try await request(action: "google", body: [
            "id_token": idToken,
            "access_token": accessToken,
            "referral_code": referralCode,
        ])
        return try decodeSession(data)
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        let data = try await request(action: "refresh", body: ["refresh_token": refreshToken])
        return try decodeSession(data)
    }

    func me(accessToken: String) async throws -> AuthUser {
        let data = try await request(action: "me", body: [:], bearer: accessToken)
        struct Envelope: Codable { let user: AuthUser }
        do {
            return try decoder.decode(Envelope.self, from: data).user
        } catch {
            throw AuthError.decoding
        }
    }

    func forgotPassword(email: String) async throws {
        _ = try await request(action: "forgot-password", body: ["email": normalizeEmail(email)])
    }

    private func request(action: String, body: [String: Any?], bearer: String? = nil) async throws -> Data {
        guard !appKey.isEmpty, !appKey.contains("<") else {
            throw AuthError.missingConfiguration("KGEN_APP_KEY")
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: action)]
        guard let url = components.url else { throw AuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body.compactMapValues { $0 },
            options: []
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
            throw AuthError.server("Auth \(action) transport failed: \(error.localizedDescription) url=\(url.absoluteString)")
            #else
            throw AuthError.server("Auth request failed: \(error.localizedDescription)")
            #endif
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }

        if http.statusCode == 401 && action == "login" {
            throw AuthError.invalidCredentials
        }
        guard (200...299).contains(http.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            #if DEBUG
            throw AuthError.server("Auth \(action) failed (HTTP \(http.statusCode)): \(rawBody)")
            #else
            throw AuthError.server(errorMessage(from: data) ?? "Auth error HTTP \(http.statusCode)")
            #endif
        }
        return data
    }

    private func decodeSession(_ data: Data) throws -> AuthSession {
        do {
            return try decoder.decode(AuthSession.self, from: data)
        } catch {
            throw AuthError.decoding
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["error"] as? String
        else { return nil }
        return message
    }

    private func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
