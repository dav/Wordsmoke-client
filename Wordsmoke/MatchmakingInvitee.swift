import Foundation

struct MatchmakingInvitee: Identifiable, Sendable, Equatable {
  let id: String
  let displayName: String
  let subtitle: String?
  let isVirtual: Bool
}
