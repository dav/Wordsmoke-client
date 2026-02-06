import Foundation

@MainActor
struct APIClient {
  let baseURL: URL
  var accountID: String?
  var urlSession: URLSession = .shared
  var authToken: String?
  let apiVersion: String = "1"
  let logState = LogState()

  enum LogStrategy {
    case always
    case changesOnly
    case silent
  }

  func createSession(
    signature: GameCenterSignature,
    displayName: String?,
    nickname: String?
  ) async throws -> SessionResponse {
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
    applyStandardHeaders(&request, includeContentType: true)

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    request.httpBody = try encoder.encode(requestBody)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)
    return try decode(SessionResponse.self, from: data, response: response)
  }

  func createGame(goalLength: Int, gcMatchId: String? = nil) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "games"))
    request.httpMethod = "POST"
    applyStandardHeaders(&request, includeContentType: true)

    var gameParams: [String: Any] = ["goal_length": goalLength]
    if let gcMatchId {
      gameParams["gc_match_id"] = gcMatchId
    }
    let body: [String: Any] = ["game": gameParams]
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
    applyStandardHeaders(&request, includeContentType: true)

    let body = ["join_code": joinCode]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func joinGameByMatchId(_ gcMatchId: String) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "game_join"))
    request.httpMethod = "POST"
    applyStandardHeaders(&request, includeContentType: true)

    let body = ["gc_match_id": gcMatchId]
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
    applyStandardHeaders(&request)

    logRequest(request, strategy: logStrategy)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data, strategy: logStrategy)
    try validate(response: response, data: data)

    return try decode(GameResponse.self, from: data, response: response)
  }

  func fetchRound(
    gameID: String,
    roundID: String,
    logStrategy: LogStrategy = .always,
    forceRefresh: Bool = false
  ) async throws -> RoundResponse {
    var request = URLRequest(
      url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)")
    )
    request.httpMethod = "GET"
    if forceRefresh {
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    } else {
      request.cachePolicy = .reloadRevalidatingCacheData
    }
    applyStandardHeaders(&request)

    logRequest(request, strategy: logStrategy)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data, strategy: logStrategy)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func submitGuess(
    gameID: String,
    roundID: String,
    guessWord: String,
    phrase: String
  ) async throws -> RoundSubmission {
    var request = URLRequest(
      url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)/submissions")
    )
    request.httpMethod = "POST"
    applyStandardHeaders(&request, includeContentType: true)

    let body = ["submission": ["guess_word": guessWord, "phrase": phrase]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundSubmission.self, from: data, response: response)
  }

  func submitPhraseVote(
    gameID: String,
    roundID: String,
    favoriteID: String,
    leastID: String
  ) async throws -> RoundResponse {
    var request = URLRequest(
      url: baseURL.appending(path: "games/\(gameID)/rounds/\(roundID)/phrase_votes")
    )
    request.httpMethod = "POST"
    applyStandardHeaders(&request, includeContentType: true)

    let body = [
      "phrase_vote": [
        "favorite_submission_id": favoriteID,
        "least_favorite_submission_id": leastID
      ]
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func submitVirtualGuess(gameID: String, playerID: String) async throws -> RoundResponse {
    var request = URLRequest(
      url: baseURL.appending(path: "dev/games/\(gameID)/virtual_players/\(playerID)/guess")
    )
    request.httpMethod = "POST"
    applyStandardHeaders(&request)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func submitVirtualVote(gameID: String, playerID: String) async throws -> RoundResponse {
    var request = URLRequest(
      url: baseURL.appending(path: "dev/games/\(gameID)/virtual_players/\(playerID)/vote")
    )
    request.httpMethod = "POST"
    applyStandardHeaders(&request)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(RoundResponse.self, from: data, response: response)
  }

  func updateGameStatus(id: String, status: String) async throws -> GameResponse {
    var request = URLRequest(url: baseURL.appending(path: "games/\(id)"))
    request.httpMethod = "PATCH"
    applyStandardHeaders(&request, includeContentType: true)

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
    applyStandardHeaders(&request)

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
    applyStandardHeaders(&request, includeContentType: true)

    let body = ["word": word]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    let result = try decode(WordValidationResponse.self, from: data, response: response)
    return result.valid
  }

  func fetchGoalWordLengths() async throws -> [Int] {
    var request = URLRequest(url: baseURL.appending(path: "goal_word_lengths"))
    request.httpMethod = "GET"
    applyStandardHeaders(&request)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    let result = try decode(GoalWordLengthsResponse.self, from: data, response: response)
    return result.lengths
  }

  func fetchClientPolicy() async throws -> ClientPolicyResponse {
    var request = URLRequest(url: baseURL.appending(path: "client_policy"))
    request.httpMethod = "GET"
    applyStandardHeaders(&request)

    logRequest(request)
    let (data, response) = try await urlSession.data(for: request)
    logResponse(response, data: data)
    try validate(response: response, data: data)

    return try decode(ClientPolicyResponse.self, from: data, response: response)
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

  private func applyStandardHeaders(_ request: inout URLRequest, includeContentType: Bool = false) {
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if includeContentType {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    request.setValue(apiVersion, forHTTPHeaderField: "X-API-Version")
    if let clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
      request.setValue(clientVersion, forHTTPHeaderField: "X-Client-Version")
    }
    if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
      request.setValue(build, forHTTPHeaderField: "X-Client-Build")
    }
    if let authToken {
      request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }
  }
}
