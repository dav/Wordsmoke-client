import SwiftUI

struct GameRoomView: View {
  @Bindable var model: GameRoomModel
  @Environment(\.appTheme) private var theme
  @Environment(\.debugEnabled) private var showDebug

  var body: some View {
    Form {
      Section("Status") {
        Text("Status: \(model.game.status)")
        if model.game.status == "waiting" {
          Button("Start Game") {
            Task {
              await model.startGame()
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled((model.game.playersCount ?? 0) < 2 || model.isBusy)
        }
      }

      if model.game.status == "waiting", let participants = model.game.participants {
        Section("Players") {
          ForEach(participants, id: \.id) { participant in
            HStack {
              Text(participant.player.displayName)
              Spacer()
              Text(participant.role)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if !model.completedRounds.isEmpty {
        ForEach(model.completedRounds) { completedRound in
          Section("Round \(completedRound.number)") {
            roundReport(for: completedRound)
          }
        }
      }

      if let round = model.round {
        Section("Round \(round.number)") {
          if shouldShowSubmissionForm(for: round) {
            submissionForm()
            if round.stage == "waiting_submissions" {
              playerStatusList(for: round)
            }
          } else {
            roundReport(for: round)
          }
        }
      } else if model.completedRounds.isEmpty {
        Section("Round Report") {
          Text("No round data yet.")
            .foregroundStyle(.secondary)
        }
      }

      if shouldShowRefreshButton && showDebug {
        Section {
          Button("Refresh Round") {
            Task {
              await model.refreshRound()
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .navigationTitle("Game \(model.game.joinCode)")
    .scrollContentBackground(.hidden)
    .listStyle(.insetGrouped)
    .listRowBackground(theme.cardBackground)
    .background(theme.background)
    .tint(theme.accent)
    .task {
      if model.round == nil {
        await model.refreshRound()
      }
    }
    .onAppear {
      model.startPolling()
    }
    .onDisappear {
      model.stopPolling()
    }
  }

  private var shouldShowRefreshButton: Bool {
    model.round != nil
  }

  private func shouldShowSubmissionForm(for round: RoundPayload) -> Bool {
    model.ownSubmission(in: round)?.createdAt == nil
  }

  @ViewBuilder
  private func submissionForm() -> some View {
    TextField("Guess word", text: $model.guessWord)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .textContentType(.oneTimeCode)
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
    Text("\(model.phrase.count)/\(model.game.goalLength * 4)")
      .font(.caption)
      .foregroundStyle(.secondary)
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

  @ViewBuilder
  private func roundReport(for round: RoundPayload) -> some View {
    switch round.stage {
    case "waiting_submissions":
      Text("Waiting for all submissions.")
        .foregroundStyle(.secondary)
      if let own = model.ownSubmission(in: round) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Your played")
            .font(.headline)
          if let phrase = own.phrase {
            Text(phrase)
          }
          if let marks = own.marks, let guessWord = own.guessWord {
            MarksView(
              marks: marks,
              letters: guessWord.map { String($0) },
              size: 36
            )
          }
        }
      }

      playerStatusList(for: round)
    case "voting":
      if model.hasSubmittedOwnGuess() == false {
        Text("Waiting on your submission.")
          .foregroundStyle(.secondary)
      } else {
        if model.game.playersCount ?? 0 >= 3 {
          VStack(alignment: .leading, spacing: 6) {
            Text("Votes")
              .font(.headline)
            ForEach(round.submissions) { submission in
              HStack {
                Text(submission.playerName)
                Spacer()
                if showDebug,
                   (submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID)),
                   submission.voted != true {
                  Button("Vote") {
                    Task {
                      await model.submitVirtualVote(for: submission.playerID)
                    }
                  }
                  .buttonStyle(.bordered)
                  .tint(theme.accent)
                }
                if submission.voted == true {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                } else {
                  Image(systemName: "clock")
                    .foregroundStyle(.orange)
                }
              }
            }
          }
          Divider()
        }

        if let own = model.ownSubmission(in: round) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Your report")
              .font(.headline)
            if let phrase = own.phrase {
              Text(phrase)
            }
            if let marks = own.marks, let guessWord = own.guessWord {
              MarksView(
                marks: marks,
                letters: guessWord.map { String($0) },
                size: 36
              )
            }
          }
        }

        Divider()

        Text("Other players’ phrases")
          .font(.headline)
        ForEach(model.otherSubmissions(in: round)) { submission in
          VStack(alignment: .leading, spacing: 8) {
            if let phrase = submission.phrase {
              Text(phrase)
            }
            HStack(spacing: 12) {
              Button("", systemImage: model.selectedFavoriteID == submission.id ? "hand.thumbsup.fill" : "hand.thumbsup") {
                model.toggleFavorite(for: submission)
              }
              .buttonStyle(.bordered)

              Button("", systemImage: model.selectedLeastID == submission.id ? "hand.thumbsdown.fill" : "hand.thumbsdown") {
                model.toggleLeast(for: submission)
              }
              .buttonStyle(.bordered)

              if showDebug,
                 (submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID)),
                 submission.voted != true {
                Button("Vote") {
                  Task {
                    await model.submitVirtualVote(for: submission.playerID)
                  }
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
              }
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
      if !round.submissions.isEmpty {
        let isFinalRound = model.game.status == "completed" && model.completedRounds.last?.id == round.id
        let winnerIDs = isFinalRound ? model.winnerIDs(for: round) : []
        let sortedSubmissions = round.submissions.sorted {
          if isFinalRound {
            let leftWinner = winnerIDs.contains($0.playerID)
            let rightWinner = winnerIDs.contains($1.playerID)
            if leftWinner != rightWinner {
              return leftWinner && !rightWinner
            }
            let leftScore = model.playerScore(for: $0.playerID)
            let rightScore = model.playerScore(for: $1.playerID)
            if leftScore != rightScore {
              return leftScore > rightScore
            }
          }
          return $0.playerName < $1.playerName
        }

        ForEach(sortedSubmissions) { submission in
          VStack(alignment: .leading, spacing: 6) {
            let isLocal = submission.playerID == model.localPlayerID
            HStack {
              if isFinalRound && winnerIDs.contains(submission.playerID) {
                Text("🏆")
              }
              Text(submission.playerName)
                .bold()
              Spacer()
              if round.status == "voting",
                 showDebug,
                 (submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID)),
                 submission.voted != true {
                Button("Vote") {
                  Task {
                    await model.submitVirtualVote(for: submission.playerID)
                  }
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
              }
              if round.status == "voting" {
                if submission.voted == true {
                  Text("voted")
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                  Text("voting")
                    .font(.caption)
                    .foregroundStyle(.red)
                }
              }
              if submission.correctGuess == true {
                Text("Correct")
                  .foregroundStyle(.green)
              }
            }
            if let phrase = submission.phrase {
              Text(phrase)
            }
            if let marks = submission.marks {
              MarksView(
                marks: marks,
                letters: isLocal ? submission.guessWord?.map { String($0) } : nil,
                size: 36
              )
            }
          }
        }
      } else {
        Text("No submissions yet.")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func playerStatusList(for round: RoundPayload) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Players")
        .font(.headline)
      ForEach(round.submissions) { submission in
        HStack {
          Text(submission.playerName)
          Spacer()
          if showDebug,
             (submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID)),
             submission.createdAt == nil {
            Button("Guess") {
              Task {
                await model.submitVirtualGuess(for: submission.playerID)
              }
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
          }
          if submission.createdAt != nil {
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

}
