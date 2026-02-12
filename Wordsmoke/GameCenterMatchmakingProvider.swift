import Foundation
@preconcurrency import GameKit

extension GKTurnBasedMatch: @unchecked @retroactive Sendable {}
extension GKTurnBasedParticipant: @unchecked @retroactive Sendable {}

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
    request.inviteMessage = "Join my \(goalLength) letter Wordsmoke game."

    let gameCenterMatchID = try await findMatchID(with: request)
    var game = try await apiClient.createGame(goalLength: goalLength, playerCount: playerCount, gcMatchId: gameCenterMatchID)

    game.invitedPlayers = inviteeIDs.compactMap { id in
      guard let friend = friendsByID[id] else { return nil }
      return GameInvitedPlayer(
        playerID: id,
        displayName: friend.displayName,
        nickname: nil,
        inviteStatus: "pending",
        accepted: false
      )
    }

    let matchData = try JSONSerialization.data(withJSONObject: ["server_game_id": game.id])
    do {
      try await saveMatchDataAndNotify(
        matchID: gameCenterMatchID,
        matchData: matchData,
        invitedPlayerIDs: inviteeIDs,
        game: game
      )
    } catch {
      Log.log(
        "Failed to finalize turn handoff",
        level: .error,
        category: .gameCenter,
        error: error,
        metadata: [
          "operation": "save_match_data_and_notify",
          "match_id": gameCenterMatchID
        ]
      )
    }

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
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
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

  private func saveMatchDataAndNotify(
    matchID: String,
    matchData: Data,
    invitedPlayerIDs: [String],
    game: GameResponse
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      GKTurnBasedMatch.load(withID: matchID) { match, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let match else {
          continuation.resume(throwing: MatchmakingError.matchCreationFailed)
          return
        }

        match.saveCurrentTurn(withMatch: matchData) { saveError in
          if let saveError {
            continuation.resume(throwing: saveError)
            return
          }

          let participantSummary = match.participants.map { p in
            let id = p.player?.teamPlayerID ?? "nil"
            let status = "\(p.status.rawValue)"
            return "\(id)(s=\(status))"
          }.joined(separator: ", ")

          let invitedParticipants = Self.participants(for: invitedPlayerIDs, in: match) // GKTurnBasedParticipant
          guard !invitedParticipants.isEmpty else {
            Log.log(
              "No invited participants resolved for match",
              level: .error,
              category: .matchmaking,
              metadata: [
                "operation": "resolve_invited_participants",
                "match_id": matchID,
                "participant_summary": participantSummary,
                "invited_player_ids": invitedPlayerIDs.joined(separator: ",")
              ]
            )
            continuation.resume(returning: ())
            return
          }

          match.message = "It's your turn in Wordsmoke."
          let defaultTurnTimeout: TimeInterval = 60 * 60 * 24 * 7

          Log.log(
            "Calling endTurn for match",
            level: .info,
            category: .matchmaking,
            metadata: [
              "operation": "end_turn",
              "match_id": matchID,
              "next_participant_count": "\(invitedParticipants.count)",
              "participant_summary": participantSummary,
              "game_id": game.id,
              "join_code": game.joinCode
            ]
          )

          match.endTurn(
            withNextParticipants: invitedParticipants,
            turnTimeout: defaultTurnTimeout,
            match: matchData
          ) { endTurnError in
            if let endTurnError {
              continuation.resume(throwing: endTurnError)
              return
            }

            Log.log(
              "endTurn succeeded",
              level: .info,
              category: .matchmaking,
              metadata: [
                "operation": "end_turn",
                "match_id": matchID,
                "participant_count": "\(invitedParticipants.count)",
                "game_id": game.id,
                "join_code": game.joinCode
              ]
            )

            continuation.resume(returning: ())
          }
        }
      }
    }
  }

  private nonisolated static func participants(
    for invitedPlayerIDs: [String],
    in match: GKTurnBasedMatch
  ) -> [GKTurnBasedParticipant] {
    let localPlayerID = GKLocalPlayer.local.teamPlayerID

    // Try exact match by teamPlayerID first
    let participantsByPlayerID = match.participants.reduce(into: [String: GKTurnBasedParticipant]()) {
      rows, participant in
      guard let playerID = participant.player?.teamPlayerID else { return }
      rows[playerID] = participant
    }
    let matched = invitedPlayerIDs.compactMap { participantsByPlayerID[$0] }
    if !matched.isEmpty { return matched }

    // Fallback: participant.player may be nil for pending invitees.
    // Use all participants except the local player.
    let fallback = match.participants.filter { $0.player?.teamPlayerID != localPlayerID }

    Log.log(
      "Using fallback participant resolution",
      level: .info,
      category: .matchmaking,
      metadata: [
        "total_participants": "\(match.participants.count)",
        "resolved_players": "\(participantsByPlayerID.count)",
        "fallback_count": "\(fallback.count)",
        "invited_ids": invitedPlayerIDs.joined(separator: ",")
      ]
    )

    return fallback
  }
}
