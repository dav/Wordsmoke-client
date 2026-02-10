import Foundation
import GameKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
  var gameCenter = GameCenterService()
  var apiClient: APIClient
  var matchmakingProvider: MatchmakingProvider
  let analytics = AnalyticsService.shared
  let pushService = PushNotificationService()
  var session: SessionResponse?
  var currentGame: GameResponse?
  var games: [GameResponse] = []
  var gameRoomModel: GameRoomModel?
  var statusMessage = "Initializing Game Center…"
  var connectionErrorMessage: String?
  var isBusy = false
  var isLoadingGames = false
  var hasLoadedGames = false
  var navigationPath = NavigationPath()
  var clientPolicy: ClientPolicyResponse?
  var showNewGameSheet = false
  var showInvitePlayersSheet = false
  var availableGoalLengths: [Int] = []
  var pendingGoalLength: Int = 5
  var pendingPlayerCount: Int = 2
  private var lobbyPollingTask: Task<Void, Never>?
  private var connectionRetryTask: Task<Void, Never>?

  init() {
    let client = APIClient(baseURL: AppEnvironment.baseURL)
    self.apiClient = client
    self.matchmakingProvider = AppModel.makeMatchmakingProvider(apiClient: client)
  }

  func start() async {
    apiClient.debugMatchmakingToken = AppEnvironment.debugMatchmakingToken
    matchmakingProvider.update(apiClient: apiClient)
    pushService.onNotificationTapped = { [weak self] gameID in
      Task { @MainActor [weak self] in
        await self?.openGameFromNotification(gameID: gameID)
      }
    }
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
    apiClient.debugMatchmakingToken = AppEnvironment.debugMatchmakingToken
    matchmakingProvider.update(apiClient: apiClient)
    session = nil
    currentGame = nil
    games = []
    hasLoadedGames = false
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
      matchmakingProvider.update(apiClient: apiClient)
      pushService.update(apiClient: apiClient)
      pushService.requestPermissionAndRegister()
      statusMessage = "Connected to server."
      connectionErrorMessage = nil
      await loadGoalWordLengths()
      await loadGames()
    } catch {
      let debugInfo = debugDescription(for: error)
      statusMessage = "Failed to connect: \(debugInfo)"
      connectionErrorMessage = "Failed to connect to the server. Retrying…"
      Log.log(
        "Connect to server failed",
        level: .error,
        category: .gameCenter,
        error: error,
        metadata: ["operation": "connect_to_server"]
      )
      if let lastError = gameCenter.lastError {
        Log.log(
          "Game Center reported a last error",
          level: .warning,
          category: .gameCenter,
          error: lastError,
          metadata: ["operation": "connect_to_server_last_error"]
        )
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

  func loadGoalWordLengths() async {
    do {
      let lengths = try await apiClient.fetchGoalWordLengths()
      availableGoalLengths = lengths
      if let first = lengths.first, !lengths.contains(pendingGoalLength) {
        pendingGoalLength = first
      }
    } catch {
      Log.log(
        "Failed to load goal word lengths",
        level: .warning,
        category: .api,
        error: error,
        metadata: ["operation": "load_goal_word_lengths"]
      )
    }
  }

  func loadGames() async {
    guard !isLoadingGames else { return }
    isLoadingGames = true
    defer { isLoadingGames = false }

    do {
      games = try await apiClient.fetchGames()
      hasLoadedGames = true
    } catch {
      statusMessage = "Failed to load games: \(debugDescription(for: error))"
    }
  }

  func presentNewGameSheet() {
    showNewGameSheet = true
  }

  func createGameWithLength(_ goalLength: Int, playerCount: Int) async {
    showNewGameSheet = false
    pendingGoalLength = goalLength
    pendingPlayerCount = playerCount
    showInvitePlayersSheet = true
  }

  func dismissInvitePlayers() {
    showInvitePlayersSheet = false
  }

  func createGameWithInvites(inviteeIDs: [String]) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let game = try await matchmakingProvider.createGame(
        goalLength: pendingGoalLength,
        playerCount: pendingPlayerCount,
        inviteeIDs: inviteeIDs
      )
      showInvitePlayersSheet = false
      currentGame = game
      games.insert(game, at: 0)
      if let session {
        gameRoomModel = GameRoomModel(game: game, apiClient: apiClient, localPlayerID: session.playerID)
      }
      statusMessage = "Game created."

      if let matchID = game.gcMatchId {
        matchmakingProvider.startListening(for: matchID) { [weak self] event in
          Task { @MainActor in
            await self?.handleMatchmakingEvent(event)
          }
        }
      }

      enterGame()
    } catch {
      statusMessage = "Failed to create game: \(debugDescription(for: error))"
      
      Log.log(
        "Failed to create game",
        level: .error,
        category: .appModel,
        error: error,
        metadata: [
          "operation": "create_game_with_invites"
        ]
      )

    }
  }

  func handleIncomingTurnBasedMatch(_ match: GKTurnBasedMatch) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    let maxRetries = 3
    let retryDelay: Duration = .seconds(2)

    for attempt in 1...maxRetries {
      do {
        let game = try await apiClient.joinGameByMatchId(match.matchID)
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
        return
      } catch let error as APIError {
        if case .statusCode(404, _) = error, attempt < maxRetries {
          Log.log(
            "Game not found for turn-based match, retrying",
            level: .info,
            category: .gameCenter,
            error: error,
            metadata: [
              "operation": "join_game_by_match_id_retry",
              "match_id": match.matchID,
              "attempt": "\(attempt)",
              "max_retries": "\(maxRetries)"
            ]
          )
          try? await Task.sleep(for: retryDelay)
          continue
        }
        statusMessage = "Failed to join game: \(debugDescription(for: error))"
        return
      } catch {
        statusMessage = "Failed to join game: \(debugDescription(for: error))"
        return
      }
    }
  }

  private func handleMatchmakingEvent(_ event: MatchmakingEvent) async {
    switch event {
    case .inviteAccepted:
      await refreshGame()
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

  func deleteGame(_ game: GameResponse) async {
    do {
      try await apiClient.deleteGame(id: game.id)
      games.removeAll { $0.id == game.id }
    } catch {
      statusMessage = "Failed to delete game: \(debugDescription(for: error))"
    }
  }

  func deleteCurrentGame() async {
    guard let game = currentGame else { return }
    await deleteGame(game)
    currentGame = nil
    gameRoomModel = nil
    navigationPath = NavigationPath()
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

  func openGameFromNotification(gameID: String) async {
    if let existing = games.first(where: { $0.id == gameID }) {
      selectGame(existing)
      return
    }

    do {
      let game = try await apiClient.fetchGame(id: gameID)
      currentGame = game
      if !games.contains(where: { $0.id == gameID }) {
        games.insert(game, at: 0)
      }
      enterGame()
    } catch {
      Log.log(
        "Failed to open game from notification",
        level: .warning,
        category: .push,
        error: error,
        metadata: ["game_id": gameID]
      )
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

    Log.log(
      "Bundle info",
      level: .debug,
      category: .build,
      metadata: [
        "bundle_id": bundleID,
        "version": shortVersion ?? "nil",
        "build": build ?? "nil"
      ]
    )

    if shortVersion == nil || build == nil {
      Log.log(
        "Missing CFBundleShortVersionString and/or CFBundleVersion",
        level: .warning,
        category: .build,
        metadata: ["operation": "bundle_info_check"]
      )
    }
  }

  private static func makeMatchmakingProvider(apiClient: APIClient) -> MatchmakingProvider {
  #if targetEnvironment(simulator)
    return ServerMatchmakingProvider(apiClient: apiClient)
  #else
    return GameCenterMatchmakingProvider(apiClient: apiClient)
  #endif
  }
}
