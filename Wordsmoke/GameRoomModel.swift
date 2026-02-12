import Foundation
import Observation

struct ReportablePhrase: Identifiable, Hashable, Sendable {
  let id: String
  let roundNumber: Int
  let playerID: String
  let playerName: String
  let phrase: String
}

struct WaitingRoomPlayerStatus: Identifiable, Equatable, Sendable {
  var id: String { playerID }
  let playerID: String
  let displayName: String
  let statusText: String
  let highlightsAsPositive: Bool
}

@MainActor
@Observable
final class GameRoomModel {
  private(set) var game: GameResponse
  private let apiClient: APIClient
  let localPlayerID: String
  var round: RoundPayload?
  var completedRounds: [RoundPayload] = []
  var guessWord = ""
  var phrase = ""
  var errorMessage: String?
  var isGuessValid = false
  var isPhraseValid = false
  private var lastValidatedGuess = ""
  private var lastRoundID: String?
  var selectedFavoriteID: String?
  var selectedLeastID: String?
  var voteSubmitted = false
  var isBusy = false
  private var cableClient: ActionCableClient?
  private var cableReconnectCount = 0

  init(game: GameResponse, apiClient: APIClient, localPlayerID: String) {
    self.game = game
    self.apiClient = apiClient
    self.localPlayerID = localPlayerID
  }
}

extension GameRoomModel {
  func connectToGameChannel() {
    disconnectFromGameChannel()

    guard let cableURL = buildCableURL() else { return }

    cableReconnectCount = 0

    let client = ActionCableClient(url: cableURL)
    client.onMessage = { [weak self] message in
      guard let self else { return }
      self.cableReconnectCount = 0
      guard message["type"] as? String == "game_updated" else { return }
      Task { [weak self] in
        await self?.refreshRound(logStrategy: .changesOnly, setBusy: false)
      }
    }
    client.onDisconnect = { [weak self] in
      Task { [weak self] in
        guard let self, self.cableClient != nil else { return }
        let attempt = self.cableReconnectCount
        guard attempt < 5 else { return }
        self.cableReconnectCount = attempt + 1
        let delay = min(2.0 * pow(2.0, Double(attempt)), 30.0)
        try? await Task.sleep(for: .seconds(delay))
        guard self.cableClient != nil else { return }
        self.connectToGameChannel()
      }
    }
    cableClient = client
    client.connect()

    let identifier = "{\"channel\":\"GameChannel\",\"game_id\":\"\(game.id)\"}"
    client.subscribe(identifier: identifier)
  }

  func disconnectFromGameChannel() {
    cableClient?.disconnect()
    cableClient = nil
  }

  func updateGame(_ game: GameResponse) {
    applyGameIfChanged(game)
  }

  func refreshRound(logStrategy: APIClient.LogStrategy = .always, setBusy: Bool = true) async {
    if setBusy {
      guard !isBusy else { return }
      isBusy = true
    }
    defer {
      if setBusy {
        isBusy = false
      }
    }

    do {
      let updatedGame = try await apiClient.fetchGame(id: game.id, logStrategy: logStrategy)
      applyGameIfChanged(updatedGame)
      // Keep completed rounds cached while refreshing to avoid UI flashing.
      let currentRoundID = game.currentRoundID
      let roundSummaries = game.rounds ?? []
      try await updateCompletedRounds(from: roundSummaries, logStrategy: logStrategy)
      try await updateCurrentRound(currentRoundID: currentRoundID, logStrategy: logStrategy)
      if errorMessage != nil {
        errorMessage = nil
      }
    } catch {
      let message = error.localizedDescription
      if errorMessage != message {
        errorMessage = message
      }
    }
  }

  func submitGuess() async {
    guard let roundID = game.currentRoundID else { return }
    guard isGuessValid, isPhraseValid else { return }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      _ = try await apiClient.submitGuess(
        gameID: game.id,
        roundID: roundID,
        guessWord: guessWord,
        phrase: phrase
      )
      guessWord = ""
      phrase = ""
      isGuessValid = false
      isPhraseValid = false
      errorMessage = nil
      await refreshRound(logStrategy: .always, setBusy: false)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func submitVotes() async {
    guard let roundID = game.currentRoundID else { return }
    guard let favoriteID = selectedFavoriteID, let leastID = selectedLeastID else {
      errorMessage = "Select a favorite and a least favorite phrase."
      return
    }
    guard favoriteID != leastID else {
      errorMessage = "Favorite and least favorite must be different."
      return
    }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let response = try await apiClient.submitPhraseVote(
        gameID: game.id,
        roundID: roundID,
        favoriteID: favoriteID,
        leastID: leastID
      )
      voteSubmitted = true
      round = response.round
      errorMessage = nil
      await refreshRound(logStrategy: .always, setBusy: false)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func startGame() async {
    let playersCount = game.playersCount ?? game.participants?.count ?? 0
    if playersCount < 2 {
      errorMessage = "At least 2 players must join before starting."
      return
    }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let updatedGame = try await apiClient.updateGameStatus(id: game.id, status: "active")
      game = updatedGame
      errorMessage = nil
      await refreshRound(logStrategy: .always, setBusy: false)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func submitVirtualGuess(for playerID: String) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let response = try await apiClient.submitVirtualGuess(gameID: game.id, playerID: playerID)
      round = response.round
      errorMessage = nil
      await refreshRound(logStrategy: .always, setBusy: false)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func submitVirtualVote(for playerID: String) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let response = try await apiClient.submitVirtualVote(gameID: game.id, playerID: playerID)
      round = response.round
      errorMessage = nil
      await refreshRound(logStrategy: .always, setBusy: false)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func submitProblemWithGameReport(
    description: String,
    name: String?,
    email: String?
  ) async throws {
    let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDescription.isEmpty else {
      throw SupportReportValidationError(message: "Please describe the problem.")
    }

    let message = problemWithGameReportMessage(
      description: trimmedDescription,
      providedName: name,
      providedEmail: email
    )
    try await apiClient.submitSupportIssue(
      topic: "Problem with game",
      message: message,
      name: name,
      email: email
    )
  }

  func submitInappropriateContentReport(selectedPhrases: [ReportablePhrase]) async throws {
    guard !selectedPhrases.isEmpty else {
      throw SupportReportValidationError(message: "Select at least one phrase to report.")
    }

    let message = inappropriateContentReportMessage(selectedPhrases: selectedPhrases)
    try await apiClient.submitSupportIssue(
      topic: "Inappropriate Content",
      message: message,
      name: playerName(for: localPlayerID),
      email: nil
    )
  }
}

extension GameRoomModel {
  func waitingRoomPlayerStatuses() -> [WaitingRoomPlayerStatus] {
    guard let participants = game.participants else { return [] }

    let participantsByPlayerID = Dictionary(uniqueKeysWithValues: participants.map { ($0.player.id, $0) })
    let participantGCIDs = Set(participants.map(\.player.gameCenterPlayerID).filter { !$0.isEmpty })
    let invitedByPlayerID = Dictionary(uniqueKeysWithValues: (game.invitedPlayers ?? []).map { ($0.playerID, $0) })
    let hostPlayerID = participants.first(where: { $0.role == "host" })?.player.id

    var rowsByPlayerID: [String: WaitingRoomPlayerStatus] = [:]
    var coveredGCIDs: Set<String> = []

    if let hostPlayerID, let host = participantsByPlayerID[hostPlayerID] {
      rowsByPlayerID[hostPlayerID] = WaitingRoomPlayerStatus(
        playerID: hostPlayerID,
        displayName: host.player.displayName,
        statusText: "Host",
        highlightsAsPositive: true
      )
    }

    for invited in invitedByPlayerID.values {
      if invited.playerID == hostPlayerID {
        continue
      }
      let hasJoined = participantsByPlayerID[invited.playerID] != nil
        || participantGCIDs.contains(invited.playerID)
      rowsByPlayerID[invited.playerID] = WaitingRoomPlayerStatus(
        playerID: invited.playerID,
        displayName: invited.displayName,
        statusText: hasJoined ? "Joined" : "Invited",
        highlightsAsPositive: hasJoined
      )
      coveredGCIDs.insert(invited.playerID)
    }

    for participant in participants where participant.player.id != hostPlayerID {
      if rowsByPlayerID[participant.player.id] != nil {
        continue
      }
      if coveredGCIDs.contains(participant.player.gameCenterPlayerID) {
        continue
      }
      rowsByPlayerID[participant.player.id] = WaitingRoomPlayerStatus(
        playerID: participant.player.id,
        displayName: participant.player.displayName,
        statusText: "Joined",
        highlightsAsPositive: true
      )
    }

    return rowsByPlayerID.values.sorted { left, right in
      if left.playerID == hostPlayerID { return true }
      if right.playerID == hostPlayerID { return false }
      return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
    }
  }

  func hasPendingInvitedPlayers() -> Bool {
    guard let invitedPlayers = game.invitedPlayers else { return false }
    let participants = game.participants ?? []
    let joinedPlayerIDs = Set(participants.map(\.player.id))
    let joinedGCIDs = Set(participants.map(\.player.gameCenterPlayerID).filter { !$0.isEmpty })
    return invitedPlayers.contains {
      !($0.accepted || joinedPlayerIDs.contains($0.playerID) || joinedGCIDs.contains($0.playerID))
    }
  }

  func shouldConfirmEarlyStart() -> Bool {
    isHost() && hasPendingInvitedPlayers()
  }

  func isReadyToVote() -> Bool {
    guard let round else { return false }
    return round.stage == "voting" && !voteSubmitted
  }

  func canShowVoting() -> Bool {
    guard let round else { return false }
    return round.stage == "voting"
  }

  func hasSubmittedOwnGuess() -> Bool {
    guard let round else { return false }
    return ownSubmission(in: round)?.createdAt != nil
  }

  func ownSubmission(in round: RoundPayload) -> RoundSubmission? {
    round.submissions.first { $0.playerID == localPlayerID }
  }

  func otherSubmissions(in round: RoundPayload) -> [RoundSubmission] {
    round.submissions
      .filter { $0.playerID != localPlayerID }
      .sorted { left, right in
        let leftKey = votingShuffleKey(roundID: round.id, submissionID: left.id)
        let rightKey = votingShuffleKey(roundID: round.id, submissionID: right.id)
        if leftKey == rightKey {
          return left.id < right.id
        }
        return leftKey < rightKey
      }
  }

  func playerName(for playerID: String) -> String? {
    game.participants?.first(where: { $0.player.id == playerID })?.player.displayName
  }

  func isHost() -> Bool {
    game.participants?.first(where: { $0.player.id == localPlayerID })?.role == "host"
  }

  private func votingShuffleKey(roundID: String, submissionID: String) -> Int {
    var hasher = Hasher()
    hasher.combine(roundID)
    hasher.combine(localPlayerID)
    hasher.combine(submissionID)
    return hasher.finalize()
  }

  func playerScore(for playerID: String) -> Int {
    game.participants?.first(where: { $0.player.id == playerID })?.score ?? 0
  }

  func reportRounds() -> [RoundPayload] {
    var rounds = completedRounds
    if let round {
      rounds.append(round)
    }
    var seen = Set<String>()
    let unique = rounds.filter { seen.insert($0.id).inserted }
    return unique.sorted { $0.number < $1.number }
  }

  func orderedPlayerIDsForReport(in rounds: [RoundPayload]) -> [String] {
    if let participants = game.participants, !participants.isEmpty {
      var otherParticipants = participants.filter { $0.player.id != localPlayerID }
      otherParticipants.sort {
        $0.player.displayName.localizedStandardCompare($1.player.displayName) == .orderedAscending
      }
      var ordered = otherParticipants.map(\.player.id)
      if participants.contains(where: { $0.player.id == localPlayerID }) {
        ordered.append(localPlayerID)
      }
      return ordered
    }

    var nameLookup: [String: String] = [:]
    for round in rounds {
      for submission in round.submissions {
        nameLookup[submission.playerID] = submission.playerName
      }
    }

    var otherIDs = nameLookup.keys.filter { $0 != localPlayerID }
    otherIDs.sort {
      let leftName = nameLookup[$0] ?? $0
      let rightName = nameLookup[$1] ?? $1
      return leftName.localizedStandardCompare(rightName) == .orderedAscending
    }
    var ordered = otherIDs
    ordered.append(localPlayerID)
    return ordered
  }

  func winningRound() -> RoundPayload? {
    if let winningRoundNumber = game.winningRoundNumber {
      return completedRounds.first { $0.number == winningRoundNumber } ?? round
    }
    return completedRounds.last ?? round
  }

  func goalWord() -> String? {
    let rounds = reportRounds()
    for round in rounds {
      for submission in round.submissions {
        if let goal = submission.feedback?.goal, !goal.isEmpty {
          return goal
        }
      }
    }
    return nil
  }

  func playerName(for playerID: String, in rounds: [RoundPayload]) -> String? {
    if let name = playerName(for: playerID) {
      return name
    }
    for round in rounds {
      if let submission = round.submissions.first(where: { $0.playerID == playerID }) {
        return submission.playerName
      }
    }
    return nil
  }

  func isVirtualPlayer(_ playerID: String) -> Bool {
    guard let player = game.participants?.first(where: { $0.player.id == playerID })?.player else {
      return false
    }
    if let isVirtual = player.virtual {
      return isVirtual
    }
    return player.gameCenterPlayerID.hasPrefix("VIRTUAL-")
  }

  func reportablePhrases() -> [ReportablePhrase] {
    var seenSubmissionIDs = Set<String>()
    var phrases: [ReportablePhrase] = []

    for round in reportRounds() {
      for submission in round.submissions where submission.playerID != localPlayerID {
        guard let phrase = submission.phrase?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty else {
          continue
        }
        guard seenSubmissionIDs.insert(submission.id).inserted else {
          continue
        }
        phrases.append(
          ReportablePhrase(
            id: submission.id,
            roundNumber: round.number,
            playerID: submission.playerID,
            playerName: submission.playerName,
            phrase: phrase
          )
        )
      }
    }

    return phrases.sorted {
      if $0.roundNumber == $1.roundNumber {
        return $0.playerName.localizedStandardCompare($1.playerName) == .orderedAscending
      }
      return $0.roundNumber > $1.roundNumber
    }
  }

  func winnerIDs(for round: RoundPayload) -> [String] {
    let correct = round.submissions.filter { $0.correctGuess == true }
    guard !correct.isEmpty else { return [] }

    let topScore = correct.map { playerScore(for: $0.playerID) }.max() ?? 0
    return correct.filter { playerScore(for: $0.playerID) == topScore }.map { $0.playerID }
  }

  func toggleFavorite(for submission: RoundSubmission) {
    selectedFavoriteID = (selectedFavoriteID == submission.id) ? nil : submission.id
    if selectedLeastID == selectedFavoriteID {
      selectedLeastID = nil
    }
  }

  func toggleLeast(for submission: RoundSubmission) {
    selectedLeastID = (selectedLeastID == submission.id) ? nil : submission.id
    if selectedFavoriteID == selectedLeastID {
      selectedFavoriteID = nil
    }
  }

  func canSubmitVotes() -> Bool {
    guard let favoriteID = selectedFavoriteID, let leastID = selectedLeastID else { return false }
    return favoriteID != leastID
  }

  func problemWithGameReportMessage(
    description: String,
    providedName: String?,
    providedEmail: String?
  ) -> String {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    var lines = [
      description,
      "",
      "---",
      "report_type: Problem with game",
      "submitted_at: \(timestamp)",
      "game_id: \(game.id)",
      "player_id: \(localPlayerID)",
      "player_name: \(playerName(for: localPlayerID) ?? "Unknown")"
    ]

    let name = providedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty {
      lines.append("provided_name: \(name)")
    }

    let email = providedEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !email.isEmpty {
      lines.append("provided_email: \(email)")
    }

    return lines.joined(separator: "\n")
  }

  func inappropriateContentReportMessage(selectedPhrases: [ReportablePhrase]) -> String {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    var lines = [
      "A player reported inappropriate content.",
      "",
      "---",
      "report_type: Inappropriate Content",
      "submitted_at: \(timestamp)",
      "game_id: \(game.id)",
      "player_id: \(localPlayerID)",
      "player_name: \(playerName(for: localPlayerID) ?? "Unknown")",
      "selected_phrases:"
    ]

    for phrase in selectedPhrases.sorted(by: { $0.id < $1.id }) {
      lines.append(
        "- round=\(phrase.roundNumber) player_id=\(phrase.playerID) player_name=\"\(phrase.playerName)\" phrase=\"\(phrase.phrase)\""
      )
    }

    return lines.joined(separator: "\n")
  }

  func validateGuessWord() async {
    let trimmed = guessWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard trimmed.count == game.goalLength else {
      isGuessValid = false
      isPhraseValid = phraseContainsAllLetters(phrase: phrase, guessWord: trimmed)
      return
    }

    guard trimmed != lastValidatedGuess else {
      isPhraseValid = phraseContainsAllLetters(phrase: phrase, guessWord: trimmed)
      return
    }

    lastValidatedGuess = trimmed
    do {
      isGuessValid = try await apiClient.validateWord(trimmed)
    } catch {
      isGuessValid = false
      errorMessage = error.localizedDescription
    }
    isPhraseValid = phraseContainsAllLetters(phrase: phrase, guessWord: trimmed)
  }

  func validatePhrase() {
    let trimmed = guessWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    isPhraseValid = phraseContainsAllLetters(phrase: phrase, guessWord: trimmed)
  }

  private func phraseContainsAllLetters(phrase: String, guessWord: String) -> Bool {
    guard !guessWord.isEmpty else { return false }
    let phraseLower = phrase.lowercased()
    let required = Set(guessWord)
    return required.allSatisfy { phraseLower.contains($0) }
  }

  private func resetRoundStateIfNeeded(roundID: String?) {
    guard roundID != lastRoundID else { return }

    selectedFavoriteID = nil
    selectedLeastID = nil
    voteSubmitted = false
    guessWord = ""
    phrase = ""
    isGuessValid = false
    isPhraseValid = false
    lastRoundID = roundID
  }

  private func updateCompletedRounds(
    from roundSummaries: [GameRoundSummary],
    logStrategy: APIClient.LogStrategy
  ) async throws {
    let closedRoundIDs = roundSummaries.filter { $0.status == "closed" }.map(\.id)
    guard !closedRoundIDs.isEmpty else { return }

    var fetchedRounds = completedRounds
    let shouldRefreshAll = game.status == "completed"
    for roundID in closedRoundIDs {
      if !shouldRefreshAll, fetchedRounds.first(where: { $0.id == roundID }) != nil {
        continue
      }
      let response = try await apiClient.fetchRound(
        gameID: game.id,
        roundID: roundID,
        logStrategy: logStrategy,
        forceRefresh: shouldRefreshAll
      )
      if let index = fetchedRounds.firstIndex(where: { $0.id == roundID }) {
        fetchedRounds[index] = response.round
      } else {
        fetchedRounds.append(response.round)
      }
    }
    let sortedRounds = fetchedRounds.sorted { $0.number < $1.number }
    if sortedRounds != completedRounds {
      completedRounds = sortedRounds
    }
  }

  private func updateCurrentRound(
    currentRoundID: String?,
    logStrategy: APIClient.LogStrategy
  ) async throws {
    guard let currentRoundID else {
      if round != nil {
        round = nil
      }
      resetRoundStateIfNeeded(roundID: nil)
      return
    }

    let response = try await apiClient.fetchRound(
      gameID: game.id,
      roundID: currentRoundID,
      logStrategy: logStrategy
    )
    if response.round.status == "closed" {
      if completedRounds.first(where: { $0.id == response.round.id }) == nil {
        completedRounds.append(response.round)
        completedRounds.sort { $0.number < $1.number }
      }
      if round != nil {
        round = nil
      }
      resetRoundStateIfNeeded(roundID: nil)
    } else {
      if round != response.round {
        round = response.round
      }
      resetRoundStateIfNeeded(roundID: currentRoundID)
      syncVoteSubmittedFromServer(response.round)
    }
  }

  private func applyGameIfChanged(_ updatedGame: GameResponse) {
    var merged = updatedGame
    if merged.invitedPlayers == nil, let existing = game.invitedPlayers {
      merged.invitedPlayers = existing
    }
    if game != merged {
      game = merged
    }
  }

  private func syncVoteSubmittedFromServer(_ round: RoundPayload) {
    guard round.status == "voting" else { return }
    // The server sets stage to "reveal" once the viewer has voted;
    // it's "voting" only while the viewer's vote is still missing.
    if round.stage != "voting" && !voteSubmitted {
      voteSubmitted = true
    }
  }

  private func buildCableURL() -> URL? {
    guard let token = apiClient.authToken else { return nil }
    guard var components = URLComponents(url: apiClient.baseURL, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.scheme = (components.scheme == "https") ? "wss" : "ws"
    components.path = "/cable"
    components.queryItems = [URLQueryItem(name: "token", value: token)]
    return components.url
  }

}

private struct SupportReportValidationError: LocalizedError {
  let message: String

  var errorDescription: String? { message }
}
