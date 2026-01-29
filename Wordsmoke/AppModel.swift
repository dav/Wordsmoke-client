import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
  var gameCenter = GameCenterService()
  var apiClient = APIClient(baseURL: AppEnvironment.baseURL)
  var session: SessionResponse?
  var currentGame: GameResponse?
  var games: [GameResponse] = []
  var inviteSheet: InviteSheet?
  var gameRoomModel: GameRoomModel?
  var statusMessage = "Initializing Game Center…"
  var isBusy = false
  var navigationPath = NavigationPath()
  var clientPolicy: ClientPolicyResponse?

  func start() async {
    gameCenter.configure()
    statusMessage = "Waiting for Game Center sign-in…"
    handleAuthChange()
    await refreshClientPolicy()
    logBundleInfo()
  }

  func updateServerEnvironment(_ environment: ServerEnvironment) {
    if apiClient.baseURL == environment.baseURL {
      return
    }

    apiClient = APIClient(baseURL: environment.baseURL)
    session = nil
    currentGame = nil
    games = []
    gameRoomModel = nil
    navigationPath = NavigationPath()
    statusMessage = "Server set to \(environment.title)."
    handleAuthChange()
  }

  func refreshClientPolicy() async {
    do {
      clientPolicy = try await apiClient.fetchClientPolicy()
      if clientPolicy?.forceUpdate == true {
        statusMessage = clientPolicy?.message ?? "Update required."
      }
    } catch {
      // Keep silent; policy fetch shouldn't block app usage.
    }
  }

  func handleAuthChange() {
    if gameCenter.isAuthenticated {
      if session != nil {
        statusMessage = "Connected to server."
      } else {
        statusMessage = "Game Center signed in."
        Task {
          await connectToServer()
        }
      }
    } else {
      if session == nil {
        statusMessage = "Game Center sign-in required."
      }
    }
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
      await loadGames()
    } catch {
      let debugInfo = debugDescription(for: error)
      statusMessage = "Failed to connect: \(debugInfo)"
      print("[GameCenter] Connect failed: \(debugInfo)")
      if let lastError = gameCenter.lastError {
        print("[GameCenter] Last error: \(lastError)")
      }
    }
  }

  func loadGames() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      games = try await apiClient.fetchGames()
    } catch {
      statusMessage = "Failed to load games: \(debugDescription(for: error))"
    }
  }

  func createGameAndInvite(goalLength: Int) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let game = try await apiClient.createGame(goalLength: goalLength)
      currentGame = game
      games.insert(game, at: 0)
      if let session {
        gameRoomModel = GameRoomModel(game: game, apiClient: apiClient, localPlayerID: session.playerID)
      }
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
      if let currentGame {
        gameRoomModel?.updateGame(currentGame)
      }
      if let currentGame, let index = games.firstIndex(where: { $0.id == currentGame.id }) {
        games[index] = currentGame
      }
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
      if let currentGame {
        gameRoomModel?.updateGame(currentGame)
      }
      statusMessage = "Game started."
    } catch {
      statusMessage = "Failed to start game: \(debugDescription(for: error))"
    }
  }

  func enterGame() {
    guard let currentGame else { return }
    if let session {
      gameRoomModel = GameRoomModel(game: currentGame, apiClient: apiClient, localPlayerID: session.playerID)
    }
    navigationPath = NavigationPath()
    navigationPath.append(AppRoute.game)
  }

  func selectGame(_ game: GameResponse) {
    currentGame = game
    enterGame()
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
