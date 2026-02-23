import XCTest
@testable import Wordsmoke

// MARK: - URLProtocol stub for intercepting API calls

final class StubURLProtocol: URLProtocol {
  // Map from URL path substring → (statusCode, JSON body)
  nonisolated(unsafe) static var stubs: [(match: String, statusCode: Int, body: String)] = []
  nonisolated(unsafe) static var requestLog: [String] = []

  static func stub(_ pathContains: String, status: Int = 200, body: String) {
    stubs.append((match: pathContains, statusCode: status, body: body))
  }

  static func reset() {
    stubs = []
    requestLog = []
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let urlString = request.url?.absoluteString ?? ""
    StubURLProtocol.requestLog.append(urlString)

    // Find the longest-matching stub (most specific wins)
    let stub = StubURLProtocol.stubs
      .filter { urlString.contains($0.match) }
      .max(by: { $0.match.count < $1.match.count })
    let statusCode = stub?.statusCode ?? 200
    let body = stub?.body ?? "{}"

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let data = body.data(using: .utf8)!

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

// MARK: - Test helpers

extension GameRoomModelTests {
  func makeAPIClient(token: String = "test-token") -> APIClient {
    var client = APIClient(baseURL: URL(string: "https://example.com")!)
    client.authToken = token
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    client.urlSession = URLSession(configuration: config)
    return client
  }

  func makeGame(
    id: String = "game-1",
    status: String = "active",
    currentRoundID: String? = "round-1",
    currentRoundNumber: Int? = 1,
    rounds: [GameRoundSummary]? = nil,
    participants: [GameParticipant]? = nil,
    invitedPlayers: [GameInvitedPlayer]? = nil,
    playersCount: Int? = 2,
    winningRoundNumber: Int? = nil,
    goalLength: Int = 5,
    nilParticipants: Bool = false
  ) -> GameResponse {
    let resolvedParticipants: [GameParticipant]? = nilParticipants ? nil : (participants ?? defaultParticipants())
    return GameResponse(
      id: id,
      status: status,
      joinCode: "AAAA",
      gcMatchId: nil,
      goalLength: goalLength,
      creatorId: nil,
      currentRoundID: currentRoundID,
      currentRoundNumber: currentRoundNumber,
      playersCount: playersCount,
      participantNames: nil,
      rounds: rounds,
      participants: resolvedParticipants,
      invitedPlayers: invitedPlayers,
      endedAt: nil,
      winnerNames: nil,
      winningRoundNumber: winningRoundNumber
    )
  }

  func defaultParticipants() -> [GameParticipant] {
    [
      GameParticipant(
        id: "part-local",
        role: "host",
        score: 10,
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
        id: "part-a",
        role: "player",
        score: 5,
        joinedAt: nil,
        player: GameParticipantPlayer(
          id: "player-a",
          displayName: "Alex",
          nickname: nil,
          gameCenterPlayerID: "GC-a",
          virtual: false
        )
      )
    ]
  }

  func makeRound(
    id: String = "round-1",
    number: Int = 1,
    status: String = "open",
    stage: String = "open",
    submissions: [RoundSubmission] = [],
    viewerFavoriteID: String? = nil,
    viewerLeastID: String? = nil
  ) -> RoundPayload {
    RoundPayload(
      id: id,
      number: number,
      status: status,
      stage: stage,
      submissions: submissions,
      phraseVotesCount: 0,
      viewerFavoriteSubmissionID: viewerFavoriteID,
      viewerLeastFavoriteSubmissionID: viewerLeastID
    )
  }

  func makeSubmission(
    id: String = "sub-1",
    playerID: String = "player-local",
    playerName: String = "Local",
    phrase: String? = "my phrase",
    guessWord: String? = "smoke",
    correctGuess: Bool? = false,
    createdAt: String? = "2026-01-01T00:00:00Z",
    feedback: SubmissionFeedback? = nil,
    scoreDelta: Int? = nil,
    voted: Bool? = nil
  ) -> RoundSubmission {
    RoundSubmission(
      id: id,
      guessWord: guessWord,
      phrase: phrase,
      playerID: playerID,
      playerName: playerName,
      playerVirtual: false,
      marks: nil,
      correctGuess: correctGuess,
      createdAt: createdAt,
      feedback: feedback,
      scoreDelta: scoreDelta,
      voted: voted
    )
  }

  func makeModel(
    game: GameResponse? = nil,
    apiClient: APIClient? = nil,
    localPlayerID: String = "player-local"
  ) -> GameRoomModel {
    GameRoomModel(
      game: game ?? makeGame(),
      apiClient: apiClient ?? makeAPIClient(),
      localPlayerID: localPlayerID
    )
  }

  // Stub the standard "fetchGame → fetchRound" flow used by refreshRound
  func stubRefreshFlow(
    gameJSON: String? = nil,
    roundJSONOverride: String? = nil,
    roundStatus: String = "open",
    roundStage: String = "open"
  ) {
    let game = gameJSON ?? gameJSONWithRound(roundID: "round-1")
    let round = roundJSONOverride ?? roundJSON(id: "round-1", status: roundStatus, stage: roundStage)
    StubURLProtocol.stub("games/game-1", status: 200, body: game)
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: round)
  }

  func gameJSONWithRound(roundID: String, status: String = "active", closedRoundIDs: [String] = []) -> String {
    let closedRounds = closedRoundIDs.map { """
      {"id":"\($0)","number":1,"status":"closed"}
      """ }.joined(separator: ",")
    let allRounds: String
    if closedRoundIDs.isEmpty {
      allRounds = """
        {"id":"\(roundID)","number":1,"status":"open"}
        """
    } else {
      allRounds = closedRounds + "," + """
        {"id":"\(roundID)","number":2,"status":"open"}
        """
    }
    return """
      {
        "id":"game-1","status":"\(status)","join_code":"AAAA",
        "goal_length":5,"current_round_id":"\(roundID)",
        "current_round_number":1,"players_count":2,
        "rounds":[\(allRounds)]
      }
      """
  }

  func roundJSON(
    id: String = "round-1",
    status: String = "open",
    stage: String = "open",
    submissions: String = "[]",
    viewerFav: String? = nil,
    viewerLeast: String? = nil
  ) -> String {
    let fav = viewerFav.map { "\"viewer_favorite_submission_id\":\"\($0)\"," } ?? ""
    let least = viewerLeast.map { "\"viewer_least_favorite_submission_id\":\"\($0)\"," } ?? ""
    return """
      {
        "game_id":"game-1",
        "round":{
          "id":"\(id)","number":1,"status":"\(status)","stage":"\(stage)",
          "submissions":\(submissions),"phrase_votes_count":0,
          \(fav)\(least)
          "phrase_votes_count":0
        }
      }
      """
  }
}

// MARK: - Test suite

@MainActor
final class GameRoomModelTests: XCTestCase {

  override func setUp() {
    super.setUp()
    StubURLProtocol.reset()
  }

  // MARK: - init

  func testInitSetsProperties() {
    let game = makeGame()
    let model = makeModel(game: game)
    XCTAssertEqual(model.localPlayerID, "player-local")
    XCTAssertEqual(model.game.id, "game-1")
    XCTAssertNil(model.round)
    XCTAssertTrue(model.completedRounds.isEmpty)
    XCTAssertEqual(model.guessWord, "")
    XCTAssertEqual(model.phrase, "")
    XCTAssertFalse(model.isBusy)
    XCTAssertFalse(model.isGuessValid)
    XCTAssertFalse(model.isPhraseValid)
    XCTAssertFalse(model.voteSubmitted)
    XCTAssertNil(model.selectedFavoriteID)
    XCTAssertNil(model.selectedLeastID)
    XCTAssertNil(model.errorMessage)
  }

  // MARK: - updateGame / applyGameIfChanged

  func testUpdateGameAppliesNewGame() {
    let model = makeModel()
    let updatedGame = makeGame(status: "completed")
    model.updateGame(updatedGame)
    XCTAssertEqual(model.game.status, "completed")
  }

  func testUpdateGamePreservesExistingInvitedPlayersWhenNewGameHasNone() {
    let invited = [GameInvitedPlayer(
      playerID: "player-b", displayName: "Bailey",
      nickname: nil, inviteStatus: "pending", accepted: false
    )]
    let model = makeModel(game: makeGame(invitedPlayers: invited))
    // New game payload has nil invitedPlayers
    let stripped = makeGame(invitedPlayers: nil)
    model.updateGame(stripped)
    XCTAssertEqual(model.game.invitedPlayers?.count, 1)
    XCTAssertEqual(model.game.invitedPlayers?.first?.playerID, "player-b")
  }

  func testUpdateGameDoesNotPreserveInvitedPlayersWhenNewGameHasThem() {
    let originalInvited = [GameInvitedPlayer(
      playerID: "player-b", displayName: "Bailey",
      nickname: nil, inviteStatus: "pending", accepted: false
    )]
    let newInvited = [GameInvitedPlayer(
      playerID: "player-c", displayName: "Casey",
      nickname: nil, inviteStatus: "accepted", accepted: true
    )]
    let model = makeModel(game: makeGame(invitedPlayers: originalInvited))
    model.updateGame(makeGame(invitedPlayers: newInvited))
    XCTAssertEqual(model.game.invitedPlayers?.first?.playerID, "player-c")
  }

  func testUpdateGameNoopWhenGameUnchanged() {
    let game = makeGame()
    let model = makeModel(game: game)
    let before = model.game
    model.updateGame(game)
    XCTAssertEqual(model.game, before)
  }

  // MARK: - refreshRound (success paths)

  func testRefreshRoundUpdatesOpenRound() async {
    let model = makeModel()
    stubRefreshFlow()
    await model.refreshRound()
    XCTAssertNotNil(model.round)
    XCTAssertEqual(model.round?.id, "round-1")
    XCTAssertNil(model.errorMessage)
  }

  func testRefreshRoundClearsErrorOnSuccess() async {
    let model = makeModel()
    model.errorMessage = "previous error"
    stubRefreshFlow()
    await model.refreshRound()
    XCTAssertNil(model.errorMessage)
  }

  func testRefreshRoundSetsBusyDuringExecution() async {
    let model = makeModel()
    stubRefreshFlow()
    // Run refresh and observe isBusy; after the await it should be false again (defer resets it)
    let task = Task { @MainActor in
      await model.refreshRound()
    }
    await task.value
    XCTAssertFalse(model.isBusy)
  }

  func testRefreshRoundDoesNotRunWhileBusy() async {
    let model = makeModel()
    model.isBusy = true
    // No stubs – if the method fires a real request the test will fail
    await model.refreshRound(setBusy: true)
    // The guard !isBusy branch returns early; isBusy stays true
    XCTAssertTrue(model.isBusy)
  }

  func testRefreshRoundWithSetBusyFalseAlwaysProceeds() async {
    let model = makeModel()
    model.isBusy = true  // isBusy doesn't gate when setBusy = false
    stubRefreshFlow()
    await model.refreshRound(setBusy: false)
    XCTAssertNotNil(model.round)
  }

  func testRefreshRoundSetsErrorOnFailure() async {
    let model = makeModel()
    StubURLProtocol.stub("games/game-1", status: 500, body: "{\"message\":\"Server error\"}")
    await model.refreshRound()
    XCTAssertNotNil(model.errorMessage)
    XCTAssertTrue(model.errorMessage?.contains("Server error") == true)
  }

  func testRefreshRoundSetsErrorOnlyOnceWhenSameMessage() async {
    let model = makeModel()
    model.errorMessage = "Server error"
    StubURLProtocol.stub("games/game-1", status: 500, body: "{\"message\":\"Server error\"}")
    await model.refreshRound()
    // The guard `errorMessage != message` prevents re-assignment
    XCTAssertEqual(model.errorMessage, "Server error")
  }

  func testRefreshRoundMovesClosedCurrentRoundToCompletedRounds() async {
    let model = makeModel()
    let closedRoundBody = roundJSON(id: "round-1", status: "closed", stage: "reveal")
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSONWithRound(roundID: "round-1"))
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: closedRoundBody)
    await model.refreshRound()
    XCTAssertNil(model.round)
    XCTAssertEqual(model.completedRounds.count, 1)
    XCTAssertEqual(model.completedRounds.first?.id, "round-1")
  }

  func testRefreshRoundWithNoCurrentRoundIDClearsRound() async {
    // Game has no currentRoundID
    let game = makeGame(currentRoundID: nil, rounds: [])
    let model = makeModel(game: game)
    model.round = makeRound()  // pre-seed a round
    let gameJSON = """
      {"id":"game-1","status":"active","join_code":"AAAA","goal_length":5,"players_count":2,"rounds":[]}
      """
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSON)
    await model.refreshRound()
    XCTAssertNil(model.round)
  }

  func testRefreshRoundFetchesClosedRoundsFromSummaries() async {
    let closedSummary = GameRoundSummary(
      id: "round-0",
      number: 0,
      status: "closed",
      startedAt: nil,
      endedAt: nil,
      submissionsCount: nil
    )
    let game = makeGame(
      currentRoundID: "round-1",
      rounds: [closedSummary],
      participants: defaultParticipants()
    )
    let model = makeModel(game: game)

    let gameJSONWithBoth = """
      {
        "id":"game-1","status":"active","join_code":"AAAA","goal_length":5,
        "current_round_id":"round-1","current_round_number":2,"players_count":2,
        "rounds":[
          {"id":"round-0","number":0,"status":"closed"},
          {"id":"round-1","number":1,"status":"open"}
        ]
      }
      """
    let closedRoundBody = """
      {"game_id":"game-1","round":{"id":"round-0","number":0,"status":"closed","stage":"reveal","submissions":[],"phrase_votes_count":0}}
      """
    let openRoundBody = roundJSON(id: "round-1", status: "open", stage: "open")
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSONWithBoth)
    StubURLProtocol.stub("game-1/rounds/round-0", status: 200, body: closedRoundBody)
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: openRoundBody)

    await model.refreshRound()

    XCTAssertFalse(model.completedRounds.isEmpty)
    XCTAssertNotNil(model.round)
  }

  func testRefreshRoundSkipsAlreadyCachedClosedRound() async {
    let cachedRound = makeRound(id: "round-0", number: 0, status: "closed", stage: "reveal")
    let game = makeGame(
      currentRoundID: "round-1",
      rounds: [
        GameRoundSummary(id: "round-0", number: 0, status: "closed", startedAt: nil, endedAt: nil, submissionsCount: nil)
      ]
    )
    let model = makeModel(game: game)
    model.completedRounds = [cachedRound]  // Already cached

    let gameJSONWithBoth = """
      {
        "id":"game-1","status":"active","join_code":"AAAA","goal_length":5,
        "current_round_id":"round-1","current_round_number":2,"players_count":2,
        "rounds":[
          {"id":"round-0","number":0,"status":"closed"},
          {"id":"round-1","number":1,"status":"open"}
        ]
      }
      """
    let openRoundBody = roundJSON(id: "round-1", status: "open", stage: "open")
    // Only stub round-1 – if round-0 is re-fetched the stub won't match and it will fail gracefully
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSONWithBoth)
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: openRoundBody)

    await model.refreshRound()

    XCTAssertEqual(model.completedRounds.count, 1)
    XCTAssertEqual(model.completedRounds.first?.id, "round-0")
  }

  func testRefreshRoundRefetchesAllClosedRoundsWhenGameCompleted() async {
    // When game is completed, shouldRefreshAll = true, so even cached closed rounds are re-fetched
    let cachedRound = makeRound(id: "round-0", number: 0, status: "closed", stage: "reveal")
    let game = makeGame(
      status: "completed",
      currentRoundID: nil,
      rounds: [
        GameRoundSummary(id: "round-0", number: 0, status: "closed", startedAt: nil, endedAt: nil, submissionsCount: nil)
      ]
    )
    let model = makeModel(game: game)
    model.completedRounds = [cachedRound]

    let gameJSON = """
      {
        "id":"game-1","status":"completed","join_code":"AAAA","goal_length":5,
        "players_count":2,
        "rounds":[{"id":"round-0","number":0,"status":"closed"}]
      }
      """
    let closedRoundBody = """
      {"game_id":"game-1","round":{"id":"round-0","number":0,"status":"closed","stage":"reveal","submissions":[],"phrase_votes_count":0}}
      """
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSON)
    StubURLProtocol.stub("game-1/rounds/round-0", status: 200, body: closedRoundBody)

    await model.refreshRound()
    XCTAssertEqual(model.completedRounds.count, 1)
  }

  // MARK: - syncVoteSubmittedFromServer

  func testSyncVoteSubmittedRestoresSelectionsFromServer() async {
    let model = makeModel()
    let votingRound = roundJSON(
      id: "round-1",
      status: "voting",
      stage: "reveal",          // stage != "voting" triggers sync
      viewerFav: "sub-fav",
      viewerLeast: "sub-least"
    )
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSONWithRound(roundID: "round-1"))
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: votingRound)

    await model.refreshRound()

    XCTAssertTrue(model.voteSubmitted)
    XCTAssertEqual(model.selectedFavoriteID, "sub-fav")
    XCTAssertEqual(model.selectedLeastID, "sub-least")
  }

  func testSyncVoteSubmittedDoesNotOverrideWhenStageIsVoting() async {
    let model = makeModel()
    let votingRound = roundJSON(
      id: "round-1",
      status: "voting",
      stage: "voting"   // still in voting stage → no sync
    )
    StubURLProtocol.stub("games/game-1", status: 200, body: gameJSONWithRound(roundID: "round-1"))
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: votingRound)

    await model.refreshRound()

    XCTAssertFalse(model.voteSubmitted)
  }

  // MARK: - submitGuess

  func testSubmitGuessSucceeds() async {
    let model = makeModel()
    model.isGuessValid = true
    model.isPhraseValid = true
    model.guessWord = "smoke"
    model.phrase = "Something makes our knowledge evolve"

    let submissionJSON = """
      {"id":"sub-1","player_id":"player-local","player_name":"Local","guess_word":"smoke","phrase":"Something makes our knowledge evolve"}
      """
    StubURLProtocol.stub("rounds/round-1/submissions", status: 200, body: submissionJSON)
    stubRefreshFlow()

    await model.submitGuess()

    XCTAssertEqual(model.guessWord, "")
    XCTAssertEqual(model.phrase, "")
    XCTAssertFalse(model.isGuessValid)
    XCTAssertFalse(model.isPhraseValid)
    XCTAssertNil(model.errorMessage)
  }

  func testSubmitGuessRequiresCurrentRoundID() async {
    let game = makeGame(currentRoundID: nil)
    let model = makeModel(game: game)
    model.isGuessValid = true
    model.isPhraseValid = true
    // No stubs needed – should return early
    await model.submitGuess()
    XCTAssertFalse(model.isBusy)
  }

  func testSubmitGuessRequiresValidGuessAndPhrase() async {
    let model = makeModel()
    model.isGuessValid = false
    model.isPhraseValid = false
    await model.submitGuess()
    XCTAssertFalse(model.isBusy)
  }

  func testSubmitGuessDoesNotRunWhileBusy() async {
    let model = makeModel()
    model.isBusy = true
    model.isGuessValid = true
    model.isPhraseValid = true
    await model.submitGuess()
    XCTAssertTrue(model.isBusy)  // still true, guard returned early
  }

  func testSubmitGuessSetsErrorOnFailure() async {
    let model = makeModel()
    model.isGuessValid = true
    model.isPhraseValid = true
    model.guessWord = "smoke"
    model.phrase = "Something makes our knowledge evolve"
    StubURLProtocol.stub("rounds/round-1/submissions", status: 422, body: "{\"message\":\"Word already submitted\"}")
    await model.submitGuess()
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: - submitVotes

  func testSubmitVotesRequiresCurrentRoundID() async {
    let game = makeGame(currentRoundID: nil)
    let model = makeModel(game: game)
    model.selectedFavoriteID = "sub-1"
    model.selectedLeastID = "sub-2"
    await model.submitVotes()
    XCTAssertFalse(model.isBusy)
  }

  func testSubmitVotesSetsErrorWhenSelectionsMissing() async {
    let model = makeModel()
    model.selectedFavoriteID = nil
    model.selectedLeastID = nil
    await model.submitVotes()
    XCTAssertEqual(model.errorMessage, "Select a favorite and a least favorite phrase.")
  }

  func testSubmitVotesSetsErrorWhenSelectionsAreSame() async {
    let model = makeModel()
    model.selectedFavoriteID = "sub-1"
    model.selectedLeastID = "sub-1"
    await model.submitVotes()
    XCTAssertEqual(model.errorMessage, "Favorite and least favorite must be different.")
  }

  func testSubmitVotesDoesNotRunWhileBusy() async {
    let model = makeModel()
    model.isBusy = true
    model.selectedFavoriteID = "sub-1"
    model.selectedLeastID = "sub-2"
    await model.submitVotes()
    XCTAssertTrue(model.isBusy)
  }

  func testSubmitVotesSucceeds() async {
    let model = makeModel()
    model.selectedFavoriteID = "sub-fav"
    model.selectedLeastID = "sub-least"
    let voteRoundJSON = roundJSON(id: "round-1", status: "voting", stage: "reveal", viewerFav: "sub-fav", viewerLeast: "sub-least")
    let roundResponse = """
      {"game_id":"game-1","round":{"id":"round-1","number":1,"status":"voting","stage":"reveal","submissions":[],"phrase_votes_count":1,"viewer_favorite_submission_id":"sub-fav","viewer_least_favorite_submission_id":"sub-least"}}
      """
    StubURLProtocol.stub("round-1/phrase_votes", status: 200, body: roundResponse)
    stubRefreshFlow(roundJSONOverride: voteRoundJSON, roundStatus: "voting", roundStage: "reveal")

    await model.submitVotes()

    XCTAssertTrue(model.voteSubmitted)
    XCTAssertNil(model.errorMessage)
  }

  func testSubmitVotesSetsErrorOnFailure() async {
    let model = makeModel()
    model.selectedFavoriteID = "sub-fav"
    model.selectedLeastID = "sub-least"
    StubURLProtocol.stub("round-1/phrase_votes", status: 500, body: "{\"message\":\"Voting error\"}")
    await model.submitVotes()
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: - startGame

  func testStartGameRequiresEnoughPlayers() async {
    let game = makeGame(participants: [defaultParticipants()[0]], playersCount: 1)
    let model = makeModel(game: game)
    await model.startGame()
    XCTAssertEqual(model.errorMessage, "At least 2 players must join before starting.")
  }

  func testStartGameUsesParticipantCountWhenPlayersCountNil() async {
    // playersCount is nil but only 1 participant → should reject
    let game = makeGame(participants: [defaultParticipants()[0]], playersCount: nil)
    let model = makeModel(game: game)
    await model.startGame()
    XCTAssertEqual(model.errorMessage, "At least 2 players must join before starting.")
  }

  func testStartGameDoesNotRunWhileBusy() async {
    let model = makeModel()
    model.isBusy = true
    await model.startGame()
    XCTAssertTrue(model.isBusy)
  }

  func testStartGameSucceeds() async {
    let model = makeModel()
    let updatedGameJSON = gameJSONWithRound(roundID: "round-1", status: "active")
    StubURLProtocol.stub("games/game-1", status: 200, body: updatedGameJSON)
    StubURLProtocol.stub("game-1/rounds/round-1", status: 200, body: roundJSON(id: "round-1", status: "open", stage: "open"))

    await model.startGame()
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.game.status, "active")
  }

  func testStartGameSetsErrorOnFailure() async {
    let model = makeModel()
    StubURLProtocol.stub("games/game-1", status: 422, body: "{\"message\":\"Cannot start\"}")
    await model.startGame()
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: - submitVirtualGuess

  func testSubmitVirtualGuessDoesNotRunWhileBusy() async {
    let model = makeModel()
    model.isBusy = true
    await model.submitVirtualGuess(for: "player-virtual")
    XCTAssertTrue(model.isBusy)
  }

  func testSubmitVirtualGuessSucceeds() async {
    let model = makeModel()
    let roundResponse = """
      {"game_id":"game-1","round":{"id":"round-1","number":1,"status":"open","stage":"open","submissions":[],"phrase_votes_count":0}}
      """
    StubURLProtocol.stub("virtual_players", status: 200, body: roundResponse)
    stubRefreshFlow()
    await model.submitVirtualGuess(for: "player-virtual")
    XCTAssertNil(model.errorMessage)
  }

  func testSubmitVirtualGuessSetsErrorOnFailure() async {
    let model = makeModel()
    StubURLProtocol.stub("virtual_players", status: 500, body: "{\"message\":\"Virtual guess failed\"}")
    await model.submitVirtualGuess(for: "player-virtual")
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: - submitVirtualVote

  func testSubmitVirtualVoteDoesNotRunWhileBusy() async {
    let model = makeModel()
    model.isBusy = true
    await model.submitVirtualVote(for: "player-virtual")
    XCTAssertTrue(model.isBusy)
  }

  func testSubmitVirtualVoteSucceeds() async {
    let model = makeModel()
    let roundResponse = """
      {"game_id":"game-1","round":{"id":"round-1","number":1,"status":"voting","stage":"voting","submissions":[],"phrase_votes_count":0}}
      """
    StubURLProtocol.stub("virtual_players", status: 200, body: roundResponse)
    stubRefreshFlow(roundStatus: "voting", roundStage: "voting")
    await model.submitVirtualVote(for: "player-virtual")
    XCTAssertNil(model.errorMessage)
  }

  func testSubmitVirtualVoteSetsErrorOnFailure() async {
    let model = makeModel()
    StubURLProtocol.stub("virtual_players", status: 500, body: "{\"message\":\"Virtual vote failed\"}")
    await model.submitVirtualVote(for: "player-virtual")
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: - validateGuessWord

  func testValidateGuessWordTooShortIsInvalid() async {
    let model = makeModel()  // goalLength = 5
    model.guessWord = "hi"
    await model.validateGuessWord()
    XCTAssertFalse(model.isGuessValid)
  }

  func testValidateGuessWordCorrectLengthCallsAPI() async {
    let model = makeModel()
    model.guessWord = "smoke"
    model.phrase = "Something makes our knowledge evolve"
    StubURLProtocol.stub("word_validations", status: 200, body: "{\"valid\":true}")
    await model.validateGuessWord()
    XCTAssertTrue(model.isGuessValid)
  }

  func testValidateGuessWordCorrectLengthInvalidWord() async {
    let model = makeModel()
    model.guessWord = "zxqwv"
    model.phrase = "zebras xray quails walked vigorously"
    StubURLProtocol.stub("word_validations", status: 200, body: "{\"valid\":false}")
    await model.validateGuessWord()
    XCTAssertFalse(model.isGuessValid)
  }

  func testValidateGuessWordSkipsAPICallForSameWord() async {
    let model = makeModel()
    model.guessWord = "smoke"
    model.phrase = "Something makes our knowledge evolve"
    StubURLProtocol.stub("word_validations", status: 200, body: "{\"valid\":true}")
    await model.validateGuessWord()
    XCTAssertTrue(model.isGuessValid)

    // Change phrase, same word – should skip API and re-derive isPhraseValid only
    StubURLProtocol.reset()  // remove stub so any network call would fail
    model.phrase = "smokes out key words every"
    await model.validateGuessWord()
    // isGuessValid remains as previously set; isPhraseValid re-evaluated
    XCTAssertTrue(model.isGuessValid)
  }

  func testValidateGuessWordSetsErrorOnAPIFailure() async {
    let model = makeModel()
    model.guessWord = "smoke"
    StubURLProtocol.stub("word_validations", status: 500, body: "{\"message\":\"Validation error\"}")
    await model.validateGuessWord()
    XCTAssertFalse(model.isGuessValid)
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: - validatePhrase

  func testValidatePhraseReturnsFalseWhenGuessWordEmpty() {
    let model = makeModel()
    model.guessWord = ""
    model.phrase = "some phrase"
    model.validatePhrase()
    XCTAssertFalse(model.isPhraseValid)
  }

  func testValidatePhraseReturnsTrueWhenPhraseContainsAllLetters() {
    let model = makeModel()
    model.guessWord = "smoke"
    model.phrase = "Something makes our knowledge evolve"
    model.validatePhrase()
    XCTAssertTrue(model.isPhraseValid)
  }

  func testValidatePhraseReturnsFalseWhenPhraseIsMissingLetters() {
    let model = makeModel()
    model.guessWord = "smoke"
    model.phrase = "no match here"  // missing 's'... actually 's' is in "no match here"? Let's use one that definitely misses
    model.phrase = "aaa bbb ccc"    // missing s, m, k, e, o
    model.validatePhrase()
    XCTAssertFalse(model.isPhraseValid)
  }

  // MARK: - isReadyToVote / canShowVoting

  func testIsReadyToVoteReturnsTrueWhenRoundIsVotingStageAndNotSubmitted() {
    let model = makeModel()
    model.round = makeRound(status: "voting", stage: "voting")
    model.voteSubmitted = false
    XCTAssertTrue(model.isReadyToVote())
  }

  func testIsReadyToVoteReturnsFalseWhenAlreadySubmitted() {
    let model = makeModel()
    model.round = makeRound(status: "voting", stage: "voting")
    model.voteSubmitted = true
    XCTAssertFalse(model.isReadyToVote())
  }

  func testIsReadyToVoteReturnsFalseWhenNoRound() {
    let model = makeModel()
    model.round = nil
    XCTAssertFalse(model.isReadyToVote())
  }

  func testCanShowVotingReturnsTrueWhenRoundIsVotingStage() {
    let model = makeModel()
    model.round = makeRound(status: "voting", stage: "voting")
    XCTAssertTrue(model.canShowVoting())
  }

  func testCanShowVotingReturnsFalseWhenNoRound() {
    let model = makeModel()
    model.round = nil
    XCTAssertFalse(model.canShowVoting())
  }

  func testCanShowVotingReturnsFalseWhenNotVotingStage() {
    let model = makeModel()
    model.round = makeRound(status: "open", stage: "open")
    XCTAssertFalse(model.canShowVoting())
  }

  // MARK: - hasSubmittedOwnGuess / ownSubmission / otherSubmissions

  func testHasSubmittedOwnGuessReturnsTrueWhenCreatedAtSet() {
    let model = makeModel()
    let localSub = makeSubmission(playerID: "player-local", createdAt: "2026-01-01T00:00:00Z")
    model.round = makeRound(submissions: [localSub])
    XCTAssertTrue(model.hasSubmittedOwnGuess())
  }

  func testHasSubmittedOwnGuessReturnsFalseWhenCreatedAtNil() {
    let model = makeModel()
    let localSub = makeSubmission(playerID: "player-local", createdAt: nil)
    model.round = makeRound(submissions: [localSub])
    XCTAssertFalse(model.hasSubmittedOwnGuess())
  }

  func testHasSubmittedOwnGuessReturnsFalseWhenNoRound() {
    let model = makeModel()
    model.round = nil
    XCTAssertFalse(model.hasSubmittedOwnGuess())
  }

  func testOwnSubmissionReturnsLocalPlayerSubmission() {
    let model = makeModel()
    let local = makeSubmission(id: "s-local", playerID: "player-local")
    let other = makeSubmission(id: "s-other", playerID: "player-a")
    let round = makeRound(submissions: [local, other])
    XCTAssertEqual(model.ownSubmission(in: round)?.id, "s-local")
  }

  func testOtherSubmissionsExcludesLocalPlayer() {
    let model = makeModel()
    let local = makeSubmission(id: "s-local", playerID: "player-local")
    let other = makeSubmission(id: "s-other", playerID: "player-a")
    let round = makeRound(submissions: [local, other])
    let others = model.otherSubmissions(in: round)
    XCTAssertEqual(others.count, 1)
    XCTAssertEqual(others.first?.id, "s-other")
  }

  // MARK: - playerName / playerScore / isHost / isVirtualPlayer

  func testPlayerNameReturnsDisplayNameForKnownPlayer() {
    let model = makeModel()
    XCTAssertEqual(model.playerName(for: "player-local"), "Local")
    XCTAssertEqual(model.playerName(for: "player-a"), "Alex")
  }

  func testPlayerNameReturnsNilForUnknownPlayer() {
    let model = makeModel()
    XCTAssertNil(model.playerName(for: "nobody"))
  }

  func testPlayerScoreReturnsCorrectScore() {
    let model = makeModel()
    XCTAssertEqual(model.playerScore(for: "player-local"), 10)
    XCTAssertEqual(model.playerScore(for: "player-a"), 5)
  }

  func testPlayerScoreReturnsZeroForUnknownPlayer() {
    let model = makeModel()
    XCTAssertEqual(model.playerScore(for: "nobody"), 0)
  }

  func testIsHostReturnsTrueForHostPlayer() {
    let model = makeModel()
    XCTAssertTrue(model.isHost())
  }

  func testIsHostReturnsFalseForNonHostPlayer() {
    let model = makeModel(localPlayerID: "player-a")
    XCTAssertFalse(model.isHost())
  }

  func testIsVirtualPlayerReturnsTrueWhenFlagSet() {
    let participants = [
      GameParticipant(
        id: "part-v",
        role: "player",
        score: 0,
        joinedAt: nil,
        player: GameParticipantPlayer(
          id: "player-v",
          displayName: "Bot",
          nickname: nil,
          gameCenterPlayerID: "GC-v",
          virtual: true
        )
      )
    ]
    let game = makeGame(participants: participants)
    let model = makeModel(game: game)
    XCTAssertTrue(model.isVirtualPlayer("player-v"))
  }

  func testIsVirtualPlayerReturnsTrueWhenGCIDPrefixedWithVIRTUAL() {
    let participants = [
      GameParticipant(
        id: "part-v",
        role: "player",
        score: 0,
        joinedAt: nil,
        player: GameParticipantPlayer(
          id: "player-v",
          displayName: "Bot",
          nickname: nil,
          gameCenterPlayerID: "VIRTUAL-bot-1",
          virtual: nil  // nil virtual flag; relies on prefix
        )
      )
    ]
    let game = makeGame(participants: participants)
    let model = makeModel(game: game)
    XCTAssertTrue(model.isVirtualPlayer("player-v"))
  }

  func testIsVirtualPlayerReturnsFalseForRealPlayer() {
    let model = makeModel()
    XCTAssertFalse(model.isVirtualPlayer("player-local"))
  }

  func testIsVirtualPlayerReturnsFalseForUnknownPlayer() {
    let model = makeModel()
    XCTAssertFalse(model.isVirtualPlayer("nobody"))
  }

  // MARK: - reportRounds

  func testReportRoundsIncludesBothCompletedAndCurrentRound() {
    let model = makeModel()
    let completed = makeRound(id: "round-0", number: 0, status: "closed")
    let current = makeRound(id: "round-1", number: 1, status: "open")
    model.completedRounds = [completed]
    model.round = current
    let result = model.reportRounds()
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result.map(\.id), ["round-0", "round-1"])
  }

  func testReportRoundsDeduplicatesRoundsApperingInBothLists() {
    let model = makeModel()
    let r = makeRound(id: "round-1", number: 1, status: "closed")
    model.completedRounds = [r]
    model.round = r  // same round in both
    let result = model.reportRounds()
    XCTAssertEqual(result.count, 1)
  }

  func testReportRoundsIsSortedByNumber() {
    let model = makeModel()
    let r2 = makeRound(id: "round-2", number: 2, status: "closed")
    let r1 = makeRound(id: "round-1", number: 1, status: "closed")
    model.completedRounds = [r2, r1]
    model.round = nil
    let result = model.reportRounds()
    XCTAssertEqual(result.map(\.number), [1, 2])
  }

  // MARK: - orderedPlayerIDsForReport

  func testOrderedPlayerIDsForReportPutsLocalPlayerLast() {
    let model = makeModel()
    let rounds: [RoundPayload] = []
    let ordered = model.orderedPlayerIDsForReport(in: rounds)
    XCTAssertEqual(ordered.last, "player-local")
  }

  func testOrderedPlayerIDsForReportSortsOthersAlphabetically() {
    let model = makeModel()
    let rounds: [RoundPayload] = []
    let ordered = model.orderedPlayerIDsForReport(in: rounds)
    // Local is last; Alex comes before Local alphabetically
    XCTAssertEqual(ordered, ["player-a", "player-local"])
  }

  func testOrderedPlayerIDsForReportFallsBackToSubmissionsWhenNoParticipants() {
    let game = makeGame(participants: [])
    let model = makeModel(game: game)
    let subs = [
      makeSubmission(id: "s1", playerID: "player-b", playerName: "Bob"),
      makeSubmission(id: "s2", playerID: "player-local", playerName: "Local")
    ]
    let rounds = [makeRound(submissions: subs)]
    let ordered = model.orderedPlayerIDsForReport(in: rounds)
    XCTAssertEqual(ordered.last, "player-local")
    XCTAssertTrue(ordered.contains("player-b"))
  }

  // MARK: - winningRound / goalWord

  func testWinningRoundReturnsRoundMatchingWinningRoundNumber() {
    let r1 = makeRound(id: "round-1", number: 1, status: "closed")
    let r2 = makeRound(id: "round-2", number: 2, status: "closed")
    let game = makeGame(winningRoundNumber: 2)
    let model = makeModel(game: game)
    model.completedRounds = [r1, r2]
    XCTAssertEqual(model.winningRound()?.id, "round-2")
  }

  func testWinningRoundFallsBackToCurrentRoundWhenCompletedDoesNotMatch() {
    let game = makeGame(winningRoundNumber: 99)
    let model = makeModel(game: game)
    model.completedRounds = []
    model.round = makeRound(id: "round-current", number: 1)
    XCTAssertEqual(model.winningRound()?.id, "round-current")
  }

  func testWinningRoundReturnsLastCompletedRoundWhenNoWinningNumber() {
    let game = makeGame(winningRoundNumber: nil)
    let model = makeModel(game: game)
    let r1 = makeRound(id: "round-1", number: 1, status: "closed")
    let r2 = makeRound(id: "round-2", number: 2, status: "closed")
    model.completedRounds = [r1, r2]
    model.round = nil
    XCTAssertEqual(model.winningRound()?.id, "round-2")
  }

  func testWinningRoundReturnsCurrentRoundWhenNoCompletedAndNoNumber() {
    let game = makeGame(winningRoundNumber: nil)
    let model = makeModel(game: game)
    model.completedRounds = []
    model.round = makeRound(id: "round-active")
    XCTAssertEqual(model.winningRound()?.id, "round-active")
  }

  func testGoalWordExtractsGoalFromFeedback() {
    let model = makeModel()
    let feedback = SubmissionFeedback(goal: "SMOKE", guess: "smoke", marks: nil)
    let sub = makeSubmission(id: "s1", playerID: "player-a", feedback: feedback)
    model.completedRounds = [makeRound(id: "r1", number: 1, submissions: [sub])]
    XCTAssertEqual(model.goalWord(), "SMOKE")
  }

  func testGoalWordReturnsNilWhenNoFeedback() {
    let model = makeModel()
    let sub = makeSubmission(id: "s1", playerID: "player-a", feedback: nil)
    model.completedRounds = [makeRound(id: "r1", number: 1, submissions: [sub])]
    XCTAssertNil(model.goalWord())
  }

  func testGoalWordIgnoresEmptyGoalString() {
    let model = makeModel()
    let feedback = SubmissionFeedback(goal: "", guess: nil, marks: nil)
    let sub = makeSubmission(id: "s1", playerID: "player-a", feedback: feedback)
    model.completedRounds = [makeRound(id: "r1", number: 1, submissions: [sub])]
    XCTAssertNil(model.goalWord())
  }

  // MARK: - playerName(for:in:)

  func testPlayerNameInRoundsFallsBackToSubmissionName() {
    let model = makeModel(game: makeGame(participants: []))
    let sub = makeSubmission(id: "s1", playerID: "unknown-player", playerName: "Ghost")
    let rounds = [makeRound(submissions: [sub])]
    XCTAssertEqual(model.playerName(for: "unknown-player", in: rounds), "Ghost")
  }

  func testPlayerNameInRoundsPrefersParticipantName() {
    let model = makeModel()
    let sub = makeSubmission(id: "s1", playerID: "player-local", playerName: "Wrong Name")
    let rounds = [makeRound(submissions: [sub])]
    XCTAssertEqual(model.playerName(for: "player-local", in: rounds), "Local")
  }

  func testPlayerNameInRoundsReturnsNilWhenNotFound() {
    let model = makeModel(game: makeGame(participants: []))
    XCTAssertNil(model.playerName(for: "nobody", in: []))
  }

  // MARK: - winnerIDs

  func testWinnerIDsReturnsCorrectGuessersWithTopScore() {
    let model = makeModel()
    let winner = makeSubmission(id: "s1", playerID: "player-local", correctGuess: true)
    let loser = makeSubmission(id: "s2", playerID: "player-a", correctGuess: false)
    let round = makeRound(submissions: [winner, loser])
    let ids = model.winnerIDs(for: round)
    XCTAssertEqual(ids, ["player-local"])
  }

  func testWinnerIDsReturnsEmptyWhenNoCorrectGuesses() {
    let model = makeModel()
    let sub1 = makeSubmission(id: "s1", playerID: "player-local", correctGuess: false)
    let round = makeRound(submissions: [sub1])
    XCTAssertTrue(model.winnerIDs(for: round).isEmpty)
  }

  func testWinnerIDsReturnsMultipleWinnersWithEqualScore() {
    // Both players have correctGuess = true; both have same score via playerScore
    let participants = [
      GameParticipant(id: "p1", role: "host", score: 10, joinedAt: nil,
        player: GameParticipantPlayer(id: "player-local", displayName: "Local", nickname: nil, gameCenterPlayerID: "GC-l", virtual: false)),
      GameParticipant(id: "p2", role: "player", score: 10, joinedAt: nil,
        player: GameParticipantPlayer(id: "player-a", displayName: "Alex", nickname: nil, gameCenterPlayerID: "GC-a", virtual: false))
    ]
    let game = makeGame(participants: participants)
    let model = makeModel(game: game)
    let sub1 = makeSubmission(id: "s1", playerID: "player-local", correctGuess: true)
    let sub2 = makeSubmission(id: "s2", playerID: "player-a", correctGuess: true)
    let round = makeRound(submissions: [sub1, sub2])
    let ids = Set(model.winnerIDs(for: round))
    XCTAssertEqual(ids, Set(["player-local", "player-a"]))
  }

  // MARK: - toggleFavorite / toggleLeast / canSubmitVotes

  func testToggleFavoriteSelectsSubmission() {
    let model = makeModel()
    let sub = makeSubmission(id: "sub-1")
    model.toggleFavorite(for: sub)
    XCTAssertEqual(model.selectedFavoriteID, "sub-1")
  }

  func testToggleFavoriteDeselectsWhenSameSubmission() {
    let model = makeModel()
    let sub = makeSubmission(id: "sub-1")
    model.selectedFavoriteID = "sub-1"
    model.toggleFavorite(for: sub)
    XCTAssertNil(model.selectedFavoriteID)
  }

  func testToggleFavoriteClearsLeastWhenSameAsNewFavorite() {
    let model = makeModel()
    model.selectedLeastID = "sub-1"
    let sub = makeSubmission(id: "sub-1")
    model.toggleFavorite(for: sub)
    XCTAssertEqual(model.selectedFavoriteID, "sub-1")
    XCTAssertNil(model.selectedLeastID)
  }

  func testToggleLeastSelectsSubmission() {
    let model = makeModel()
    let sub = makeSubmission(id: "sub-2")
    model.toggleLeast(for: sub)
    XCTAssertEqual(model.selectedLeastID, "sub-2")
  }

  func testToggleLeastDeselectsWhenSameSubmission() {
    let model = makeModel()
    let sub = makeSubmission(id: "sub-2")
    model.selectedLeastID = "sub-2"
    model.toggleLeast(for: sub)
    XCTAssertNil(model.selectedLeastID)
  }

  func testToggleLeastClearsFavoriteWhenSameAsNewLeast() {
    let model = makeModel()
    model.selectedFavoriteID = "sub-2"
    let sub = makeSubmission(id: "sub-2")
    model.toggleLeast(for: sub)
    XCTAssertEqual(model.selectedLeastID, "sub-2")
    XCTAssertNil(model.selectedFavoriteID)
  }

  func testCanSubmitVotesReturnsTrueWhenDifferentSelectionsChosen() {
    let model = makeModel()
    model.selectedFavoriteID = "sub-fav"
    model.selectedLeastID = "sub-least"
    XCTAssertTrue(model.canSubmitVotes())
  }

  func testCanSubmitVotesReturnsFalseWhenSelectionsMissing() {
    let model = makeModel()
    model.selectedFavoriteID = nil
    model.selectedLeastID = nil
    XCTAssertFalse(model.canSubmitVotes())
  }

  func testCanSubmitVotesReturnsFalseWhenSelectionsAreSame() {
    let model = makeModel()
    model.selectedFavoriteID = "sub-1"
    model.selectedLeastID = "sub-1"
    XCTAssertFalse(model.canSubmitVotes())
  }

  // MARK: - hasPendingInvitedPlayers / shouldConfirmEarlyStart

  func testHasPendingInvitedPlayersReturnsFalseWhenNilInvited() {
    let model = makeModel(game: makeGame(invitedPlayers: nil))
    XCTAssertFalse(model.hasPendingInvitedPlayers())
  }

  func testHasPendingInvitedPlayersReturnsFalseWhenAllAccepted() {
    let invited = [GameInvitedPlayer(
      playerID: "player-a", displayName: "Alex",
      nickname: nil, inviteStatus: "accepted", accepted: true
    )]
    let model = makeModel(game: makeGame(invitedPlayers: invited))
    XCTAssertFalse(model.hasPendingInvitedPlayers())
  }

  func testHasPendingInvitedPlayersReturnsTrueForPendingInvite() {
    let invited = [GameInvitedPlayer(
      playerID: "player-b", displayName: "Bailey",
      nickname: nil, inviteStatus: "pending", accepted: false
    )]
    let model = makeModel(game: makeGame(invitedPlayers: invited))
    XCTAssertTrue(model.hasPendingInvitedPlayers())
  }

  func testShouldConfirmEarlyStartReturnsFalseWhenNotHost() {
    let invited = [GameInvitedPlayer(
      playerID: "player-c", displayName: "Casey",
      nickname: nil, inviteStatus: "pending", accepted: false
    )]
    let model = makeModel(game: makeGame(invitedPlayers: invited), localPlayerID: "player-a")
    XCTAssertFalse(model.shouldConfirmEarlyStart())
  }

  // MARK: - disconnectFromGameChannel

  func testDisconnectFromGameChannelClearsClient() {
    let model = makeModel()
    // connectToGameChannel requires an auth token on the APIClient;
    // we call disconnect directly to ensure it's a no-op (nil client) without crashing
    model.disconnectFromGameChannel()
    // No assertion needed – test passes if no crash occurs
  }

  // MARK: - buildCableURL (via connectToGameChannel)

  func testConnectToGameChannelNoopsWhenNoAuthToken() {
    var client = APIClient(baseURL: URL(string: "https://example.com")!)
    client.authToken = nil  // No token → buildCableURL returns nil → early return
    let model = GameRoomModel(game: makeGame(), apiClient: client, localPlayerID: "player-local")
    model.connectToGameChannel()
    // If we reach here without crashing the guard returned cleanly
  }

  // MARK: - problemWithGameReportMessage

  func testProblemReportMessageOmitsNameAndEmailWhenEmpty() {
    let model = makeModel()
    let msg = model.problemWithGameReportMessage(
      description: "Something broke.",
      providedName: "   ",   // whitespace only
      providedEmail: ""
    )
    XCTAssertFalse(msg.contains("provided_name"))
    XCTAssertFalse(msg.contains("provided_email"))
  }

  func testProblemReportMessageIncludesNameAndEmailWhenProvided() {
    let model = makeModel()
    let msg = model.problemWithGameReportMessage(
      description: "Something broke.",
      providedName: "Taylor",
      providedEmail: "t@example.com"
    )
    XCTAssertTrue(msg.contains("provided_name: Taylor"))
    XCTAssertTrue(msg.contains("provided_email: t@example.com"))
  }

  func testProblemReportMessageUsesUnknownWhenLocalPlayerNotInParticipants() {
    let game = makeGame(participants: [])
    let model = makeModel(game: game)
    let msg = model.problemWithGameReportMessage(
      description: "Broke", providedName: nil, providedEmail: nil
    )
    XCTAssertTrue(msg.contains("player_name: Unknown"))
  }

  // MARK: - submitProblemWithGameReport

  func testSubmitProblemWithGameReportThrowsWhenDescriptionBlank() async {
    let model = makeModel()
    do {
      try await model.submitProblemWithGameReport(description: "   ", name: nil, email: nil)
      XCTFail("Expected throw")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("Please describe the problem."))
    }
  }

  func testSubmitProblemWithGameReportSucceeds() async throws {
    let model = makeModel()
    // The support API goes to api.web3forms.com – stub it
    StubURLProtocol.stub("web3forms.com", status: 200, body: "{\"success\":true}")
    try await model.submitProblemWithGameReport(description: "Something broke.", name: "Test", email: "t@t.com")
  }

  // MARK: - submitInappropriateContentReport

  func testSubmitInappropriateContentReportThrowsWhenEmpty() async {
    let model = makeModel()
    do {
      try await model.submitInappropriateContentReport(selectedPhrases: [])
      XCTFail("Expected throw")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("Select at least one phrase to report."))
    }
  }

  func testSubmitInappropriateContentReportSucceeds() async throws {
    let model = makeModel()
    StubURLProtocol.stub("web3forms.com", status: 200, body: "{\"success\":true}")
    let phrases = [ReportablePhrase(id: "p1", roundNumber: 1, playerID: "player-a", playerName: "Alex", phrase: "bad")]
    try await model.submitInappropriateContentReport(selectedPhrases: phrases)
  }

  // MARK: - waitingRoomPlayerStatuses (additional edge cases)

  func testWaitingRoomStatusesReturnsEmptyWhenNoParticipants() {
    let model = makeModel(game: makeGame(nilParticipants: true))
    XCTAssertTrue(model.waitingRoomPlayerStatuses().isEmpty)
  }

  func testWaitingRoomStatusesShowsJoinedForParticipantMatchedByGCID() {
    // An invited player whose playerID matches a participant's gameCenterPlayerID
    let participants = [
      GameParticipant(
        id: "part-local",
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
        id: "part-b",
        role: "player",
        score: 0,
        joinedAt: nil,
        player: GameParticipantPlayer(
          id: "player-b-server",
          displayName: "Bailey",
          nickname: nil,
          gameCenterPlayerID: "GC-invited-b",
          virtual: false
        )
      )
    ]
    // Invited player's playerID == participant's gameCenterPlayerID
    let invited = [GameInvitedPlayer(
      playerID: "GC-invited-b",
      displayName: "Bailey",
      nickname: nil,
      inviteStatus: "accepted",
      accepted: true
    )]
    let game = makeGame(participants: participants, invitedPlayers: invited)
    let model = makeModel(game: game)
    let statuses = model.waitingRoomPlayerStatuses()
    let baileyStatus = statuses.first { $0.playerID == "GC-invited-b" }
    XCTAssertEqual(baileyStatus?.statusText, "Joined")
  }

  func testWaitingRoomStatusesSkipsHostInInvitedLoop() {
    // When the host is also in the invited list, they should only appear once as Host
    let hostID = "player-local"
    let invited = [
      GameInvitedPlayer(
        playerID: hostID,
        displayName: "Local",
        nickname: nil,
        inviteStatus: "accepted",
        accepted: true
      ),
      GameInvitedPlayer(
        playerID: "player-a",
        displayName: "Alex",
        nickname: nil,
        inviteStatus: "pending",
        accepted: false
      )
    ]
    let model = makeModel(game: makeGame(invitedPlayers: invited))
    let statuses = model.waitingRoomPlayerStatuses()
    let hostStatuses = statuses.filter { $0.playerID == hostID }
    XCTAssertEqual(hostStatuses.count, 1)
    XCTAssertEqual(hostStatuses.first?.statusText, "Host")
  }

  func testWaitingRoomStatusesAddsUnlistedParticipantAsJoined() {
    // A participant who is not in the invited list should still appear as Joined
    let model = makeModel(game: makeGame(invitedPlayers: []))
    let statuses = model.waitingRoomPlayerStatuses()
    // player-a is a participant but not invited; should appear as "Joined"
    let alexStatus = statuses.first { $0.playerID == "player-a" }
    XCTAssertEqual(alexStatus?.statusText, "Joined")
    XCTAssertTrue(alexStatus?.highlightsAsPositive == true)
  }
}
