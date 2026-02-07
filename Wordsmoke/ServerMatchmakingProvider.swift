import Foundation

@MainActor
final class ServerMatchmakingProvider: MatchmakingProvider {
  private var apiClient: APIClient
  private var actionCableClient: ActionCableClient?
  private var onEvent: ((MatchmakingEvent) -> Void)?

  var source: MatchmakingSource { .debug }

  init(apiClient: APIClient) {
    self.apiClient = apiClient
  }

  func loadInvitees() async throws -> [MatchmakingInvitee] {
    let players = try await apiClient.fetchDebugMatchmakingPlayers()
    return players
      .map {
        MatchmakingInvitee(
          id: $0.id,
          displayName: $0.displayName,
          subtitle: $0.nickname,
          isVirtual: $0.virtual
        )
      }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  func createGame(
    goalLength: Int,
    playerCount: Int,
    inviteeIDs: [String]
  ) async throws -> GameResponse {
    guard let token = apiClient.debugMatchmakingToken, !token.isEmpty else {
      throw MatchmakingError.missingDebugToken
    }
    guard playerCount >= 2, inviteeIDs.count == playerCount - 1 else {
      throw MatchmakingError.invalidInviteSelection
    }

    return try await apiClient.createDebugMatchmakingMatch(
      goalLength: goalLength,
      playerCount: playerCount,
      inviteeIDs: inviteeIDs
    )
  }

  func update(apiClient: APIClient) {
    self.apiClient = apiClient
  }

  func startListening(for matchID: String, onEvent: @escaping (MatchmakingEvent) -> Void) {
    stopListening()
    self.onEvent = onEvent

    guard let token = apiClient.debugMatchmakingToken,
          let url = cableURL(token: token) else {
      return
    }

    let client = ActionCableClient(url: url)
    client.onMessage = { [weak self] message in
      guard let type = message["type"] as? String else { return }
      if type == "invite_accepted",
         let playerID = message["player_id"] as? String {
        self?.onEvent?(.inviteAccepted(playerID: playerID))
      }
    }

    actionCableClient = client
    client.connect()

    let identifier = "{\"channel\":\"MatchmakingChannel\",\"match_id\":\"\(matchID)\"}"
    client.subscribe(identifier: identifier)
  }

  func stopListening() {
    actionCableClient?.disconnect()
    actionCableClient = nil
    onEvent = nil
  }

  private func cableURL(token: String) -> URL? {
    guard var components = URLComponents(url: apiClient.baseURL, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.scheme = (components.scheme == "https") ? "wss" : "ws"
    components.path = "/cable"
    components.queryItems = [URLQueryItem(name: "debug_token", value: token)]
    return components.url
  }
}
