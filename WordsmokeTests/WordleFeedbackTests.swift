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

@MainActor
final class ReportFlowTests: XCTestCase {
  func testReportablePhrasesIncludesOnlyOtherPlayersWithPhraseText() {
    let model = makeModel()

    model.completedRounds = [
      RoundPayload(
        id: "round-1",
        number: 1,
        status: "closed",
        stage: "reveal",
        submissions: [
          makeSubmission(id: "s-local", playerID: "player-local", playerName: "Local", phrase: "my phrase"),
          makeSubmission(id: "s-1", playerID: "player-a", playerName: "Alex", phrase: "first phrase"),
          makeSubmission(id: "s-2", playerID: "player-b", playerName: "Bailey", phrase: nil)
        ],
        phraseVotesCount: 0,
        viewerFavoriteSubmissionID: nil,
        viewerLeastFavoriteSubmissionID: nil
      ),
      RoundPayload(
        id: "round-2",
        number: 2,
        status: "closed",
        stage: "reveal",
        submissions: [
          makeSubmission(id: "s-3", playerID: "player-b", playerName: "Bailey", phrase: "second phrase")
        ],
        phraseVotesCount: 0,
        viewerFavoriteSubmissionID: nil,
        viewerLeastFavoriteSubmissionID: nil
      )
    ]

    let reportable = model.reportablePhrases()

    XCTAssertEqual(reportable.count, 2)
    XCTAssertEqual(reportable.map(\.id), ["s-3", "s-1"])
    XCTAssertEqual(reportable.map(\.playerID), ["player-b", "player-a"])
  }

  func testProblemReportMessageIncludesContextAndOptionalContact() {
    let model = makeModel()

    let message = model.problemWithGameReportMessage(
      description: "Something went wrong in voting.",
      providedName: "Taylor",
      providedEmail: "taylor@example.com"
    )

    XCTAssertTrue(message.contains("report_type: Problem with game"))
    XCTAssertTrue(message.contains("game_id: game-123"))
    XCTAssertTrue(message.contains("player_id: player-local"))
    XCTAssertTrue(message.contains("provided_name: Taylor"))
    XCTAssertTrue(message.contains("provided_email: taylor@example.com"))
  }

  func testInappropriateReportMessageIncludesSelectedPhraseDetails() {
    let model = makeModel()
    let selected = [
      ReportablePhrase(
        id: "s-9",
        roundNumber: 4,
        playerID: "player-a",
        playerName: "Alex",
        phrase: "bad phrase"
      )
    ]

    let message = model.inappropriateContentReportMessage(selectedPhrases: selected)

    XCTAssertTrue(message.contains("report_type: Inappropriate Content"))
    XCTAssertTrue(message.contains("game_id: game-123"))
    XCTAssertTrue(message.contains("player_id: player-local"))
    XCTAssertTrue(message.contains("round=4"))
    XCTAssertTrue(message.contains("player_id=player-a"))
    XCTAssertTrue(message.contains("phrase=\"bad phrase\""))
  }

  func testWaitingRoomStatusesAreHostFirstAndDeduped() {
    let model = makeModel(
      status: "waiting",
      invitedPlayers: [
        GameInvitedPlayer(
          playerID: "player-a",
          displayName: "Alex",
          nickname: nil,
          inviteStatus: "accepted",
          accepted: true
        ),
        GameInvitedPlayer(
          playerID: "player-b",
          displayName: "Bailey",
          nickname: nil,
          inviteStatus: "pending",
          accepted: false
        )
      ]
    )

    let statuses = model.waitingRoomPlayerStatuses()

    XCTAssertEqual(statuses.count, 3)
    XCTAssertEqual(statuses.map(\.displayName), ["Local", "Alex", "Bailey"])
    XCTAssertEqual(statuses.map(\.statusText), ["Host", "Joined", "Invited"])
    XCTAssertEqual(statuses.filter { $0.playerID == "player-a" }.count, 1)
    XCTAssertTrue(model.hasPendingInvitedPlayers())
  }

  func testHostShouldConfirmEarlyStartWhenPendingInvitesRemain() {
    let model = makeModel(
      status: "waiting",
      invitedPlayers: [
        GameInvitedPlayer(
          playerID: "player-b",
          displayName: "Bailey",
          nickname: nil,
          inviteStatus: "pending",
          accepted: false
        )
      ]
    )

    XCTAssertTrue(model.hasPendingInvitedPlayers())
    XCTAssertTrue(model.shouldConfirmEarlyStart())
  }

  func testHostStatusAppearsAtTopInWaitingRoom() {
    let model = makeModel(
      status: "waiting",
      invitedPlayers: [
        GameInvitedPlayer(
          playerID: "player-a",
          displayName: "Alex",
          nickname: nil,
          inviteStatus: "accepted",
          accepted: true
        )
      ]
    )

    let statuses = model.waitingRoomPlayerStatuses()

    XCTAssertEqual(statuses.first?.displayName, "Local")
    XCTAssertEqual(statuses.first?.statusText, "Host")
  }

  func testOtherSubmissionsUseStableShuffledOrder() {
    let model = makeModel()
    let local = makeSubmission(id: "s-local", playerID: "player-local", playerName: "Local", phrase: "mine")
    let first = makeSubmission(id: "s-a", playerID: "player-a", playerName: "Alex", phrase: "alpha")
    let second = makeSubmission(id: "s-b", playerID: "player-b", playerName: "Bailey", phrase: "beta")
    let third = makeSubmission(id: "s-c", playerID: "player-c", playerName: "Casey", phrase: "gamma")

    let roundForward = RoundPayload(
      id: "round-voting",
      number: 2,
      status: "voting",
      stage: "voting",
      submissions: [local, first, second, third],
      phraseVotesCount: 0,
      viewerFavoriteSubmissionID: nil,
      viewerLeastFavoriteSubmissionID: nil
    )
    let roundReverse = RoundPayload(
      id: "round-voting",
      number: 2,
      status: "voting",
      stage: "voting",
      submissions: [local, third, second, first],
      phraseVotesCount: 0,
      viewerFavoriteSubmissionID: nil,
      viewerLeastFavoriteSubmissionID: nil
    )

    let forwardIDs = model.otherSubmissions(in: roundForward).map(\.id)
    let reverseIDs = model.otherSubmissions(in: roundReverse).map(\.id)

    XCTAssertEqual(forwardIDs, reverseIDs)
    XCTAssertEqual(Set(forwardIDs), Set(["s-a", "s-b", "s-c"]))
  }

  private func makeModel(
    status: String = "active",
    invitedPlayers: [GameInvitedPlayer]? = nil
  ) -> GameRoomModel {
    let game = GameResponse(
      id: "game-123",
      status: status,
      joinCode: "ABCD",
      gcMatchId: nil,
      goalLength: 5,
      creatorId: nil,
      currentRoundID: nil,
      currentRoundNumber: nil,
      playersCount: 2,
      participantNames: nil,
      rounds: nil,
      participants: [
        GameParticipant(
          id: "participant-local",
          role: "host",
          score: 0,
          joinedAt: nil,
          player: GameParticipantPlayer(
            id: "player-local",
            displayName: "Local",
            nickname: nil,
            gameCenterPlayerID: "GC-local",
            virtual: false
          )
        ),
        GameParticipant(
          id: "participant-a",
          role: "player",
          score: 0,
          joinedAt: nil,
          player: GameParticipantPlayer(
            id: "player-a",
            displayName: "Alex",
            nickname: nil,
            gameCenterPlayerID: "GC-a",
            virtual: false
          )
        )
      ],
      invitedPlayers: invitedPlayers,
      endedAt: nil,
      winnerNames: nil,
      winningRoundNumber: nil
    )

    let apiClient = APIClient(baseURL: URL(string: "https://example.com") ?? URL.documentsDirectory)
    return GameRoomModel(game: game, apiClient: apiClient, localPlayerID: "player-local")
  }

  private func makeSubmission(
    id: String,
    playerID: String,
    playerName: String,
    phrase: String?
  ) -> RoundSubmission {
    RoundSubmission(
      id: id,
      guessWord: "smoke",
      phrase: phrase,
      playerID: playerID,
      playerName: playerName,
      playerVirtual: false,
      marks: nil,
      correctGuess: false,
      createdAt: "2026-02-07T00:00:00Z",
      feedback: nil,
      scoreDelta: nil,
      voted: nil
    )
  }
}
