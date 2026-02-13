import Foundation

struct RoundPayload: Decodable, Sendable, Identifiable, Equatable {
  let id: String
  let number: Int
  let status: String
  let stage: String
  let submissions: [RoundSubmission]
  let phraseVotesCount: Int
  let viewerFavoriteSubmissionID: String?
  let viewerLeastFavoriteSubmissionID: String?

  enum CodingKeys: String, CodingKey {
    case id
    case number
    case status
    case submissions
    case stage
    case phraseVotesCount = "phrase_votes_count"
    case viewerFavoriteSubmissionID = "viewer_favorite_submission_id"
    case viewerLeastFavoriteSubmissionID = "viewer_least_favorite_submission_id"
  }
}

struct RoundResponse: Decodable, Sendable, Equatable {
  let gameID: String
  let round: RoundPayload

  enum CodingKeys: String, CodingKey {
    case gameID = "game_id"
    case round
  }
}

struct RoundSubmission: Decodable, Identifiable, Sendable, Equatable {
  let id: String
  let guessWord: String?
  let phrase: String?
  let playerID: String
  let playerName: String
  let playerVirtual: Bool?
  let marks: [String]?
  let correctGuess: Bool?
  let createdAt: String?
  let feedback: SubmissionFeedback?
  let scoreDelta: Int?
  let voted: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case guessWord = "guess_word"
    case phrase
    case playerID = "player_id"
    case playerName = "player_name"
    case playerVirtual = "player_virtual"
    case marks
    case correctGuess = "correct_guess"
    case createdAt = "created_at"
    case feedback
    case scoreDelta = "score_delta"
    case voted
  }
}

struct SubmissionFeedback: Decodable, Sendable, Equatable {
  let goal: String?
  let guess: String?
  let marks: [String]?
}
