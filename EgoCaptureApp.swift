import SwiftUI
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

/// Top-level view switcher between the dummy `LoginView` and the real
/// `KGenEyeHomeView`. Auth is purely cosmetic for now — the real wiring
/// (Keychain persistence, Google SDK, backend call) lands alongside the
/// auth provider integration.
private struct RootView: View {
    @State private var isAuthenticated = false

    var body: some View {
        ZStack {
            if isAuthenticated {
                KGenEyeHomeView()
                    .transition(.opacity)
            } else {
                LoginView(onAuthenticated: {
                    isAuthenticated = true
                })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isAuthenticated)
    }
}
