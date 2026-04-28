import SwiftUI
import GoogleSignIn
import UIKit

final class OrientationLock {
    static let shared = OrientationLock()
    var mask: UIInterfaceOrientationMask = .all

    func lock(_ orientation: UIInterfaceOrientationMask) {
        mask = orientation
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GoogleAuthService.handle(url: url)
    }
}

@main
struct EgoCaptureApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Top-level view switcher between real auth and the capture workflow.
private struct RootView: View {
    @StateObject private var auth = AuthViewModel()

    var body: some View {
        ZStack {
            switch auth.state {
            case .loading:
                ProgressView()
                    .tint(KE.accentBlue)
            case .signedIn:
                KGenEyeHomeView()
                    .environment(\.authViewModel, auth)
                    .transition(.opacity)
            case .signedOut:
                LoginView(auth: auth)
                    .transition(.opacity)
            }
        }
        .task { await auth.bootstrap() }
        .animation(.easeInOut(duration: 0.35), value: auth.state)
    }
}
