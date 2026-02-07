import Foundation

enum MatchmakingSource {
  case gameCenter
  case debug

  var title: String {
    switch self {
    case .gameCenter:
      return "Game Center Friends"
    case .debug:
      return "Virtual Players"
    }
  }

  var detail: String {
    switch self {
    case .gameCenter:
      return "Invite friends from your Game Center list. Access must be granted in Settings."
    case .debug:
      return "Invite virtual players from the debug server."
    }
  }
}
