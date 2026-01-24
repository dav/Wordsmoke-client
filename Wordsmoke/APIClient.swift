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

    let (data, response) = try await urlSession.data(for: request)
    try validate(response: response, data: data)

    do {
      let decoder = JSONDecoder()
      return try decoder.decode(SessionResponse.self, from: data)
    } catch {
      let body = String(data: data, encoding: .utf8) ?? ""
      print("[API] Decode failed. status=\((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(body)")
      throw error
    }
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
