import Foundation

struct RoundPayload: Decodable, Sendable {
  let id: String
  let number: Int
  let status: String
  let stage: String
  let submissions: [RoundSubmission]
  let phraseVotesCount: Int

  enum CodingKeys: String, CodingKey {
    case id
    case number
    case status
    case submissions
    case stage
    case phraseVotesCount = "phrase_votes_count"
  }
}

struct RoundResponse: Decodable, Sendable {
  let gameID: String
  let round: RoundPayload

  enum CodingKeys: String, CodingKey {
    case gameID = "game_id"
    case round
  }
}

struct RoundSubmission: Decodable, Identifiable, Sendable {
  let id: String
  let guessWord: String?
  let phrase: String?
  let playerID: String
  let playerName: String
  let marks: [String]?
  let correctGuess: Bool?
  let createdAt: String?
  let feedback: SubmissionFeedback?
  let scoreDelta: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case guessWord = "guess_word"
    case phrase
    case playerID = "player_id"
    case playerName = "player_name"
    case marks
    case correctGuess = "correct_guess"
    case createdAt = "created_at"
    case feedback
    case scoreDelta = "score_delta"
  }
}

struct SubmissionFeedback: Decodable, Sendable {
  let goal: String?
  let guess: String?
  let marks: [String]?
}
