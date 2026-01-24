import XCTest
@testable import Wordsmoke

final class WordleFeedbackTests: XCTestCase {
  func testMarksWithExactMatches() {
    let marks = WordleFeedback.marks(guess: "smoke", goal: "smoke")

    XCTAssertEqual(marks, [.correct, .correct, .correct, .correct, .correct])
  }

  func testMarksWithMixedMatches() {
    let marks = WordleFeedback.marks(guess: "smoke", goal: "smile")

    XCTAssertEqual(marks, [.correct, .correct, .absent, .absent, .correct])
  }
}
