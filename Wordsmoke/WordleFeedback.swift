import Foundation

enum WordleMark: String, Codable, Sendable {
  case correct
  case present
  case absent
}

struct WordleFeedback {
  static func marks(guess: String, goal: String) -> [WordleMark] {
    let guessChars = Array(guess.lowercased())
    let goalChars = Array(goal.lowercased())
    var marks = Array(repeating: WordleMark.absent, count: guessChars.count)
    var remaining: [Character: Int] = [:]

    for index in guessChars.indices {
      if index < goalChars.count, guessChars[index] == goalChars[index] {
        marks[index] = .correct
      } else if index < goalChars.count {
        remaining[goalChars[index], default: 0] += 1
      }
    }

    for index in guessChars.indices {
      guard marks[index] == .absent else { continue }
      let char = guessChars[index]
      if let count = remaining[char], count > 0 {
        marks[index] = .present
        remaining[char] = count - 1
      }
    }

    return marks
  }
}
