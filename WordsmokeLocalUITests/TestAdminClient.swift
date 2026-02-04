import Foundation

struct TestAdminClient {
  struct Game: Decodable, Sendable {
    let id: String
    let joinCode: String
    let status: String
    let goalLength: Int
    let goalWord: String?
    let currentRoundId: String?
    let currentRoundNumber: Int?
    let createdAt: Date?
  }

  struct LatestGameResponse: Decodable, Sendable {
    let game: Game
  }

  struct VirtualPlayerResponse: Decodable, Sendable {
    struct Player: Decodable, Sendable {
      let id: String
      let displayName: String
      let virtual: Bool
    }

    let gameId: String
    let players: [Player]
  }

  struct StateResponse: Decodable, Sendable {
    struct GameState: Decodable, Sendable {
      let id: String
      let joinCode: String
      let status: String
      let goalLength: Int
      let goalWord: String?
      let playersCount: Int
      let currentRoundId: String?
      let currentRoundNumber: Int?
    }

    struct Participant: Decodable, Sendable {
      let id: String
      let displayName: String
      let role: String
      let score: Int
      let virtual: Bool
    }

    struct RoundState: Decodable, Sendable {
      let id: String
      let number: Int
      let status: String
      let startedAt: Date?
      let endedAt: Date?
    }

    struct Submission: Decodable, Sendable {
      let id: String
      let playerId: String
      let playerName: String
      let guessWord: String?
      let phrase: String?
      let correctGuess: Bool
      let createdAt: Date?
    }

    let game: GameState
    let participants: [Participant]
    let currentRound: RoundState?
    let submissions: [Submission]
  }

  struct WordsResponse: Decodable, Sendable {
    let goalWord: String
    let goalLength: Int
    let randomGuessWord: String
  }

  struct RoundActionResponse: Decodable, Sendable {
    struct Round: Decodable, Sendable {
      let id: String
      let number: Int
      let status: String
      let startedAt: Date?
      let endedAt: Date?
      let submissionsCount: Int
      let phraseVotesCount: Int
    }

    struct Submission: Decodable, Sendable {
      let id: String
      let playerId: String
      let guessWord: String?
      let phrase: String?
    }

    let round: Round
    let submission: Submission?
  }

  let baseURL: URL
  let token: String
  var urlSession: URLSession = .shared

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let basic = ISO8601DateFormatter()
      basic.formatOptions = [.withInternetDateTime]
      if let date = fractional.date(from: value) ?? basic.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
    }
    return decoder
  }()

  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  func fetchLatestGame(createdAfter: Date?) async throws -> Game {
    var components = URLComponents(url: baseURL.appending(path: "test_admin/games/latest"), resolvingAgainstBaseURL: false)
    if let createdAfter {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let value = formatter.string(from: createdAfter)
      components?.queryItems = [URLQueryItem(name: "created_after", value: value)]
    }
    let url = components?.url ?? baseURL.appending(path: "test_admin/games/latest")
    let request = authorizedRequest(url: url)
    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
    return try decoder.decode(LatestGameResponse.self, from: data).game
  }

  func fetchState(gameID: String) async throws -> StateResponse {
    let url = baseURL.appending(path: "test_admin/games/\(gameID)/state")
    let request = authorizedRequest(url: url)
    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
    return try decoder.decode(StateResponse.self, from: data)
  }

  func fetchWords(gameID: String, excludeGoal: Bool) async throws -> WordsResponse {
    var components = URLComponents(url: baseURL.appending(path: "test_admin/games/\(gameID)/words"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "exclude_goal", value: excludeGoal ? "true" : "false")]
    let url = components?.url ?? baseURL.appending(path: "test_admin/games/\(gameID)/words")
    let request = authorizedRequest(url: url)
    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
    return try decoder.decode(WordsResponse.self, from: data)
  }

  func createVirtualPlayers(gameID: String, count: Int) async throws -> VirtualPlayerResponse {
    let url = baseURL.appending(path: "test_admin/games/\(gameID)/virtual_players")
    var request = authorizedRequest(url: url)
    request.httpMethod = "POST"
    let body = ["count": count]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
    return try decoder.decode(VirtualPlayerResponse.self, from: data)
  }

  func createSubmission(
    gameID: String,
    roundID: String,
    playerID: String,
    auto: Bool,
    excludeGoal: Bool
  ) async throws -> RoundActionResponse {
    try await createSubmission(
      gameID: gameID,
      roundID: roundID,
      playerID: playerID,
      guessWord: nil,
      phrase: nil,
      auto: auto,
      excludeGoal: excludeGoal
    )
  }

  func createSubmission(
    gameID: String,
    roundID: String,
    playerID: String,
    guessWord: String?,
    phrase: String?,
    auto: Bool,
    excludeGoal: Bool
  ) async throws -> RoundActionResponse {
    let url = baseURL.appending(path: "test_admin/games/\(gameID)/rounds/\(roundID)/submissions")
    var request = authorizedRequest(url: url)
    request.httpMethod = "POST"
    var body: [String: Any] = [
      "player_id": playerID,
      "auto": auto,
      "exclude_goal": excludeGoal
    ]
    if let guessWord {
      body["guess_word"] = guessWord
    }
    if let phrase {
      body["phrase"] = phrase
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
    return try decoder.decode(RoundActionResponse.self, from: data)
  }

  func createPhraseVote(
    gameID: String,
    roundID: String,
    voterID: String,
    auto: Bool
  ) async throws -> RoundActionResponse {
    let url = baseURL.appending(path: "test_admin/games/\(gameID)/rounds/\(roundID)/phrase_votes")
    var request = authorizedRequest(url: url)
    request.httpMethod = "POST"
    let body: [String: Any] = [
      "voter_id": voterID,
      "auto": auto
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
    return try decoder.decode(RoundActionResponse.self, from: data)
  }

  func deleteGame(gameID: String) async throws {
    let url = baseURL.appending(path: "test_admin/games/\(gameID)")
    var request = authorizedRequest(url: url)
    request.httpMethod = "DELETE"
    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)
  }

  func waitForLatestGame(createdAfter: Date, timeout: TimeInterval) async throws -> Game {
    try await poll(timeout: timeout) {
      try await fetchLatestGame(createdAfter: createdAfter)
    }
  }

  func waitForRound(gameID: String, number: Int, timeout: TimeInterval) async throws -> StateResponse {
    try await poll(timeout: timeout) {
      let state = try await fetchState(gameID: gameID)
      guard state.currentRound?.number == number else {
        throw PollingError.notReady
      }
      return state
    }
  }

  func waitForRoundStatus(gameID: String, status: String, timeout: TimeInterval) async throws -> StateResponse {
    try await poll(timeout: timeout) {
      let state = try await fetchState(gameID: gameID)
      guard state.currentRound?.status == status else {
        throw PollingError.notReady
      }
      return state
    }
  }

  private func authorizedRequest(url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: "X-Test-Admin-Token")
    return request
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? ""
      throw NSError(domain: "TestAdminClient", code: http.statusCode, userInfo: [
        NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(message)"
      ])
    }
  }

  private func poll<T>(timeout: TimeInterval, interval: TimeInterval = 1.0, task: @escaping () async throws -> T) async throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      do {
        return try await task()
      } catch {
        if Date() >= deadline {
          throw error
        }
        try await Task.sleep(for: .seconds(interval))
      }
    }
  }

  enum PollingError: Error {
    case notReady
  }
}
