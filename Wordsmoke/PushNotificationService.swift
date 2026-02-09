import Foundation
import UserNotifications
import UIKit

@MainActor
@Observable
final class PushNotificationService: NSObject {
  var deviceToken: String?
  var permissionGranted = false
  private var apiClient: APIClient?
  private var registeredToken: String?
  var onNotificationTapped: ((String) -> Void)?

  func requestPermissionAndRegister() {
    Task {
      let center = UNUserNotificationCenter.current()
      center.delegate = self

      do {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        permissionGranted = granted
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
        }
      } catch {
        Log.log(
          "Push notification authorization failed",
          level: .warning,
          category: .push,
          error: error,
          metadata: ["operation": "request_authorization"]
        )
      }
    }
  }

  func handleDeviceToken(_ tokenData: Data) {
    let token = tokenData.map { String(format: "%02x", $0) }.joined()
    deviceToken = token
    sendTokenToServer()
  }

  func handleRegistrationError(_ error: Error) {
    Log.log(
      "Remote notification registration failed",
      level: .warning,
      category: .push,
      error: error,
      metadata: ["operation": "register_remote_notifications"]
    )
  }

  func update(apiClient: APIClient) {
    self.apiClient = apiClient
    sendTokenToServer()
  }

  private func sendTokenToServer() {
    guard let token = deviceToken, let apiClient, apiClient.authToken != nil else { return }
    guard token != registeredToken else { return }

    Task {
      do {
        let environment: String
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif
        try await apiClient.registerDeviceToken(token, environment: environment)
        registeredToken = token
      } catch {
        Log.log(
          "Failed to register device token",
          level: .warning,
          category: .push,
          error: error,
          metadata: ["operation": "register_device_token"]
        )
      }
    }
  }
}

extension PushNotificationService: @preconcurrency UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let userInfo = notification.request.content.userInfo
    if let gameID = userInfo["game_id"] as? String {
      // Don't show banner if user is already viewing this game
      // For now, show all notifications as banners
      _ = gameID
    }
    return [.banner, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    if let gameID = userInfo["game_id"] as? String {
      onNotificationTapped?(gameID)
    }
  }
}
