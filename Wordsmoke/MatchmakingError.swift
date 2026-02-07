import Foundation

enum MatchmakingError: LocalizedError {
  case missingInvitees
  case invalidInviteSelection
  case missingDebugToken
  case invalidResponse
  case matchCreationFailed

  var errorDescription: String? {
    switch self {
    case .missingInvitees:
      return "Select players to invite."
    case .invalidInviteSelection:
      return "Select the required number of players."
    case .missingDebugToken:
      return "Missing debug matchmaking token."
    case .invalidResponse:
      return "Unexpected response from matchmaking service."
    case .matchCreationFailed:
      return "Unable to create the match."
    }
  }
}
