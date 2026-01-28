import Foundation

struct SessionResponse: Decodable, Sendable {
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

@MainActor
struct APIClient {
  let baseURL: URL
  var accountID: String?
  var urlSession: URLSession = .shared
  var authToken: String?
  private let logState = LogState()

  enum LogStrategy {
    case always
    case changesOnly
    case silent
  }

  func createSession(signature: GameCenterSignature, displayName: String?, nickname: String?) async throws -> SessionResponse {
    let requestBody = CreateSessionRequest(
      accountID: accountID,
      session: .init(
        gameCenterPlayerID: signature.teamPlayerID,
        displayName: displayName,
        nickname: nickname,
        publicKeyURL: signature.publicKeyURL.absoluteString,
        signature: signature.signature,
        salt: signature.salt,
        timestamp: signature.timestamp,
        bundleID: signature.bundleID
      )
    )

    var request = URLRequest(url: baseURL.appending(path: "session"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    request.httpBody = try encoder.encode(requestBody)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)
    return try decode(SessionResponse.self, from: data, response: response)
  }

  func createGame(goalLength: Int) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "games"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    let body = ["game": ["goal_length": goalLength]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func joinGame(joinCode: String) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "game_join"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    let body = ["join_code": joinCode]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func fetchGame(id: String, logStrategy: LogStrategy = .always) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(id)"))
    request.httpMethod = "GET"
    request.cachePolicy = .reloadRevalidatingCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    logRequest(request, strategy: logStrategy)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data, strategy: logStrategy)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func fetchRound(gameID: String, roundID: String, logStrategy: LogStrategy = .always) async throws -> RoundResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)"))
    request.httpMethod = "GET"
    request.cachePolicy = .reloadRevalidatingCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    logRequest(request, strategy: logStrategy)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data, strategy: logStrategy)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func submitGuess(gameID: String, roundID: String, guessWord: String, phrase: String) async throws -> RoundSubmission {
    var request = URLRequest(url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)/submissions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    let body = ["submission": ["guess_word": guessWord, "phrase": phrase]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundSubmission.self, from: data, response: response)
  }

  func submitPhraseVote(gameID: String, roundID: String, favoriteID: String, leastID: String) async throws -> RoundResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)/phrase_votes"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    let body = ["phrase_vote": ["favorite_submission_id": favoriteID, "least_favorite_submission_id": leastID]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func submitVirtualGuess(gameID: String, playerID: String) async throws -> RoundResponse {
    var request = URLRequest(url: baseURL.appending(path: "dev/games/\(gameID)/virtual_players/\(playerID)/guess"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func submitVirtualVote(gameID: String, playerID: String) async throws -> RoundResponse {
    var request = URLRequest(url: baseURL.appending(path: "dev/games/\(gameID)/virtual_players/\(playerID)/vote"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func updateGameStatus(id: String, status: String) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(id)"))
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    let body = ["game": ["status": status]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func fetchGames() async throws -> [GameResponse] {
    var request = URLRequest(url: baseURL.appending(path: "games"))
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    let list = try decode(GamesListResponse.self, from: data, response: response)
    return list.games
  }

  func validateWord(_ word: String) async throws -> Bool {
    var request = URLRequest(url: baseURL.appending(path: "word_validations"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    let body = ["word": word]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    let result = try decode(WordValidationResponse.self, from: data, response: response)
    return result.valid
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw APIError.statusCode(httpResponse.statusCode, body)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: URLResponse) throws -> T {
    do {
      let decoder = JSONDecoder()
      return try decoder.decode(T.self, from: data)
    } catch {
      let body = String(data: data, encoding: .utf8) ?? ""
      print("[API] Decode failed. status=\((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(body)")
      throw error
    }
  }

  private func prettyPrintedJSON(from data: Data) -> String? {
    // Pretty print JSON, but compress arrays under key "marks" to one line.
    do {
      // Parse JSON
      let object = try JSONSerialization.jsonObject(with: data, options: [])

      // Helper to build a compact array string from a JSON array value
      func compactArrayString(from value: Any) -> String? {
        guard let array = value as? [Any] else { return nil }
        // Convert elements to JSON fragments
        let elements: [String] = array.compactMap { element in
          if let s = element as? String {
            // Properly JSON-escape the string
            if let jsonData = try? JSONSerialization.data(withJSONObject: [s], options: []),
               let jsonArrayString = String(data: jsonData, encoding: .utf8),
               jsonArrayString.hasPrefix("[") && jsonArrayString.hasSuffix("]") {
              let inner = jsonArrayString.dropFirst().dropLast() // remove [ ]
              return String(inner)
            }
            return "\"\(s)\""
          } else if let n = element as? NSNumber {
            return n.stringValue
          } else if element is NSNull {
            return "null"
          } else if let dict = element as? [String: Any],
                    let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
                    let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
          } else if let arr = element as? [Any],
                    let jsonData = try? JSONSerialization.data(withJSONObject: arr, options: []),
                    let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
          } else {
            return nil
          }
        }
        return "[" + elements.joined(separator: ",") + "]"
      }

      // Collect paths where key == "marks" to aid in replacement
      struct MarksOccurrence { let placeholder: String; let compact: String }
      var occurrences: [MarksOccurrence] = []

      // Recursively traverse and replace values with placeholders to make reliable string substitution
      func traverse(_ any: Any) -> Any {
        if var dict = any as? [String: Any] {
          for (key, value) in dict {
            if key == "marks", let compact = compactArrayString(from: value) {
              // Insert a unique placeholder string unlikely to appear in payload
              let placeholder = "__MARKS_PLACEHOLDER_\(UUID().uuidString)__"
              dict[key] = placeholder
              occurrences.append(MarksOccurrence(placeholder: placeholder, compact: compact))
            } else {
              dict[key] = traverse(value)
            }
          }
          return dict
        } else if let array = any as? [Any] {
          return array.map { traverse($0) }
        } else {
          return any
        }
      }

      let traversed = traverse(object)

      // Encode with prettyPrinted
      let prettyData = try JSONSerialization.data(withJSONObject: traversed, options: [.prettyPrinted])
      var pretty = String(data: prettyData, encoding: .utf8) ?? ""

      // Replace placeholders with compact arrays, keeping surrounding JSON formatting intact
      for occ in occurrences {
        // The placeholder will be encoded as a JSON string, including quotes.
        let quotedPlaceholder = "\"\(occ.placeholder)\""
        pretty = pretty.replacingOccurrences(of: quotedPlaceholder, with: occ.compact)
      }

      return pretty
    } catch {
      return nil
    }
  }

  private func logRequest(_ request: URLRequest, strategy: LogStrategy = .always) {
    #if DEBUG
    guard strategy == .always else { return }
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? "unknown"
    let headers = request.allHTTPHeaderFields ?? [:]
    let body: String = {
      guard let data = request.httpBody else { return "" }
      if let pretty = prettyPrintedJSON(from: data) {
        return pretty
      }
      return String(data: data, encoding: .utf8) ?? ""
    }()

    print("[API] ➡️ \(method) \(urlString)")
    if !headers.isEmpty {
      print("[API] Headers: \(headers)")
    }
    if !body.isEmpty {
      print("[API] ➡️ Body:\n\(body)")
    }
    #endif
  }

  private func logResponse(_ response: URLResponse, data: Data, strategy: LogStrategy = .always) {
    #if DEBUG
    guard let httpResponse = response as? HTTPURLResponse else {
      print("[API] ⬅️😵 invalid response")
      return
    }

    let body: String = {
      if let pretty = prettyPrintedJSON(from: data) {
        return pretty
      }
      return String(data: data, encoding: .utf8) ?? ""
    }()

    if httpResponse.statusCode == 304 {
      return
    }
    if strategy == .silent {
      return
    }
    if strategy == .changesOnly {
      let signature = responseSignature(for: httpResponse, body: data)
      let key = httpResponse.url?.absoluteString ?? ""
      if let signature, logState.signatures[key] == signature {
        return
      }
      if let signature {
        logState.signatures[key] = signature
      }
    }

    let symbol: String
    switch httpResponse.statusCode {
    case 200..<300:
      symbol = "⬅️✅"
    case 400..<500:
      symbol = "⬅️‼️"
    case 500...:
      symbol = "⬅️❌"
    default:
      symbol = "⬅️🤔"
    }
    print("[API] \(symbol) \(httpResponse.statusCode) \(httpResponse.url?.absoluteString ?? "")")

    if !body.isEmpty {
      print("[API] ⬅️ Body:\n\(body)")
    }
    #endif
  }

  private func responseSignature(for response: HTTPURLResponse, body: Data) -> String? {
    if let etag = response.value(forHTTPHeaderField: "ETag") {
      return "etag:\(etag)"
    }
    if let lastModified = response.value(forHTTPHeaderField: "Last-Modified") {
      return "last:\(lastModified)"
    }
    if body.isEmpty {
      return nil
    }
    return "len:\(body.count)-hash:\(body.hashValue)"
  }
}

@MainActor
final class LogState {
  var signatures: [String: String] = [:]
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
      return "HTTP \(statusCode): \(trimmed)"
    case .invalidResponse:
      return "Invalid server response"
    }
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

struct GameResponse: Decodable, Sendable {
  let id: String
  let status: String
  let joinCode: String
  let goalLength: Int
  let currentRoundID: String?
  let currentRoundNumber: Int?
  let playersCount: Int?
  let participantNames: [String]?
  let rounds: [GameRoundSummary]?
  let participants: [GameParticipant]?
  let endedAt: String?
  let winnerNames: [String]?
  let winningRoundNumber: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case joinCode = "join_code"
    case goalLength = "goal_length"
    case currentRoundID = "current_round_id"
    case currentRoundNumber = "current_round_number"
    case playersCount = "players_count"
    case participantNames = "participant_names"
    case rounds
    case participants
    case endedAt = "ended_at"
    case winnerNames = "winner_names"
    case winningRoundNumber = "winning_round_number"
  }
}

struct GamesListResponse: Decodable, Sendable {
  let games: [GameResponse]
}

struct GameRoundSummary: Decodable, Sendable, Identifiable {
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

struct GameParticipant: Decodable, Sendable, Identifiable {
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

struct GameParticipantPlayer: Decodable, Sendable {
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

struct WordValidationResponse: Decodable, Sendable {
  let valid: Bool
}
