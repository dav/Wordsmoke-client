import Foundation

struct SessionResponse: Decodable, Sendable, Equatable {
  let token: String
  let playerID: String
  let accountID: String
  let playerName: String?

  enum CodingKeys: String, CodingKey {
    case token
    case playerID = "player_id"
    case accountID = "account_id"
    case playerName = "player_name"
  }
}

struct CreateSessionRequest: Encodable {
  let accountID: String?
  let session: SessionPayload

  enum CodingKeys: String, CodingKey {
    case accountID = "account_id"
    case session
  }
}

struct SessionPayload: Encodable {
  let gameCenterPlayerID: String
  let displayName: String?
  let nickname: String?
  let publicKeyURL: String?
  let signature: Data?
  let salt: Data?
  let timestamp: UInt64?
  let bundleID: String?

  enum CodingKeys: String, CodingKey {
    case gameCenterPlayerID = "game_center_player_id"
    case displayName
    case nickname
    case publicKeyURL
    case signature
    case salt
    case timestamp
    case bundleID
  }
}

struct GameResponse: Decodable, Sendable, Equatable {
  let id: String
  let status: String
  let joinCode: String
  let gcMatchId: String?
  let goalLength: Int
  let currentRoundID: String?
  let currentRoundNumber: Int?
  let playersCount: Int?
  let participantNames: [String]?
  let rounds: [GameRoundSummary]?
  let participants: [GameParticipant]?
  let invitedPlayers: [GameInvitedPlayer]?
  let endedAt: String?
  let winnerNames: [String]?
  let winningRoundNumber: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case joinCode = "join_code"
    case gcMatchId = "gc_match_id"
    case goalLength = "goal_length"
    case currentRoundID = "current_round_id"
    case currentRoundNumber = "current_round_number"
    case playersCount = "players_count"
    case participantNames = "participant_names"
    case rounds
    case participants
    case invitedPlayers = "invited_players"
    case endedAt = "ended_at"
    case winnerNames = "winner_names"
    case winningRoundNumber = "winning_round_number"
  }
}

struct GamesListResponse: Decodable, Sendable, Equatable {
  let games: [GameResponse]
}

struct GameRoundSummary: Decodable, Sendable, Identifiable, Equatable {
  let id: String
  let number: Int
  let status: String
  let startedAt: String?
  let endedAt: String?
  let submissionsCount: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case number
    case status
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case submissionsCount = "submissions_count"
  }
}

struct GameParticipant: Decodable, Sendable, Identifiable, Equatable {
  let id: String
  let role: String
  let score: Int
  let joinedAt: String?
  let player: GameParticipantPlayer

  enum CodingKeys: String, CodingKey {
    case id
    case role
    case score
    case joinedAt = "joined_at"
    case player
  }
}

struct GameParticipantPlayer: Decodable, Sendable, Equatable {
  let id: String
  let displayName: String
  let nickname: String?
  let gameCenterPlayerID: String
  let virtual: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case nickname
    case gameCenterPlayerID = "game_center_player_id"
    case virtual
  }
}

struct GameInvitedPlayer: Decodable, Sendable, Identifiable, Equatable {
  var id: String { playerID }
  let playerID: String
  let displayName: String
  let nickname: String?
  let inviteStatus: String
  let accepted: Bool

  enum CodingKeys: String, CodingKey {
    case playerID = "player_id"
    case displayName = "display_name"
    case nickname
    case inviteStatus = "invite_status"
    case accepted
  }
}

struct WordValidationResponse: Decodable, Sendable, Equatable {
  let valid: Bool
}

struct ClientPolicyResponse: Decodable, Sendable, Equatable {
  let apiVersion: String?
  let clientVersion: String?
  let supportedApiVersions: [String]?
  let minSupportedClientVersion: String?
  let latestClientVersion: String?
  let deprecationDate: String?
  let sunsetDate: String?
  let deprecated: Bool?
  let forceUpdate: Bool?
  let message: String?
  let updateURL: String?

  enum CodingKeys: String, CodingKey {
    case apiVersion = "api_version"
    case clientVersion = "client_version"
    case supportedApiVersions = "supported_api_versions"
    case minSupportedClientVersion = "min_supported_client_version"
    case latestClientVersion = "latest_client_version"
    case deprecationDate = "deprecation_date"
    case sunsetDate = "sunset_date"
    case deprecated
    case forceUpdate = "force_update"
    case message
    case updateURL = "update_url"
  }
}

struct GoalWordLengthsResponse: Decodable, Sendable, Equatable {
  let lengths: [Int]
}

enum APIError: Error, CustomNSError, LocalizedError {
  case statusCode(Int, String)
  case invalidResponse

  static var errorDomain: String { "Wordsmoke.APIError" }

  var errorCode: Int {
    switch self {
    case .statusCode(let statusCode, _):
      return statusCode
    case .invalidResponse:
      return -1
    }
  }

  var errorDescription: String? {
    switch self {
    case .statusCode(let statusCode, let body):
      let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        return "HTTP \(statusCode)"
      }
      if let payload = APIErrorPayload.decode(from: trimmed) {
        if let detailsMessage = payload.detailsMessage {
          return detailsMessage
        }
        if let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
          return message
        }
      }
      return "HTTP \(statusCode): \(trimmed)"
    case .invalidResponse:
      return "Invalid server response"
    }
  }
}

private struct APIErrorPayload: Decodable {
  let message: String?
  let details: [String: [String]]?

  var detailsMessage: String? {
    guard let details else { return nil }
    let messages = details
      .keys
      .sorted()
      .flatMap { details[$0] ?? [] }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !messages.isEmpty else { return nil }
    return messages.joined(separator: "\n")
  }

  static func decode(from rawBody: String) -> APIErrorPayload? {
    guard let data = rawBody.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(APIErrorPayload.self, from: data)
  }
}
