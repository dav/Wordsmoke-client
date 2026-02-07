import Foundation

enum MatchmakingEvent: Sendable, Equatable {
  case inviteAccepted(playerID: String)
}
