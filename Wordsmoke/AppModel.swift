import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
  var gameCenter = GameCenterService()
  var apiClient = APIClient(baseURL: AppEnvironment.baseURL)
  var session: SessionResponse?
  var currentGame: GameResponse?
  var inviteSheet: InviteSheet?
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
      apiClient.authToken = response.token
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

  func createGameAndInvite(goalLength: Int) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let game = try await apiClient.createGame(goalLength: goalLength)
      currentGame = game
      statusMessage = "Game created."
      inviteSheet = InviteSheet(joinCode: game.joinCode, minPlayers: 2, maxPlayers: 4)
    } catch {
      statusMessage = "Failed to create game: \(debugDescription(for: error))"
    }
  }

  func refreshGame() async {
    guard let gameID = currentGame?.id else { return }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      currentGame = try await apiClient.fetchGame(id: gameID)
      statusMessage = "Game refreshed."
    } catch {
      statusMessage = "Failed to refresh game: \(debugDescription(for: error))"
    }
  }

  func startGame() async {
    guard let gameID = currentGame?.id else { return }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      currentGame = try await apiClient.updateGameStatus(id: gameID, status: "active")
      statusMessage = "Game started."
    } catch {
      statusMessage = "Failed to start game: \(debugDescription(for: error))"
    }
  }

  func dismissInviteSheet() {
    inviteSheet = nil
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

struct InviteSheet: Identifiable {
  let id = UUID()
  let joinCode: String
  let minPlayers: Int
  let maxPlayers: Int
}
