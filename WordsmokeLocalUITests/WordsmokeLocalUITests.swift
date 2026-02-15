import Foundation
import XCTest

@MainActor
final class WordsmokeLocalUITests: XCTestCase {
  private static let defaultInviteeNames = ["Alice", "Bob", "Cindy"]
  private let app = XCUIApplication()
  private var adminClient: TestAdminClient?
  private var createdGameID: String?
  private var createdGameIDs: [String] = []
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
    if !testDidFail, let adminClient {
      if let createdGameID {
        try await adminClient.deleteGame(gameID: createdGameID)
      }
      for gameID in createdGameIDs {
        try? await adminClient.deleteGame(gameID: gameID)
      }
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
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchApp(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    let createdAfter = Date()
    let game = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter,
      playerCount: 3
    )

    dismissOnboardingIfPresent()

    let roundOneState = try await admin.waitForRound(gameID: game.id, number: 1, timeout: 30)
    let roundOneID = try requireRoundID(from: roundOneState)
    let wordsRoundOne = try await admin.fetchWords(gameID: game.id, excludeGoal: true)

    let localPlayerID = try requireLocalPlayerID(from: roundOneState)
    let virtualPlayerIDs = roundOneState.participants.filter { $0.virtual }.map { $0.id }
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

  // MARK: - 2-Player Tests

  func testTwoPlayerGameLocalPlayerWins() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchApp(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    let createdAfter = Date()
    let game = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter,
      playerCount: 2,
      wordLength: 4
    )

    dismissOnboardingIfPresent()

    // Round 1: Both players submit non-goal words
    let roundOneState = try await admin.waitForRound(gameID: game.id, number: 1, timeout: 30)
    let roundOneID = try requireRoundID(from: roundOneState)
    let wordsRoundOne = try await admin.fetchWords(gameID: game.id, excludeGoal: true)

    let localPlayer = roundOneState.participants.first { !$0.virtual }!
    let virtualPlayer = try requireVirtualPlayer(from: roundOneState)

    try submitGuess(word: wordsRoundOne.randomGuessWord, phrasePrefix: "round one")

    _ = try await admin.createSubmission(
      gameID: game.id,
      roundID: roundOneID,
      playerID: virtualPlayer.id,
      auto: true,
      excludeGoal: true
    )

    // Round 2: Local player wins by guessing goal word
    let roundTwoState = try await admin.waitForRound(gameID: game.id, number: 2, timeout: 30)
    let roundTwoID = try requireRoundID(from: roundTwoState)
    let wordsRoundTwo = try await admin.fetchWords(gameID: game.id, excludeGoal: false)
    let goalWord = wordsRoundTwo.goalWord

    try submitGuess(word: goalWord, phrasePrefix: "winner with")

    _ = try await admin.createSubmission(
      gameID: game.id,
      roundID: roundTwoID,
      playerID: virtualPlayer.id,
      auto: true,
      excludeGoal: true
    )

    // Verify game over with local player as winner
    let gameOverSection = app.staticTexts["game-over-section"]
    XCTAssertTrue(scrollToElement(gameOverSection, timeout: 20))

    // Find the row by player name and check its accessibility label
    let localPlayerSafeName = Self.accessibilitySafePlayerName(localPlayer.displayName)
    let localPlayerRow = app.otherElements["game-over-player-\(localPlayerSafeName)"]
    XCTAssertTrue(scrollToElement(localPlayerRow, timeout: 20))
    XCTAssertTrue(localPlayerRow.label.contains("Winner"), "Local player should be marked as winner")

    let virtualPlayerSafeName = Self.accessibilitySafePlayerName(virtualPlayer.displayName)
    let virtualPlayerRow = app.otherElements["game-over-player-\(virtualPlayerSafeName)"]
    XCTAssertTrue(scrollToElement(virtualPlayerRow, timeout: 20))
    XCTAssertFalse(virtualPlayerRow.label.contains("Winner"), "Virtual player should not be marked as winner")
  }

  func testTwoPlayerGameLocalPlayerLoses() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchApp(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    let createdAfter = Date()
    let game = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter,
      playerCount: 2,
      wordLength: 7
    )

    dismissOnboardingIfPresent()

    // Round 1: Both players submit non-goal words
    let roundOneState = try await admin.waitForRound(gameID: game.id, number: 1, timeout: 30)
    let roundOneID = try requireRoundID(from: roundOneState)
    let wordsRoundOne = try await admin.fetchWords(gameID: game.id, excludeGoal: true)

    let localPlayer = roundOneState.participants.first { !$0.virtual }!
    let virtualPlayer = try requireVirtualPlayer(from: roundOneState)

    try submitGuess(word: wordsRoundOne.randomGuessWord, phrasePrefix: "round one")

    _ = try await admin.createSubmission(
      gameID: game.id,
      roundID: roundOneID,
      playerID: virtualPlayer.id,
      auto: true,
      excludeGoal: true
    )

    // Round 2: Virtual player wins by guessing goal word, local player loses
    let roundTwoState = try await admin.waitForRound(gameID: game.id, number: 2, timeout: 30)
    let roundTwoID = try requireRoundID(from: roundTwoState)
    let wordsRoundTwo = try await admin.fetchWords(gameID: game.id, excludeGoal: true)
    let goalWord = try await admin.fetchWords(gameID: game.id, excludeGoal: false).goalWord

    // Local player submits a non-goal word (fetch fresh word to ensure validity)
    try submitGuess(word: wordsRoundTwo.randomGuessWord, phrasePrefix: "not the answer")

    // Virtual player submits the goal word and wins
    _ = try await admin.createSubmission(
      gameID: game.id,
      roundID: roundTwoID,
      playerID: virtualPlayer.id,
      guessWord: goalWord,
      phrase: "I win \(goalWord)",
      auto: false,
      excludeGoal: false
    )

    // Verify game over with virtual player as winner
    let gameOverSection = app.staticTexts["game-over-section"]
    XCTAssertTrue(scrollToElement(gameOverSection, timeout: 20))

    // Check virtual player is the winner (by name-based identifier with accessibility label)
    let virtualPlayerSafeName = Self.accessibilitySafePlayerName(virtualPlayer.displayName)
    let virtualPlayerRow = app.otherElements["game-over-player-\(virtualPlayerSafeName)"]
    XCTAssertTrue(scrollToElement(virtualPlayerRow, timeout: 20))
    XCTAssertTrue(virtualPlayerRow.label.contains("Winner"), "Virtual player should be marked as winner")

    // Check local player is NOT the winner
    let localPlayerSafeName = Self.accessibilitySafePlayerName(localPlayer.displayName)
    let localPlayerRow = app.otherElements["game-over-player-\(localPlayerSafeName)"]
    XCTAssertTrue(scrollToElement(localPlayerRow, timeout: 20))
    XCTAssertFalse(localPlayerRow.label.contains("Winner"), "Local player should not be marked as winner")
  }

  // MARK: - Voting UI Tests

  /// Tests that after submitting votes, the UI updates to show a waiting state
  /// instead of continuing to show the voting controls.
  func testVotingUIUpdatesAfterSubmission() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchApp(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    let createdAfter = Date()
    let game = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter,
      playerCount: 3
    )

    dismissOnboardingIfPresent()

    // Round 1: All players submit guesses
    let roundOneState = try await admin.waitForRound(gameID: game.id, number: 1, timeout: 30)
    let roundOneID = try requireRoundID(from: roundOneState)
    let wordsRoundOne = try await admin.fetchWords(gameID: game.id, excludeGoal: true)

    let localPlayerID = try requireLocalPlayerID(from: roundOneState)
    let virtualPlayerIDs = roundOneState.participants.filter(\.virtual).map(\.id)

    try submitGuess(word: wordsRoundOne.randomGuessWord, phrasePrefix: "round one")

    for playerID in virtualPlayerIDs {
      _ = try await admin.createSubmission(
        gameID: game.id,
        roundID: roundOneID,
        playerID: playerID,
        auto: true,
        excludeGoal: true
      )
    }

    // Wait for voting phase
    let votingState = try await admin.waitForRoundStatus(gameID: game.id, status: "voting", timeout: 20)
    let otherSubmissionIDs = votingState.submissions
      .filter { $0.playerId != localPlayerID }
      .map { $0.id }
    XCTAssertGreaterThanOrEqual(otherSubmissionIDs.count, 2, "Need at least 2 other submissions for voting")

    // Wait for voting UI to appear
    let submitVotesButton = app.buttons["submit-votes-button"]
    XCTAssertTrue(scrollToElement(submitVotesButton, timeout: 20), "Submit votes button should appear")

    // Submit votes (local player only - virtual players don't vote yet)
    try submitVotes(favoriteID: otherSubmissionIDs[0], leastID: otherSubmissionIDs[1])

    // After submitting votes, the submit button should disappear and be replaced
    // by a waiting message. Give UI time to update.
    let buttonDisappeared = await waitForButtonToDisappear(submitVotesButton, timeout: 10)
    XCTAssertTrue(
      buttonDisappeared,
      "Submit votes button should disappear after submitting votes"
    )
  }

  private func waitForButtonToDisappear(_ button: XCUIElement, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !button.exists {
        return true
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return !button.exists
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

    // Wait for the button to become enabled (validation to complete)
    let enabledPredicate = NSPredicate(format: "isEnabled == true")
    let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: submitButton)
    let result = XCTWaiter.wait(for: [expectation], timeout: 10)
    XCTAssertEqual(result, .completed, "Submit button should become enabled")

    submitButton.tap()
    assertNoSubmissionError()
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
    assertNoVotingError()
  }

  private func assertNoSubmissionError() {
    let errorText = app.staticTexts["submission-error"]
    XCTAssertFalse(
      errorText.waitForExistence(timeout: 2),
      "Unexpected submission error: \(errorText.exists ? errorText.label : "unknown")"
    )
  }

  private func assertNoVotingError() {
    let errorText = app.staticTexts["voting-error"]
    XCTAssertFalse(
      errorText.waitForExistence(timeout: 2),
      "Unexpected voting error: \(errorText.exists ? errorText.label : "unknown")"
    )
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
      scrollTarget.swipeDown()
      if element.waitForExistence(timeout: perSwipeTimeout) {
        return true
      }
    }
    return element.waitForExistence(timeout: perSwipeTimeout)
  }

  private func createGameThroughInviteFlow(
    admin: TestAdminClient,
    createdAfter: Date,
    playerCount: Int,
    wordLength: Int? = nil
  ) async throws -> TestAdminClient.Game {
    tapNewGameAndCreate(wordLength: wordLength, playerCount: playerCount)
    try selectInviteesAndSend(requiredInvitees: max(playerCount - 1, 0))
    let game = try await admin.waitForLatestGame(createdAfter: createdAfter, timeout: 20)
    createdGameID = game.id
    _ = try await admin.acceptInvites(gameID: game.id)
    return game
  }

  private func tapNewGameAndCreate(wordLength: Int? = nil, playerCount: Int = 2) {
    let newGameButton = app.buttons["new-game-button"]
    XCTAssertTrue(newGameButton.waitForExistence(timeout: 20))
    newGameButton.tap()

    let createButton = app.buttons["create-game-button"]
    XCTAssertTrue(createButton.waitForExistence(timeout: 10))

    let playerCountButton = app.buttons["\(playerCount) players"]
    XCTAssertTrue(
      playerCountButton.waitForExistence(timeout: 5),
      "Segment for \(playerCount) players should exist"
    )
    playerCountButton.tap()

    if let wordLength {
      let segment = app.buttons["\(wordLength) letters"]
      XCTAssertTrue(segment.waitForExistence(timeout: 5), "Segment for \(wordLength) letters should exist")
      segment.tap()
    }

    createButton.tap()
  }

  private func selectInviteesAndSend(requiredInvitees: Int) throws {
    let sendButton = app.buttons["send-invites-button"]
    XCTAssertTrue(sendButton.waitForExistence(timeout: 10), "Invite sheet should appear.")
    let inviteeRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "invitee-row-"))
    XCTAssertTrue(
      waitForInviteeRows(inviteeRows, timeout: 10),
      "Invitee rows failed to load. Verify debug matchmaking token and virtual players."
    )

    let preferredNames = Self.resolvePreferredInviteeNames()
    var selectedRowIDs = Set<String>()
    var selectedCount = 0
    for name in preferredNames where selectedCount < requiredInvitees {
      if let selectedRowID = selectInvitee(named: name, in: inviteeRows) {
        selectedRowIDs.insert(selectedRowID)
        selectedCount += 1
      }
    }

    if selectedCount < requiredInvitees {
      for index in 0..<inviteeRows.count where selectedCount < requiredInvitees {
        let row = inviteeRows.element(boundBy: index)
        guard row.exists else { continue }
        if selectedRowIDs.contains(row.identifier) {
          continue
        }
        row.tap()
        selectedRowIDs.insert(row.identifier)
        selectedCount += 1
      }
    }

    XCTAssertEqual(
      selectedCount,
      requiredInvitees,
      "Not enough invitees available to satisfy test requirements."
    )
    XCTAssertTrue(sendButton.isEnabled, "Send Invites should be enabled after selecting invitees.")
    sendButton.tap()
  }

  private func selectInvitee(named name: String, in rows: XCUIElementQuery) -> String? {
    for index in 0..<rows.count {
      let row = rows.element(boundBy: index)
      guard row.exists else { continue }
      if row.label.localizedStandardContains(name) {
        row.tap()
        return row.identifier
      }
    }
    let fallback = rows.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
    if fallback.waitForExistence(timeout: 1) {
      fallback.tap()
      return fallback.identifier
    }
    let textMatch = app.staticTexts[name].firstMatch
    if textMatch.waitForExistence(timeout: 1) {
      textMatch.tap()
      return textMatch.identifier
    }
    return nil
  }

  private func waitForInviteeRows(_ rows: XCUIElementQuery, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if rows.count > 0 {
        return true
      }
      if app.staticTexts["No players available."].exists {
        return false
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return rows.count > 0
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

  private func requireVirtualPlayer(
    from state: TestAdminClient.StateResponse
  ) throws -> TestAdminClient.StateResponse.Participant {
    if let virtualPlayer = state.participants.first(where: \.virtual) {
      return virtualPlayer
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 6, userInfo: [
      NSLocalizedDescriptionKey: "Virtual player not found in participants."
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
    if let token = normalizedToken(env["WORDSMOKE_TEST_ADMIN_TOKEN"]) {
      return token
    }
    throw NSError(domain: "WordsmokeLocalUITests", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Missing WORDSMOKE_TEST_ADMIN_TOKEN in environment."
    ])
  }

  private static func resolveDebugMatchmakingToken(fallback: String) -> String {
    let env = ProcessInfo.processInfo.environment
    return normalizedToken(env["WORDSMOKE_DEBUG_MATCHMAKING_TOKEN"]) ?? fallback
  }

  private static func resolvePreferredInviteeNames() -> [String] {
    let env = ProcessInfo.processInfo.environment
    if let rawValue = env["WORDSMOKE_UI_TEST_INVITEE_NAMES"] {
      let names = rawValue
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if !names.isEmpty {
        return names
      }
    }
    return defaultInviteeNames
  }

  private static func normalizedToken(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed != "__TEST_ADMIN_TOKEN__" else { return nil }
    return trimmed
  }

  private func launchApp(baseURL: URL, debugMatchmakingToken: String) {
    app.launchEnvironment["WORDSMOKE_UI_TESTS"] = "1"
    app.launchEnvironment["WORDSMOKE_BASE_URL"] = baseURL.absoluteString
    app.launchEnvironment["WORDSMOKE_DEBUG_MATCHMAKING_TOKEN"] = debugMatchmakingToken
    app.launch()
  }

  private func launchAppWithOnboardingReset(baseURL: URL, debugMatchmakingToken: String) {
    app.launchEnvironment["WORDSMOKE_UI_TESTS"] = "1"
    app.launchEnvironment["WORDSMOKE_BASE_URL"] = baseURL.absoluteString
    app.launchEnvironment["WORDSMOKE_DEBUG_MATCHMAKING_TOKEN"] = debugMatchmakingToken
    app.launchEnvironment["WORDSMOKE_RESET_ONBOARDING"] = "1"
    app.launch()
  }

  private func advanceOnboardingStep() {
    for label in ["Start Tour", "Next", "Finish"] {
      let button = app.buttons[label]
      if button.waitForExistence(timeout: 2) {
        button.tap()
        return
      }
    }
  }

  // MARK: - Onboarding Flow Tests

  func testOnboardingWaitsForGameStart() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchAppWithOnboardingReset(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    // Create a 2-player game but don't accept invites yet (stays in waiting)
    tapNewGameAndCreate(playerCount: 2)
    try selectInviteesAndSend(requiredInvitees: 1)

    let createdAfter = Date().addingTimeInterval(-5)
    let game = try await admin.waitForLatestGame(createdAfter: createdAfter, timeout: 20)
    createdGameID = game.id

    // Wait a bit and confirm onboarding does NOT appear while waiting
    let skipButton = app.buttons["Skip Tour"]
    XCTAssertFalse(skipButton.waitForExistence(timeout: 3), "Onboarding should not show during waiting status")

    // Accept invites → game starts
    _ = try await admin.acceptInvites(gameID: game.id)

    // Onboarding should now appear
    let welcomeText = app.staticTexts["Welcome to Wordsmoke"]
    XCTAssertTrue(welcomeText.waitForExistence(timeout: 15), "Onboarding should appear after game starts")

    // Dismiss onboarding
    dismissOnboardingIfPresent()
  }

  func testVotingOnboardingAfterTwoPlayerGame() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchAppWithOnboardingReset(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    // Game 1: 2-player game — walk through submission onboarding then complete round
    let createdAfter1 = Date()
    let game1 = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter1,
      playerCount: 2,
      wordLength: 4
    )
    createdGameIDs.append(game1.id)

    let roundOneState = try await admin.waitForRound(gameID: game1.id, number: 1, timeout: 30)
    let roundOneID = try requireRoundID(from: roundOneState)
    let virtualPlayer = try requireVirtualPlayer(from: roundOneState)

    // Walk through onboarding: tap Start Tour, then Next through each step.
    // Wait for each onboarding button directly — it only appears when the step
    // is eligible and its target is visible, so this is the synchronization point.
    let startTourButton = app.buttons["Start Tour"]
    XCTAssertTrue(startTourButton.waitForExistence(timeout: 15), "Start Tour should appear")
    startTourButton.tap()

    let nextButton = app.buttons["Next"]
    for step in 1...3 {
      XCTAssertTrue(
        nextButton.waitForExistence(timeout: 15),
        "Next button should appear for onboarding step \(step)"
      )
      nextButton.tap()
    }

    // After advancing past submitGuess (step 4), onboarding auto-completes for 2-player
    let skipButtonAfter = app.buttons["Skip Tour"]
    XCTAssertFalse(skipButtonAfter.waitForExistence(timeout: 3), "Onboarding should end after submit in 2-player game")

    // Complete round 1
    let wordsRound1 = try await admin.fetchWords(gameID: game1.id, excludeGoal: true)
    try submitGuess(word: wordsRound1.randomGuessWord, phrasePrefix: "go")
    _ = try await admin.createSubmission(
      gameID: game1.id,
      roundID: roundOneID,
      playerID: virtualPlayer.id,
      auto: true,
      excludeGoal: true
    )

    // Wait for round 2 to open (confirms round 1 closed) then navigate back to lobby
    _ = try await admin.waitForRound(gameID: game1.id, number: 2, timeout: 30)
    app.navigationBars.buttons.firstMatch.tap()

    // Wait for lobby to appear before creating next game
    let newGameButton = app.buttons["new-game-button"]
    XCTAssertTrue(newGameButton.waitForExistence(timeout: 10), "Lobby should appear after navigating back")

    // Game 2: 3-player game — voting onboarding should trigger
    let createdAfter2 = Date()
    let game2 = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter2,
      playerCount: 3
    )
    createdGameIDs.append(game2.id)

    let round2State = try await admin.waitForRound(gameID: game2.id, number: 1, timeout: 30)
    let round2ID = try requireRoundID(from: round2State)
    let virtualPlayerIDs = round2State.participants.filter(\.virtual).map(\.id)

    // Submit guess in 3-player game
    let wordsRound2 = try await admin.fetchWords(gameID: game2.id, excludeGoal: true)
    try submitGuess(word: wordsRound2.randomGuessWord, phrasePrefix: "ok")

    for playerID in virtualPlayerIDs {
      _ = try await admin.createSubmission(
        gameID: game2.id,
        roundID: round2ID,
        playerID: playerID,
        auto: true,
        excludeGoal: true
      )
    }

    // Wait for voting phase
    _ = try await admin.waitForRoundStatus(gameID: game2.id, status: "voting", timeout: 20)

    // Voting onboarding should appear
    let pickFavoriteText = app.staticTexts["Pick a favorite"]
    XCTAssertTrue(pickFavoriteText.waitForExistence(timeout: 15), "Voting onboarding should appear in 3-player game")

    // Dismiss voting onboarding
    dismissOnboardingIfPresent()
  }

  func testOnboardingRerunShowsFullFlow() async throws {
    let baseURL = Self.resolveBaseURL()
    let adminToken = try Self.resolveAdminToken()
    let debugMatchmakingToken = Self.resolveDebugMatchmakingToken(fallback: adminToken)
    let admin = TestAdminClient(baseURL: baseURL, token: adminToken)
    adminClient = admin

    launchAppWithOnboardingReset(baseURL: baseURL, debugMatchmakingToken: debugMatchmakingToken)

    // Create a 2-player game and dismiss onboarding
    let createdAfter = Date()
    let _ = try await createGameThroughInviteFlow(
      admin: admin,
      createdAfter: createdAfter,
      playerCount: 2,
      wordLength: 4
    )

    dismissOnboardingIfPresent(timeout: 10)

    // Navigate back to the lobby where the settings button lives
    app.navigationBars.buttons.firstMatch.tap()

    // Navigate to Settings and toggle Introduction Flow on
    let settingsButton = app.buttons["settings-button"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
    settingsButton.tap()

    let onboardingToggle = app.switches["onboarding-toggle"]
    XCTAssertTrue(onboardingToggle.waitForExistence(timeout: 10))
    // Tap the right side of the toggle where the switch control lives
    let switchControl = onboardingToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
    switchControl.tap()

    // Dismiss settings sheet
    let doneButton = app.buttons["Done"]
    if doneButton.waitForExistence(timeout: 3) {
      doneButton.tap()
    }

    // Re-enter the game room to trigger onboarding
    let gameRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "active-game-")).firstMatch
    XCTAssertTrue(gameRow.waitForExistence(timeout: 10), "Active game row should appear in lobby")
    gameRow.tap()

    // Onboarding should restart with full flow
    let welcomeText = app.staticTexts["Welcome to Wordsmoke"]
    XCTAssertTrue(welcomeText.waitForExistence(timeout: 10), "Full onboarding should restart after settings toggle")

    // Dismiss onboarding
    dismissOnboardingIfPresent()
  }
}
