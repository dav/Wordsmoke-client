import Foundation

struct RoundResponse: Decodable, Sendable {
  let id: String
  let number: Int
  let status: String
  let submissions: [RoundSubmission]
  let phraseVotesCount: Int

  enum CodingKeys: String, CodingKey {
    case id
    case number
    case status
    case submissions
    case phraseVotesCount = "phrase_votes_count"
  }
}

struct RoundSubmission: Decodable, Identifiable, Sendable {
  let id: String
  let guessWord: String
  let phrase: String
  let playerName: String
  let marks: [String]
  let correctGuess: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case guessWord = "guess_word"
    case phrase
    case playerName = "player_name"
    case marks
    case correctGuess = "correct_guess"
  }
}
