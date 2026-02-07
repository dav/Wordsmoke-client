import Foundation

@MainActor
protocol MatchmakingProvider: AnyObject {
  var source: MatchmakingSource { get }

  func loadInvitees() async throws -> [MatchmakingInvitee]
  func createGame(
    goalLength: Int,
    playerCount: Int,
    inviteeIDs: [String]
  ) async throws -> GameResponse
  func update(apiClient: APIClient)

  func startListening(for matchID: String, onEvent: @escaping (MatchmakingEvent) -> Void)
  func stopListening()
}
