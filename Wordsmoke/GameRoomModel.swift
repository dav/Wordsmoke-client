import Foundation
import Observation

@MainActor
@Observable
final class GameRoomModel {
  private(set) var game: GameResponse
  private let apiClient: APIClient
  var round: RoundResponse?
  var guessWord = ""
  var phrase = ""
  var errorMessage: String?
  var isBusy = false

  init(game: GameResponse, apiClient: APIClient) {
    self.game = game
    self.apiClient = apiClient
  }

  func updateGame(_ game: GameResponse) {
    self.game = game
  }

  func refreshRound() async {
    guard let roundID = game.currentRoundID else { return }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      round = try await apiClient.fetchRound(gameID: game.id, roundID: roundID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func submitGuess() async {
    guard let roundID = game.currentRoundID else { return }
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      _ = try await apiClient.submitGuess(gameID: game.id, roundID: roundID, guessWord: guessWord, phrase: phrase)
      guessWord = ""
      phrase = ""
      errorMessage = nil
      await refreshRound()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
