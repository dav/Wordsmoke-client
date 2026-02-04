import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
  var gameCenter = GameCenterService()
  var apiClient = APIClient(baseURL: AppEnvironment.baseURL)
  let analytics = AnalyticsService()
  var session: SessionResponse?
  var currentGame: GameResponse?
  var games: [GameResponse] = []
  var inviteSheet: InviteSheet?
  var gameRoomModel: GameRoomModel?
  var statusMessage = "Initializing Game Center…"
  var connectionErrorMessage: String?
  var isBusy = false
  var navigationPath = NavigationPath()
  var clientPolicy: ClientPolicyResponse?
  private var lobbyPollingTask: Task<Void, Never>?
  private var connectionRetryTask: Task<Void, Never>?

  func start() async {
    gameCenter.configure()
    statusMessage = "Waiting for Game Center sign-in…"
    handleAuthChange()
    await refreshClientPolicy()
    logBundleInfo()
  }

  func updateBaseURLIfNeeded() {
    let baseURL = AppEnvironment.baseURL
    if apiClient.baseURL == baseURL {
      return
    }

    apiClient = APIClient(baseURL: baseURL)
    session = nil
    currentGame = nil
    games = []
    gameRoomModel = nil
    navigationPath = NavigationPath()
    statusMessage = "Server set to \(baseURL.absoluteString)."
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
        connectionErrorMessage = nil
        stopConnectionRetry()
      } else {
        statusMessage = "Game Center signed in."
        startConnectionRetry()
      }
    } else {
      if session == nil {
        statusMessage = "Game Center sign-in required."
        connectionErrorMessage = nil
        stopConnectionRetry()
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
      connectionErrorMessage = nil
      await loadGames()
    } catch {
      let debugInfo = debugDescription(for: error)
      statusMessage = "Failed to connect: \(debugInfo)"
      connectionErrorMessage = "Failed to connect to the server. Retrying…"
      print("[GameCenter] Connect failed: \(debugInfo)")
      if let lastError = gameCenter.lastError {
        print("[GameCenter] Last error: \(lastError)")
      }
    }
  }

  private func startConnectionRetry() {
    guard connectionRetryTask == nil else { return }
    connectionRetryTask = Task { [weak self] in
      guard let self else { return }
      var delay: Duration = .seconds(2)
      while !Task.isCancelled {
        if self.session != nil || !self.gameCenter.isAuthenticated {
          break
        }
        await self.connectToServer()
        if self.session != nil {
          break
        }
        try? await Task.sleep(for: delay)
        if delay < .seconds(30) {
          delay = min(delay * 2, .seconds(30))
        }
      }
      self.connectionRetryTask = nil
    }
  }

  private func stopConnectionRetry() {
    connectionRetryTask?.cancel()
    connectionRetryTask = nil
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
      if !AppEnvironment.isUITest {
        inviteSheet = InviteSheet(joinCode: game.joinCode)
      }
    } catch {
      statusMessage = "Failed to create game: \(debugDescription(for: error))"
    }
  }

  func joinGame(joinCode: String) async -> Bool {
    guard !isBusy else { return false }
    let cleanedCode = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedCode.isEmpty else {
      statusMessage = "Enter a join code."
      return false
    }

    isBusy = true
    defer { isBusy = false }

    do {
      let game = try await apiClient.joinGame(joinCode: cleanedCode)
      currentGame = game
      if let session {
        gameRoomModel = GameRoomModel(game: game, apiClient: apiClient, localPlayerID: session.playerID)
      }
      if let index = games.firstIndex(where: { $0.id == game.id }) {
        games[index] = game
      } else {
        games.insert(game, at: 0)
      }
      statusMessage = "Joined game."
      enterGame()
      return true
    } catch {
      statusMessage = "Failed to join game: \(debugDescription(for: error))"
      return false
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

  func startLobbyPolling() {
    lobbyPollingTask?.cancel()
    lobbyPollingTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        if self.session != nil {
          await self.loadGames()
        }
        try? await Task.sleep(for: .seconds(12))
      }
    }
  }

  func stopLobbyPolling() {
    lobbyPollingTask?.cancel()
    lobbyPollingTask = nil
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
      print(
        "[Bundle][Warning] Missing CFBundleShortVersionString (Marketing Version) and/or CFBundleVersion (Build). "
        + "Set MARKETING_VERSION and CURRENT_PROJECT_VERSION in Build Settings or .xcconfig."
      )
    }
  }

}
