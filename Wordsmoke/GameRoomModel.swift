import Foundation
import Observation

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
  private var pollingTask: Task<Void, Never>?

  init(game: GameResponse, apiClient: APIClient, localPlayerID: String) {
    self.game = game
    self.apiClient = apiClient
    self.localPlayerID = localPlayerID
  }
}

extension GameRoomModel {
  func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.refreshRound(logStrategy: .changesOnly, setBusy: false)
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  func updateGame(_ game: GameResponse) {
    self.game = game
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
      game = updatedGame
      if game.status == "completed" {
        completedRounds = []
      }
      let currentRoundID = game.currentRoundID
      let roundSummaries = game.rounds ?? []
      try await updateCompletedRounds(from: roundSummaries, logStrategy: logStrategy)
      try await updateCurrentRound(currentRoundID: currentRoundID, logStrategy: logStrategy)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
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
}

extension GameRoomModel {
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
    round.submissions.filter { $0.playerID != localPlayerID }
  }

  func playerName(for playerID: String) -> String? {
    game.participants?.first(where: { $0.player.id == playerID })?.player.displayName
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
    completedRounds = fetchedRounds.sorted { $0.number < $1.number }
  }

  private func updateCurrentRound(
    currentRoundID: String?,
    logStrategy: APIClient.LogStrategy
  ) async throws {
    guard let currentRoundID else {
      round = nil
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
      round = nil
      resetRoundStateIfNeeded(roundID: nil)
    } else {
      round = response.round
      resetRoundStateIfNeeded(roundID: currentRoundID)
    }
  }
}
