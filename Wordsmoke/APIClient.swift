import Foundation

struct SessionResponse: Decodable, Sendable {
  let token: String
  let playerID: String
  let accountID: String

  enum CodingKeys: String, CodingKey {
    case token
    case playerID = "player_id"
    case accountID = "account_id"
  }
}

struct APIClient {
  let baseURL: URL
  var accountID: String?
  var urlSession: URLSession = .shared
  var authToken: String?

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

  func fetchGame(id: String) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(id)"))
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func fetchRound(gameID: String, roundID: String) async throws -> RoundResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)"))
    request.httpMethod = "GET"
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

  func submitPhraseVote(gameID: String, roundID: String, favoriteID: String, leastID: String) async throws {
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

  private func logRequest(_ request: URLRequest) {
    #if DEBUG
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? "unknown"
    let headers = request.allHTTPHeaderFields ?? [:]
    let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    print("[API] -> \(method) \(urlString)")
    if !headers.isEmpty {
      print("[API] Headers: \(headers)")
    }
    if !body.isEmpty {
      print("[API] Body: \(body)")
    }
    #endif
  }

  private func logResponse(_ response: URLResponse, data: Data) {
    #if DEBUG
    guard let httpResponse = response as? HTTPURLResponse else {
      print("[API] <- invalid response")
      return
    }
    let body = String(data: data, encoding: .utf8) ?? ""
    print("[API] <- \(httpResponse.statusCode) \(httpResponse.url?.absoluteString ?? "")")
    if !body.isEmpty {
      print("[API] Response: \(body)")
    }
    #endif
  }
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
  let playersCount: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case joinCode = "join_code"
    case goalLength = "goal_length"
    case currentRoundID = "current_round_id"
    case playersCount = "players_count"
  }
}

struct GamesListResponse: Decodable, Sendable {
  let games: [GameResponse]
}

struct WordValidationResponse: Decodable, Sendable {
  let valid: Bool
}
