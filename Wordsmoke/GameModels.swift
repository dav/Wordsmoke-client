import Foundation

struct RoundResponse: Decodable, Sendable {
  let id: String
  let number: Int
  let status: String
  let stage: String
  let submissions: [RoundSubmission]?
  let anonymousPhrases: [AnonymousPhrase]?
  let submittedPlayerIDs: [String]?
  let players: [RoundPlayer]?
  let ownSubmission: RoundSubmission?
  let phraseVotesCount: Int

  enum CodingKeys: String, CodingKey {
    case id
    case number
    case status
    case submissions
    case stage
    case anonymousPhrases = "anonymous_phrases"
    case submittedPlayerIDs = "submitted_player_ids"
    case players
    case ownSubmission = "own_submission"
    case phraseVotesCount = "phrase_votes_count"
  }
}

struct RoundPlayer: Decodable, Identifiable, Sendable {
  let id: String
  let name: String

  enum CodingKeys: String, CodingKey {
    case id = "player_id"
    case name = "player_name"
  }
}

struct AnonymousPhrase: Decodable, Identifiable, Sendable {
  let id: String
  let phrase: String

  enum CodingKeys: String, CodingKey {
    case id = "submission_id"
    case phrase
  }
}

struct RoundSubmission: Decodable, Identifiable, Sendable {
  let id: String
  let guessWord: String
  let phrase: String
  let playerID: String
  let playerName: String
  let marks: [String]
  let correctGuess: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case guessWord = "guess_word"
    case phrase
    case playerID = "player_id"
    case playerName = "player_name"
    case marks
    case correctGuess = "correct_guess"
  }
}
