import Foundation

struct InviteSheet: Identifiable {
  let id = UUID()
  let joinCode: String
  let minPlayers: Int
  let maxPlayers: Int
}
