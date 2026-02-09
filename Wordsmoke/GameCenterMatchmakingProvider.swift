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

    let matchID = try await findMatchID(with: request)
    let game = try await apiClient.createGame(goalLength: goalLength, playerCount: playerCount, gcMatchId: matchID)

    let matchData = try JSONSerialization.data(withJSONObject: ["server_game_id": game.id])
    do {
      try await saveMatchDataAndNotify(
        matchID: matchID,
        matchData: matchData,
        invitedPlayerIDs: inviteeIDs
      )
    } catch {
      ErrorReporter.log(
        "Failed to finalize turn handoff",
        level: .error,
        category: .gameCenter,
        error: error,
        metadata: [
          "operation": "save_match_data_and_notify",
          "match_id": matchID
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
    invitedPlayerIDs: [String]
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

          let invitedParticipants = Self.participants(for: invitedPlayerIDs, in: match)
          guard !invitedParticipants.isEmpty else {
            ErrorReporter.log(
              "No invited participants resolved for match",
              level: .warning,
              category: .matchmaking,
              metadata: [
                "operation": "resolve_invited_participants",
                "match_id": matchID
              ]
            )
            continuation.resume(returning: ())
            return
          }

          let reminderMessageKey = "It's your turn in Wordsmoke."
          match.message = reminderMessageKey
          let defaultTurnTimeout: TimeInterval = 60 * 60 * 24 * 7

          match.endTurn(
            withNextParticipants: invitedParticipants,
            turnTimeout: defaultTurnTimeout,
            match: matchData
          ) { endTurnError in
            if let endTurnError {
              continuation.resume(throwing: endTurnError)
              return
            }

            match.sendReminder(
              to: invitedParticipants,
              localizableMessageKey: reminderMessageKey,
              arguments: []
            ) { reminderError in
              if let reminderError {
                ErrorReporter.log(
                  "Failed to send turn reminder",
                  level: .warning,
                  category: .gameCenter,
                  error: reminderError,
                  metadata: [
                    "operation": "send_reminder",
                    "match_id": matchID
                  ]
                )
              }
              continuation.resume(returning: ())
            }
          }
        }
      }
    }
  }

  private nonisolated static func participants(
    for invitedPlayerIDs: [String],
    in match: GKTurnBasedMatch
  ) -> [GKTurnBasedParticipant] {
    let participantsByPlayerID = match.participants.reduce(into: [String: GKTurnBasedParticipant]()) {
      rows,
      participant in
      guard let playerID = participant.player?.teamPlayerID else { return }
      rows[playerID] = participant
    }

    return invitedPlayerIDs.compactMap { participantsByPlayerID[$0] }
  }
}
