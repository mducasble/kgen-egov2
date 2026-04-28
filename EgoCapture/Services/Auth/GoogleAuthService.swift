import Foundation
import GoogleSignIn
import UIKit

enum GoogleAuthService {
    static func signIn(
        presenting presenter: UIViewController?,
        referralCode: String?
    ) async throws -> AuthSession {
        guard let presenter else { throw AuthError.missingPresenter }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.server("Google did not return an id_token.")
        }
        let accessToken = result.user.accessToken.tokenString
        return try await KGenAuthClient.shared.google(
            idToken: idToken,
            accessToken: accessToken,
            referralCode: referralCode
        )
    }

    static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}

extension UIApplication {
    var firstKeyWindowRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
