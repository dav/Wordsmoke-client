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
      return "You must add friends in Game Center app first before they are available below."
    case .debug:
      return "Invite virtual players from the debug server."
    }
  }
}
