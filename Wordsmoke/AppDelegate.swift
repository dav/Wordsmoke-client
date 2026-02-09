import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
  var pushService: PushNotificationService?

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { @MainActor in
      pushService?.handleDeviceToken(deviceToken)
    }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    Task { @MainActor in
      pushService?.handleRegistrationError(error)
    }
  }
}
