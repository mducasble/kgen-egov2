import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(StoredAuthSession)
    }

    @Published private(set) var state: State = .loading
    @Published var errorMessage: String?

    private let client: KGenAuthClient
    private let store: AuthSessionStore

    init(
        client: KGenAuthClient = .shared,
        store: AuthSessionStore = .shared
    ) {
        self.client = client
        self.store = store
    }

    func bootstrap() async {
        guard let stored = store.load() else {
            state = .signedOut
            return
        }

        if stored.expiresAt.timeIntervalSinceNow > 300 {
            syncContributorProfile(from: stored.user)
            state = .signedIn(stored)
            return
        }

        do {
            try await save(client.refresh(refreshToken: stored.refreshToken))
        } catch {
            store.clear()
            state = .signedOut
        }
    }

    func login(email: String, password: String) async {
        await runAuthTask {
            try await client.login(email: email, password: password)
        }
    }

    func signup(
        email: String,
        password: String,
        fullName: String?,
        country: String?,
        city: String?,
        referralCode: String?
    ) async {
        await runAuthTask(preferredDisplayName: fullName, preferredCountry: country) {
            try await client.signup(
                email: email,
                password: password,
                fullName: fullName,
                country: country,
                city: city,
                referralCode: referralCode
            )
        }
    }

    func completeGoogle(idToken: String, accessToken: String?, referralCode: String?) async {
        await runAuthTask {
            try await client.google(
                idToken: idToken,
                accessToken: accessToken,
                referralCode: referralCode
            )
        }
    }

    func complete(session: AuthSession) async {
        await runAuthTask { session }
    }

    func forgotPassword(email: String) async {
        do {
            try await client.forgotPassword(email: email)
            errorMessage = "Password reset email sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        store.clear()
        state = .signedOut
    }

    private func runAuthTask(
        preferredDisplayName: String? = nil,
        preferredCountry: String? = nil,
        _ task: () async throws -> AuthSession
    ) async {
        errorMessage = nil
        do {
            try await save(task(), preferredDisplayName: preferredDisplayName, preferredCountry: preferredCountry)
        } catch {
            errorMessage = error.localizedDescription
            if case .loading = state {
                state = .signedOut
            }
        }
    }

    private func save(
        _ session: AuthSession,
        preferredDisplayName: String? = nil,
        preferredCountry: String? = nil
    ) async throws {
        let stored = StoredAuthSession(session: session)
        try store.save(stored)
        syncContributorProfile(from: stored.user, preferredDisplayName: preferredDisplayName, preferredCountry: preferredCountry)
        state = .signedIn(stored)
    }

    private func syncContributorProfile(
        from user: AuthUser,
        preferredDisplayName: String? = nil,
        preferredCountry: String? = nil
    ) {
        let fallback = preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = user.displayName ?? (fallback?.isEmpty == false ? fallback : nil)
        if let resolved, !resolved.isEmpty {
            UserDefaults.standard.set(resolved, forKey: CampaignConfig.userNameStorageKey)
        }

        let country = normalizeCountry(user.country ?? preferredCountry)
        if let country {
            UserDefaults.standard.set(country, forKey: CampaignConfig.countryStorageKey)
        }
    }

    private func normalizeCountry(_ country: String?) -> String? {
        let trimmed = country?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(2))
    }
}

private struct AuthViewModelKey: EnvironmentKey {
    static let defaultValue: AuthViewModel? = nil
}

extension EnvironmentValues {
    var authViewModel: AuthViewModel? {
        get { self[AuthViewModelKey.self] }
        set { self[AuthViewModelKey.self] = newValue }
    }
}
