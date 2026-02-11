import GameKit
import XCTest
@testable import Wordsmoke

final class AppModelMatchRecoveryTests: XCTestCase {
  func testRecoverableMatchIDsIncludeInvitedActiveAndUnknownStatus() {
    let summaries = [
      TurnBasedMatchSummary(matchID: "known-active", localParticipantStatus: .active),
      TurnBasedMatchSummary(matchID: "invited", localParticipantStatus: .invited),
      TurnBasedMatchSummary(matchID: "active", localParticipantStatus: .active),
      TurnBasedMatchSummary(matchID: "done", localParticipantStatus: .done),
      TurnBasedMatchSummary(matchID: "declined", localParticipantStatus: .declined),
      TurnBasedMatchSummary(matchID: "matching", localParticipantStatus: .matching),
      TurnBasedMatchSummary(matchID: "unknown-status", localParticipantStatus: nil)
    ]

    let recoverable = AppModel.recoverableMatchIDs(
      from: summaries,
      knownMatchIDs: ["known-active"]
    )

    XCTAssertEqual(recoverable, ["invited", "active", "unknown-status"])
  }
}
