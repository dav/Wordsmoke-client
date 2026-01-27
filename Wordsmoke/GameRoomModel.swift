import Foundation
import Observation

@MainActor
@Observable
final class GameRoomModel {
  private(set) var game: GameResponse
  private let apiClient: APIClient
  let localPlayerID: String
  var round: RoundPayload?
  var completedRound: RoundPayload?
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

  init(game: GameResponse, apiClient: APIClient, localPlayerID: String) {
    self.game = game
    self.apiClient = apiClient
    self.localPlayerID = localPlayerID
  }

  func updateGame(_ game: GameResponse) {
    self.game = game
  }

  func refreshRound() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let updatedGame = try await apiClient.fetchGame(id: game.id)
      let previousRoundID = round?.id
      game = updatedGame

      guard let currentRoundID = game.currentRoundID else {
        if let previousRoundID {
          let previousResponse = try await apiClient.fetchRound(gameID: game.id, roundID: previousRoundID)
          completedRound = previousResponse.round
          round = nil
        }
        resetRoundStateIfNeeded(roundID: nil)
        errorMessage = nil
        return
      }

      if let previousRoundID, previousRoundID != currentRoundID {
        let completedResponse = try await apiClient.fetchRound(gameID: game.id, roundID: previousRoundID)
        completedRound = completedResponse.round

        let currentResponse = try await apiClient.fetchRound(gameID: game.id, roundID: currentRoundID)
        round = currentResponse.round
        resetRoundStateIfNeeded(roundID: currentRoundID)
      } else {
        let response = try await apiClient.fetchRound(gameID: game.id, roundID: currentRoundID)
        round = response.round
        if response.round.stage == "reveal" {
          completedRound = response.round
        } else if completedRound?.id != response.round.id {
          completedRound = nil
        }
        resetRoundStateIfNeeded(roundID: currentRoundID)
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
      if response.round.stage == "reveal" {
        completedRound = response.round
      }
      errorMessage = nil
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
