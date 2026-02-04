import XCTest

@MainActor
final class WordsmokeLocalUITests: XCTestCase {
  private let app = XCUIApplication()
  private var adminClient: TestAdminClient?
  private var createdGameID: String?
  nonisolated(unsafe) private var testDidFail = false

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    if let testRun, !testRun.hasSucceeded {
      await MainActor.run {
        Self.captureFailureArtifacts(app: app, testName: name)
      }
    }
    if !testDidFail, let adminClient, let createdGameID {
        try await adminClient.deleteGame(gameID: createdGameID)
    }
    try await super.tearDown()
  }

  override func record(_ issue: XCTIssue) {
    testDidFail = true
    super.record(issue)
  }

  func testLocalGameFlow() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    app.launchEnvironment["WORDSMOKE_UI_TESTS"] = "1"
    app.launchEnvironment["WORDSMOKE_BASE_URL"] = baseURL.absoluteString
    app.launch()

    let newGameButton = app.buttons["new-game-button"]
    XCTAssertTrue(newGameButton.waitForExistence(timeout: 20))

    let createdAfter = Date()
    newGameButton.tap()

    let game = try await admin.waitForLatestGame(createdAfter: createdAfter, timeout: 20)
    createdGameID = game.id
    _ = try await admin.createVirtualPlayers(gameID: game.id, count: 2)

    let gameCard = app.buttons["active-game-\(game.id)"]
    XCTAssertTrue(gameCard.waitForExistence(timeout: 20))
    gameCard.tap()

    dismissOnboardingIfPresent()

    let startButton = app.buttons["game-room-start-button"]
    XCTAssertTrue(startButton.waitForExistence(timeout: 20))
    startButton.tap()

    let roundOneState = try await admin.waitForRound(gameID: game.id, number: 1, timeout: 30)
    let roundOneID = try requireRoundID(from: roundOneState)
    let wordsRoundOne = try await admin.fetchWords(gameID: game.id, excludeGoal: true)

    let localPlayerID = try requireLocalPlayerID(from: roundOneState)
    let virtualPlayerIDs = roundOneState.participants.filter { $0.virtual }.map { $0.id }
      _ = roundOneState.participants.reduce(into: [String: String]()) { result, participant in
      result[participant.id] = participant.displayName
    }
    var expectedGuessesByRound: [Int: [String: String]] = [:]

    try submitGuess(word: wordsRoundOne.randomGuessWord, phrasePrefix: "test")
    expectedGuessesByRound[1] = [
      localPlayerID: wordsRoundOne.randomGuessWord.uppercased()
    ]

    for playerID in virtualPlayerIDs {
      let response = try await admin.createSubmission(
        gameID: game.id,
        roundID: roundOneID,
        playerID: playerID,
        auto: true,
        excludeGoal: true
      )
      if let guessWord = response.submission?.guessWord {
        expectedGuessesByRound[1, default: [:]][playerID] = guessWord.uppercased()
      }
    }

    let roundOneVoting = try await admin.waitForRoundStatus(gameID: game.id, status: "voting", timeout: 20)
    let roundOneVotingID = try requireRoundID(from: roundOneVoting)
    let otherSubmissionIDs = roundOneVoting.submissions
      .filter { $0.playerId != localPlayerID }
      .map { $0.id }
    XCTAssertGreaterThanOrEqual(otherSubmissionIDs.count, 2)

    try submitVotes(favoriteID: otherSubmissionIDs[0], leastID: otherSubmissionIDs[1])

    for playerID in virtualPlayerIDs {
      _ = try await admin.createPhraseVote(
        gameID: game.id,
        roundID: roundOneVotingID,
        voterID: playerID,
        auto: true
      )
    }

    let roundTwoState = try await admin.waitForRound(gameID: game.id, number: 2, timeout: 30)
    let roundTwoID = try requireRoundID(from: roundTwoState)
    let wordsRoundTwo = try await admin.fetchWords(gameID: game.id, excludeGoal: false)
      _ = try requirePlayerName(from: roundTwoState, playerID: localPlayerID)

    let goalWord = wordsRoundTwo.goalWord

    try submitGuess(word: goalWord, phrasePrefix: "winner with")
    expectedGuessesByRound[2] = [
      localPlayerID: goalWord.uppercased()
    ]

    for playerID in virtualPlayerIDs {
      let response = try await admin.createSubmission(
        gameID: game.id,
        roundID: roundTwoID,
        playerID: playerID,
        auto: true,
        excludeGoal: true
      )
      if let guessWord = response.submission?.guessWord {
        expectedGuessesByRound[2, default: [:]][playerID] = guessWord.uppercased()
      }
    }

    let roundTwoVoting = try await admin.waitForRoundStatus(gameID: game.id, status: "voting", timeout: 20)
    let roundTwoVotingID = try requireRoundID(from: roundTwoVoting)
    let otherSubmissionIDsRoundTwo = roundTwoVoting.submissions
      .filter { $0.playerId != localPlayerID }
      .map { $0.id }
    XCTAssertGreaterThanOrEqual(otherSubmissionIDsRoundTwo.count, 2)

    let roundTwoStateForGuesses = try await admin.fetchState(gameID: game.id)
      _ = roundTwoStateForGuesses.submissions.reduce(into: [String: String]()) { result, submission in
      if let guessWord = submission.guessWord {
        result[submission.playerName] = guessWord.uppercased()
      }
    }

    try submitVotes(favoriteID: otherSubmissionIDsRoundTwo[0], leastID: otherSubmissionIDsRoundTwo[1])

    for playerID in virtualPlayerIDs {
      _ = try await admin.createPhraseVote(
        gameID: game.id,
        roundID: roundTwoVotingID,
        voterID: playerID,
        auto: true
      )
    }

    let gameOverSection = app.staticTexts["game-over-section"]
    XCTAssertTrue(scrollToElement(gameOverSection, timeout: 20))

    let winnerIdentifier = "game-over-player-id-\(localPlayerID)"
    let winnerRow = app.otherElements[winnerIdentifier]
    XCTAssertTrue(scrollToElement(winnerRow, timeout: 20))

    for (roundNumber, guesses) in expectedGuessesByRound {
      for (playerID, guessWord) in guesses {
        let identifier = "player-round-row-\(roundNumber)-\(playerID)"
        let row = app.otherElements[identifier]
        XCTAssertTrue(scrollToElement(row, timeout: 20))
        let didMatch = await waitForValue(row, equals: guessWord, timeout: 10)
        XCTAssertTrue(didMatch)
      }
    }
  }

  private func submitGuess(word: String, phrasePrefix: String) throws {
    dismissOnboardingIfPresent()
    let guessField = app.textFields["guess-word-field"]
    XCTAssertTrue(scrollToElement(guessField, timeout: 20))
    guessField.tap()
    guessField.typeText(word)

    let phraseField = app.textFields["phrase-field"]
    XCTAssertTrue(scrollToElement(phraseField, timeout: 10))
    phraseField.tap()
    phraseField.typeText("\(phrasePrefix) \(word)")

    let submitButton = app.buttons["submit-guess-button"]
    XCTAssertTrue(scrollToElement(submitButton, timeout: 10))
    submitButton.tap()
  }

  private func submitVotes(favoriteID: String, leastID: String) throws {
    dismissOnboardingIfPresent()
    let favoriteButton = app.buttons["vote-favorite-\(favoriteID)"]
    XCTAssertTrue(scrollToElement(favoriteButton, timeout: 20))
    favoriteButton.tap()

    let leastButton = app.buttons["vote-least-\(leastID)"]
    XCTAssertTrue(scrollToElement(leastButton, timeout: 20))
    leastButton.tap()

    let submitVotesButton = app.buttons["submit-votes-button"]
    XCTAssertTrue(scrollToElement(submitVotesButton, timeout: 10))
    submitVotesButton.tap()
  }

  private func scrollToElement(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    if element.waitForExistence(timeout: timeout) {
      return true
    }

    let container: XCUIElement
    if app.collectionViews.firstMatch.exists {
      container = app.collectionViews.firstMatch
    } else if app.tables.firstMatch.exists {
      container = app.tables.firstMatch
    } else {
      container = app.scrollViews.firstMatch
    }
    let scrollTarget = container.exists ? container : app

    let maxSwipes = 10
    let perSwipeTimeout = max(1, timeout / TimeInterval(maxSwipes))
    for _ in 0..<maxSwipes {
      scrollTarget.swipeUp()
      if element.waitForExistence(timeout: perSwipeTimeout) {
        return true
      }
    }
    return element.waitForExistence(timeout: perSwipeTimeout)
  }

  private func dismissOnboardingIfPresent(timeout: TimeInterval = 2) {
    let skipButton = app.buttons["Skip Tour"]
    if skipButton.waitForExistence(timeout: timeout) {
      skipButton.tap()
    }
  }

  private func waitForValue(
    _ element: XCUIElement,
    equals expectedValue: String,
    timeout: TimeInterval,
    pollInterval: Duration = .milliseconds(200)
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))
    while clock.now < deadline {
      if element.value as? String == expectedValue {
        return true
      }
      try? await Task.sleep(for: pollInterval)
    }
    return element.value as? String == expectedValue
  }

  private static func accessibilitySafePlayerName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split { !($0.isLetter || $0.isNumber) }
    let joined = parts.joined(separator: "-")
    return joined.isEmpty ? "player" : joined
  }

  private static func captureFailureArtifacts(app: XCUIApplication, testName: String) {
    let screenshot: XCUIScreenshot
    if app.state == .runningForeground {
      screenshot = app.screenshot()
    } else {
      screenshot = XCUIScreen.main.screenshot()
    }
    let data = screenshot.pngRepresentation
    let filename = sanitizedFilename(for: testName)
    let screenshotURL = URL(fileURLWithPath: "/tmp").appendingPathComponent("\(filename).png")
    let debugDescriptionURL = URL(fileURLWithPath: "/tmp").appendingPathComponent("\(filename).txt")
    do {
      try data.write(to: screenshotURL, options: .atomic)
      try app.debugDescription.write(to: debugDescriptionURL, atomically: true, encoding: .utf8)
    } catch {
      // Best-effort: avoid masking test failures.
    }
  }

  nonisolated private static func sanitizedFilename(for testName: String) -> String {
    let base = testName
      .replacingOccurrences(of: " ", with: "_")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
    let unique = ProcessInfo.processInfo.globallyUniqueString
    return "ui-test-failure-\(base)-\(unique)"
  }

  private func requireLocalPlayerID(from state: TestAdminClient.StateResponse) throws -> String {
    if let local = state.participants.first(where: { !$0.virtual }) {
      return local.id
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "Local player not found in participants."
    ])
  }

  private func requireRoundID(from state: TestAdminClient.StateResponse) throws -> String {
    if let roundID = state.game.currentRoundId {
      return roundID
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 3, userInfo: [
      NSLocalizedDescriptionKey: "Current round not found."
    ])
  }

  private func requireRoundNumber(from state: TestAdminClient.StateResponse) throws -> Int {
    if let roundNumber = state.currentRound?.number {
      return roundNumber
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 5, userInfo: [
      NSLocalizedDescriptionKey: "Current round number not found."
    ])
  }

  private func requirePlayerName(
    from state: TestAdminClient.StateResponse,
    playerID: String
  ) throws -> String {
    if let participant = state.participants.first(where: { $0.id == playerID }) {
      return participant.displayName
    }
    if let submission = state.submissions.first(where: { $0.playerId == playerID }) {
      return submission.playerName
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 4, userInfo: [
      NSLocalizedDescriptionKey: "Player name not found for \(playerID)."
    ])
  }

  private static func resolveBaseURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    if let rawValue = env["WORDSMOKE_UI_TEST_BASE_URL"], let url = URL(string: rawValue) {
      return url
    }
    return URL(string: "http://127.0.0.1:3000")!
  }

  private static func resolveAdminToken() throws -> String {
    let env = ProcessInfo.processInfo.environment
    if let token = env["WORDSMOKE_TEST_ADMIN_TOKEN"], !token.isEmpty {
      return token
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Missing WORDSMOKE_TEST_ADMIN_TOKEN in environment."
    ])
  }
}
