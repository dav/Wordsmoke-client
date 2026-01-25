import SwiftUI

struct GameRoomView: View {
  @Bindable var model: GameRoomModel

  var body: some View {
    Form {
      Section("Round") {
        Text("Status: \(model.game.status)")
        if let round = model.round {
          Text("Round \(round.number) — \(round.status)")
          Text("Votes: \(round.phraseVotesCount)")
        } else {
          Text("No round loaded")
            .foregroundStyle(.secondary)
        }
        Button("Refresh Round") {
          Task {
            await model.refreshRound()
          }
        }
        .buttonStyle(.bordered)
      }

      Section("Submit Guess") {
        TextField("Guess word", text: $model.guessWord)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onChange(of: model.guessWord) { _, _ in
            Task {
              await model.validateGuessWord()
            }
          }
        TextField("Phrase", text: $model.phrase)
          .textInputAutocapitalization(.sentences)
          .onChange(of: model.phrase) { _, _ in
            model.validatePhrase()
          }
        Button("Submit Guess") {
          Task {
            await model.submitGuess()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy || !model.isGuessValid || !model.isPhraseValid)

        if let errorMessage = model.errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
        }

        if !model.guessWord.isEmpty && !model.isGuessValid {
          Text("Guess word must be valid and \(model.game.goalLength) letters.")
            .foregroundStyle(.red)
        }

        if !model.phrase.isEmpty && !model.isPhraseValid {
          Text("Phrase must include every letter from the guess word.")
            .foregroundStyle(.red)
        }
      }

      Section("Round Report") {
        if let round = model.round {
          switch round.stage {
          case "waiting_submissions":
            Text("Waiting for all submissions.")
              .foregroundStyle(.secondary)
            if let own = model.ownSubmission() {
              VStack(alignment: .leading, spacing: 6) {
                Text("Your report")
                  .font(.headline)
                Text(own.phrase)
                MarksView(
                  marks: own.marks,
                  letters: own.guessWord.map { String($0) },
                  size: 36
                )
              }
            }

            if let players = round.players {
              VStack(alignment: .leading, spacing: 6) {
                Text("Players")
                  .font(.headline)
                ForEach(players) { player in
                  HStack {
                    Text(player.name)
                    Spacer()
                    if round.submittedPlayerIDs?.contains(player.id) == true {
                      Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    } else {
                      Image(systemName: "clock")
                        .foregroundStyle(.orange)
                    }
                  }
                }
              }
            }
          case "voting":
            if model.hasSubmittedOwnGuess() == false {
              Text("Waiting on your submission.")
                .foregroundStyle(.secondary)
            } else {
              if let own = model.ownSubmission() {
                VStack(alignment: .leading, spacing: 6) {
                  Text("Your report")
                    .font(.headline)
                  Text(own.phrase)
                  MarksView(
                    marks: own.marks,
                    letters: own.guessWord.map { String($0) },
                    size: 36
                  )
                }
              }

              Divider()

              Text("Other players’ phrases")
                .font(.headline)
              ForEach(model.orderedAnonymousPhrases()) { phrase in
                VStack(alignment: .leading, spacing: 8) {
                  Text(phrase.phrase)
                  HStack(spacing: 12) {
                    Button("", systemImage: model.selectedFavoriteID == phrase.id ? "hand.thumbsup.fill" : "hand.thumbsup") {
                      model.selectedFavoriteID = (model.selectedFavoriteID == phrase.id) ? nil : phrase.id
                      if model.selectedLeastID == model.selectedFavoriteID {
                        model.selectedLeastID = nil
                      }
                    }
                    .buttonStyle(.bordered)

                    Button("", systemImage: model.selectedLeastID == phrase.id ? "hand.thumbsdown.fill" : "hand.thumbsdown") {
                      model.selectedLeastID = (model.selectedLeastID == phrase.id) ? nil : phrase.id
                      if model.selectedLeastID == model.selectedFavoriteID {
                        model.selectedFavoriteID = nil
                      }
                    }
                    .buttonStyle(.bordered)
                  }
                }
              }

              Button("Submit Votes") {
                Task {
                  await model.submitVotes()
                }
              }
              .buttonStyle(.borderedProminent)
              .disabled(!model.canSubmitVotes() || model.isBusy)
            }
          default:
            if let submissions = round.submissions, !submissions.isEmpty {
              ForEach(submissions) { submission in
                VStack(alignment: .leading, spacing: 6) {
                  let isLocal = submission.playerID == model.localPlayerID
                  HStack {
                    Text(submission.playerName)
                      .bold()
                    if submission.correctGuess == true {
                      Text("Correct")
                        .foregroundStyle(.green)
                    }
                  }
                  Text(submission.phrase)
                  MarksView(
                    marks: submission.marks,
                    letters: isLocal ? submission.guessWord.map { String($0) } : nil,
                    size: 36
                  )
                }
              }
            } else {
              Text("No submissions yet.")
                .foregroundStyle(.secondary)
            }
          }
        } else {
          Text("No round data yet.")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Game")
    .task {
      if model.round == nil {
        await model.refreshRound()
      }
    }
  }
}
