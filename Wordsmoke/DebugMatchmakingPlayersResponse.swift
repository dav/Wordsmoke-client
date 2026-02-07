import Foundation

struct DebugMatchmakingPlayersResponse: Decodable, Sendable, Equatable {
  let players: [DebugMatchmakingPlayer]
}
