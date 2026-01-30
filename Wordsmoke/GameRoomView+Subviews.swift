import SwiftUI

extension GameRoomView {
  var shouldShowRefreshButton: Bool {
    model.round != nil
  }

  func shouldShowSubmissionForm(for round: RoundPayload) -> Bool {
    model.ownSubmission(in: round)?.createdAt == nil
  }

  @ViewBuilder
  func submissionForm() -> some View {
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
  func roundReport(for round: RoundPayload) -> some View {
    switch round.stage {
    case "waiting_submissions":
      waitingSubmissionsReport(for: round)
    case "voting":
      votingReport(for: round)
    default:
      completedRoundReport(for: round)
    }
  }

  @ViewBuilder
  private func waitingSubmissionsReport(for round: RoundPayload) -> some View {
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
  }

  @ViewBuilder
  private func votingReport(for round: RoundPayload) -> some View {
    if !model.hasSubmittedOwnGuess() {
      Text("Waiting on your submission.")
        .foregroundStyle(.secondary)
    } else {
      votingStatusSection(for: round)
      votingOwnReportSection(for: round)
      votingOtherPhrasesSection(for: round)
      submitVotesButton
    }
  }

  @ViewBuilder
  private func votingStatusSection(for round: RoundPayload) -> some View {
    if model.game.playersCount ?? 0 >= 3 {
      VStack(alignment: .leading, spacing: 6) {
        Text("Votes")
          .font(.headline)
        ForEach(round.submissions) { submission in
          HStack {
            Text(submission.playerName)
            Spacer()
            if showDebug,
               submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID),
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
  }

  @ViewBuilder
  private func votingOwnReportSection(for round: RoundPayload) -> some View {
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
  }

  @ViewBuilder
  private func votingOtherPhrasesSection(for round: RoundPayload) -> some View {
    Divider()

    Text("Other players’ phrases")
      .font(.headline)
    ForEach(model.otherSubmissions(in: round)) { submission in
      VStack(alignment: .leading, spacing: 8) {
        if let phrase = submission.phrase {
          Text(phrase)
        }
        HStack(spacing: 12) {
          Button(
            "",
            systemImage: model.selectedFavoriteID == submission.id
              ? "hand.thumbsup.fill"
              : "hand.thumbsup"
          ) {
            model.toggleFavorite(for: submission)
          }
          .buttonStyle(.bordered)

          Button(
            "",
            systemImage: model.selectedLeastID == submission.id
              ? "hand.thumbsdown.fill"
              : "hand.thumbsdown"
          ) {
            model.toggleLeast(for: submission)
          }
          .buttonStyle(.bordered)

          if showDebug,
             submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID),
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
  }

  private var submitVotesButton: some View {
    Button("Submit Votes") {
      Task {
        await model.submitVotes()
      }
    }
    .buttonStyle(.borderedProminent)
    .disabled(!model.canSubmitVotes() || model.isBusy)
  }

  @ViewBuilder
  private func completedRoundReport(for round: RoundPayload) -> some View {
    if round.submissions.isEmpty {
      Text("No submissions yet.")
        .foregroundStyle(.secondary)
    } else {
      let isFinalRound = model.game.status == "completed" && model.completedRounds.last?.id == round.id
      let winnerIDs = isFinalRound ? model.winnerIDs(for: round) : []
      let sortedSubmissions = sortedSubmissions(for: round, isFinalRound: isFinalRound, winnerIDs: winnerIDs)

      ForEach(sortedSubmissions) { submission in
        completedSubmissionRow(
          submission,
          in: round,
          isFinalRound: isFinalRound,
          winnerIDs: winnerIDs
        )
      }
    }
  }

  private func sortedSubmissions(
    for round: RoundPayload,
    isFinalRound: Bool,
    winnerIDs: [String]
  ) -> [RoundSubmission] {
    round.submissions.sorted {
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
  }

  @ViewBuilder
  private func completedSubmissionRow(
    _ submission: RoundSubmission,
    in round: RoundPayload,
    isFinalRound: Bool,
    winnerIDs: [String]
  ) -> some View {
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
           submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID),
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

  @ViewBuilder
  func playerStatusList(for round: RoundPayload) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Players")
        .font(.headline)
      ForEach(round.submissions) { submission in
        HStack {
          Text(submission.playerName)
          Spacer()
          if showDebug,
             submission.playerVirtual ?? model.isVirtualPlayer(submission.playerID),
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
