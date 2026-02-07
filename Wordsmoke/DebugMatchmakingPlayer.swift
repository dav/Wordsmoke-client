import Foundation

struct DebugMatchmakingPlayer: Decodable, Sendable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let nickname: String?
  let virtual: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case nickname
    case virtual
  }
}
