import UIKit
import CloudKit
import UserNotifications

/// Registers for silent pushes (so iCloud changes arrive quickly) and installs a scene delegate
/// that receives "accept trip invitation" callbacks.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = self
        FlightStore.registerBackgroundTask()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show flight alerts (gate change, delay) even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch from an invitation link.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await TripSharing.accept(metadata) }
        }
    }

    /// App already running when the invitation link is tapped.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await TripSharing.accept(cloudKitShareMetadata) }
    }
}
