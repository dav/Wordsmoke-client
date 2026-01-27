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

  func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.refreshRound(logStrategy: .changesOnly)
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

  func refreshRound(logStrategy: APIClient.LogStrategy = .always) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let updatedGame = try await apiClient.fetchGame(id: game.id, logStrategy: logStrategy)
      game = updatedGame
      let currentRoundID = game.currentRoundID
      let roundSummaries = game.rounds ?? []
      let closedRoundIDs = roundSummaries.filter { $0.status == "closed" }.map(\.id)

      if !closedRoundIDs.isEmpty {
        var fetchedRounds = completedRounds
        for roundID in closedRoundIDs where fetchedRounds.first(where: { $0.id == roundID }) == nil {
          let response = try await apiClient.fetchRound(gameID: game.id, roundID: roundID, logStrategy: logStrategy)
          fetchedRounds.append(response.round)
        }
        completedRounds = fetchedRounds.sorted { $0.number < $1.number }
      }

      if let currentRoundID {
        let response = try await apiClient.fetchRound(gameID: game.id, roundID: currentRoundID, logStrategy: logStrategy)
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
      } else {
        round = nil
        resetRoundStateIfNeeded(roundID: nil)
      }
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
      _ = try await apiClient.submitGuess(gameID: game.id, roundID: roundID, guessWord: guessWord, phrase: phrase)
      guessWord = ""
      phrase = ""
      isGuessValid = false
      isPhraseValid = false
      errorMessage = nil
      await refreshRound()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func submitVotes() async {
    guard let roundID = game.currentRoundID else { return }
    guard let favoriteID = selectedFavoriteID, let leastID = selectedLeastID else { return }
    guard favoriteID != leastID else { return }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let response = try await apiClient.submitPhraseVote(gameID: game.id, roundID: roundID, favoriteID: favoriteID, leastID: leastID)
      voteSubmitted = true
      round = response.round
      errorMessage = nil
      await refreshRound()
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
      await refreshRound()
    } catch {
      errorMessage = error.localizedDescription
    }
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
    round.submissions.filter { $0.playerID != localPlayerID }
  }

  func playerName(for playerID: String) -> String? {
    game.participants?.first(where: { $0.player.id == playerID })?.player.displayName
  }

  func playerScore(for playerID: String) -> Int {
    game.participants?.first(where: { $0.player.id == playerID })?.score ?? 0
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
}
