import Foundation
import GameKit

@MainActor
final class GameCenterMatchmakingProvider: MatchmakingProvider {
  private var apiClient: APIClient
  private var friendsByID: [String: GKPlayer] = [:]

  var source: MatchmakingSource { .gameCenter }

  init(apiClient: APIClient) {
    self.apiClient = apiClient
  }

  func loadInvitees() async throws -> [MatchmakingInvitee] {
    let friends = try await GKLocalPlayer.local.loadFriends()
    friendsByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.teamPlayerID, $0) })

    return friends
      .map { MatchmakingInvitee(id: $0.teamPlayerID, displayName: $0.displayName, subtitle: nil, isVirtual: false) }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  func createGame(
    goalLength: Int,
    playerCount: Int,
    inviteeIDs: [String]
  ) async throws -> GameResponse {
    guard playerCount >= 2 else { throw MatchmakingError.invalidInviteSelection }
    guard inviteeIDs.count == playerCount - 1 else { throw MatchmakingError.invalidInviteSelection }

    let recipients = inviteeIDs.compactMap { friendsByID[$0] }
    if recipients.count != inviteeIDs.count {
      throw MatchmakingError.invalidInviteSelection
    }

    let request = GKMatchRequest()
    request.minPlayers = playerCount
    request.maxPlayers = playerCount
    request.defaultNumberOfPlayers = playerCount
    request.recipients = recipients
    request.inviteMessage = "Join my Wordsmoke game."

    let matchID = try await findMatchID(with: request)
    let game = try await apiClient.createGame(goalLength: goalLength, gcMatchId: matchID)

    let matchData = try JSONSerialization.data(withJSONObject: ["server_game_id": game.id])
    saveMatchData(matchID: matchID, matchData: matchData)

    return game
  }

  func update(apiClient: APIClient) {
    self.apiClient = apiClient
  }

  func startListening(for matchID: String, onEvent: @escaping (MatchmakingEvent) -> Void) {
  }

  func stopListening() {
  }

  private func findMatchID(with request: GKMatchRequest) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      GKTurnBasedMatch.find(for: request) { match, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let match else {
          continuation.resume(throwing: MatchmakingError.matchCreationFailed)
          return
        }
        continuation.resume(returning: match.matchID)
      }
    }
  }

  private func saveMatchData(matchID: String, matchData: Data) {
    GKTurnBasedMatch.load(withID: matchID) { match, error in
      if let error {
        print("[GameCenter] Failed to load match: \(error)")
        return
      }
      guard let match else {
        print("[GameCenter] Missing match for id \(matchID)")
        return
      }
      match.saveCurrentTurn(withMatch: matchData) { saveError in
        if let saveError {
          print("[GameCenter] Failed to save matchData: \(saveError)")
        }
      }
    }
  }
}
