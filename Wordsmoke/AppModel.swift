import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
  var gameCenter = GameCenterService()
  var apiClient = APIClient(baseURL: AppEnvironment.baseURL)
  var session: SessionResponse?
  var statusMessage = "Initializing Game Center…"
  var isBusy = false

  func start() async {
    gameCenter.configure()
    statusMessage = "Waiting for Game Center sign-in…"
    logBundleInfo()
  }

  func connectToServer() async {
    guard gameCenter.isAuthenticated else {
      statusMessage = "Game Center sign-in required."
      return
    }

    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let signature = try await gameCenter.fetchIdentitySignature()
      let response = try await apiClient.createSession(
        signature: signature,
        displayName: gameCenter.playerDisplayName,
        nickname: nil
      )
      session = response
      statusMessage = "Connected to server."
    } catch {
      let debugInfo = debugDescription(for: error)
      statusMessage = "Failed to connect: \(debugInfo)"
      print("[GameCenter] Connect failed: \(debugInfo)")
      if let lastError = gameCenter.lastError {
        print("[GameCenter] Last error: \(lastError)")
      }
    }
  }

  private func debugDescription(for error: Error) -> String {
    if let apiError = error as? APIError {
      return apiError.localizedDescription
    }

    if let nsError = error as NSError? {
      return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }

    return error.localizedDescription
  }

  private func logBundleInfo() {
    let bundleID = Bundle.main.bundleIdentifier ?? "nil"
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    print("[Bundle] id=\(bundleID) version=\(shortVersion ?? "nil") build=\(build ?? "nil")")

    if shortVersion == nil || build == nil {
      print("[Bundle][Warning] Missing CFBundleShortVersionString (Marketing Version) and/or CFBundleVersion (Build). Set MARKETING_VERSION and CURRENT_PROJECT_VERSION in Build Settings or .xcconfig.")
    }
  }
}

enum AppEnvironment {
  static var baseURL: URL {
    #if DEBUG
    return URL(string: "https://karoline-unconsulted-oversensibly.ngrok-free.dev")!
    #else
    return URL(string: "https://www.akuaku.org")!
    #endif
  }
}
