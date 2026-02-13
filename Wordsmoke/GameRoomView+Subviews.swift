import SwiftUI

extension GameRoomView {
  var reportIssueSection: some View {
    Section {
      Button {
        isReportIssueSheetPresented = true
      } label: {
        Label {
          Text("Report Issue")
            .foregroundStyle(.red)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
      .tint(.red)
      .accessibilityIdentifier("report-issue-button")
    }
  }

  func shouldShowSubmissionForm(for round: RoundPayload) -> Bool {
    model.ownSubmission(in: round)?.createdAt == nil
  }

  @ViewBuilder
  func submissionForm() -> some View {
    TextField("Guess \(model.game.goalLength)-letter word", text: $model.guessWord)
      .focused($focusedField, equals: .guess)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .textContentType(.oneTimeCode)
      .accessibilityIdentifier("guess-word-field")
      .onboardingTarget(.guessWordField)
      .id(OnboardingTarget.guessWordField)
      .onChange(of: model.guessWord) { _, _ in
        Task {
          await model.validateGuessWord()
        }
      }
    TextField("Phrase", text: $model.phrase)
      .focused($focusedField, equals: .phrase)
      .textInputAutocapitalization(.sentences)
      .accessibilityIdentifier("phrase-field")
      .onboardingTarget(.phraseField)
      .id(OnboardingTarget.phraseField)
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
    .accessibilityIdentifier("submit-guess-button")
    .onboardingTarget(.submitGuessButton)
    .id(OnboardingTarget.submitGuessButton)
    .onAppear {
      isGuessSubmitButtonVisible = true
    }
    .onDisappear {
      isGuessSubmitButtonVisible = false
    }

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
  func playerReportContent(for playerID: String, rounds: [RoundPayload]) -> some View {
    let orderedRounds = rounds.sorted { $0.number < $1.number }
    let name = model.playerName(for: playerID, in: orderedRounds) ?? "Player"

    ForEach(orderedRounds.indices, id: \.self) { index in
      let round = orderedRounds[index]
      VStack(alignment: .leading, spacing: 8) {
        playerRoundSection(for: round, playerID: playerID, name: name)
        if index != orderedRounds.indices.last {
          Divider()
        }
      }
      .listRowSeparator(.hidden)
    }
  }

  @ViewBuilder
  func gameOverContent() -> some View {
    if let winningRound = model.winningRound() {
      gameOverWinners(for: winningRound)
    } else {
      Text("No winning round data yet.")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func gameOverWinners(for round: RoundPayload) -> some View {
    let winners = model.winnerIDs(for: round)
    let orderedIDs = model.orderedPlayerIDsForReport(in: [round])

    ForEach(orderedIDs, id: \.self) { playerID in
      let name = model.playerName(for: playerID, in: [round]) ?? "Player"
      let submission = round.submissions.first { $0.playerID == playerID }
      let isLocal = playerID == model.localPlayerID
      let guessWord = submission?.guessWord?.uppercased()
      HStack(spacing: 12) {
        if let submission, let marks = submission.marks {
          MarksView(
            marks: marks,
            letters: submission.guessWord?.map { String($0) },
            size: 28,
            phrase: !isLocal ? submission.phrase : nil,
            isOtherPlayer: !isLocal
          )
        } else {
          Text("—")
            .foregroundStyle(.secondary)
        }

        if winners.contains(playerID) {
          Text("🏆")
        }

        Text(name)
        Spacer()
        Text("\(model.playerScore(for: playerID))")
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier("game-over-player-\(accessibilitySafePlayerName(name))")
      .accessibilityLabel(winners.contains(playerID) ? "Winner \(name)" : "Player \(name)")
      .accessibilityValue(guessWord ?? "")
      .background(
        Color.clear
          .accessibilityElement()
          .accessibilityIdentifier("game-over-player-id-\(playerID)")
      )
    }
  }

  private func accessibilitySafePlayerName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split { !$0.isLetter && !$0.isNumber }
    let joined = parts.joined(separator: "-")
    return joined.isEmpty ? "player" : joined
  }

  @ViewBuilder
  private func playerRoundSection(for round: RoundPayload, playerID: String, name: String) -> some View {
    let revealAll = model.game.status == "completed"
    let isLocal = playerID == model.localPlayerID
    let submission = round.submissions.first { $0.playerID == playerID }
    let guessWord = (revealAll || isLocal) ? submission?.guessWord?.uppercased() : nil
    VStack(alignment: .leading) {
      roundReportContent(for: round, playerID: playerID)
    }
    .accessibilityElement(children: .contain)
    .background(
      Color.clear
        .accessibilityElement()
        .accessibilityIdentifier("player-round-row-\(round.number)-\(playerID)")
        .accessibilityLabel("Player round row \(name)")
        .accessibilityValue(guessWord ?? "")
    )
  }

  @ViewBuilder
  private func roundReportContent(for round: RoundPayload, playerID: String) -> some View {
    let submission = round.submissions.first { $0.playerID == playerID }
    let isLocal = playerID == model.localPlayerID
    let waitingForGuessString = isLocal ? "Waiting for your guess..." : "Waiting for guess..."
    let waitingForVoteString = isLocal ? "Waiting for your vote..." : "Waiting for vote..."

    if round.status == "closed" {
      if let submission {
        completedSubmissionContent(for: submission)
      } else {
        roundStatusRow(text: waitingForGuessString, symbol: "clock", style: .secondary)
      }
    } else if let submission, submission.createdAt != nil {
      if round.status == "voting", submission.voted != true {
        roundStatusRow(text: waitingForVoteString, symbol: "clock", style: .secondary)
      } else if isLocal {
        localInProgressSubmissionContent(for: submission)
      } else {
        roundStatusRow(text: "played", symbol: "checkmark.circle.fill", style: .success)
      }
    } else {
      roundStatusRow(
        text: "waiting...",
        symbol: "clock",
        style: .secondary
      ) {
        debugAction(for: playerID, submission: submission, round: round)
      }
    }
  }

  @ViewBuilder
  private func localInProgressSubmissionContent(for submission: RoundSubmission) -> some View {
    if let guessWord = submission.guessWord {
      neutralGuessTiles(for: guessWord, size: 36)
    }
    if let phrase = submission.phrase {
      Text(phrase)
    }
  }

  @ViewBuilder
  func votingActionSection(for round: RoundPayload) -> some View {
    if !model.hasSubmittedOwnGuess() {
      Text("Waiting on your submission.")
        .foregroundStyle(.secondary)
    } else if model.voteSubmitted {
      votesSubmittedSummary(for: round)
    } else {
      votingOtherPhrasesSection(for: round)
      submitVotesButton
    }
  }

  @ViewBuilder
  private func votesSubmittedSummary(for round: RoundPayload) -> some View {
    ForEach(model.otherSubmissions(in: round)) { submission in
      HStack {
        if submission.id == model.selectedFavoriteID {
          Image(systemName: "hand.thumbsup.fill")
            .foregroundStyle(.green)
        } else if submission.id == model.selectedLeastID {
          Image(systemName: "hand.thumbsdown.fill")
            .foregroundStyle(.red)
        }
        Text(submission.phrase ?? "")
      }
    }
    Text("Waiting for other players' votes to complete this round.")
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("votes-submitted-waiting")
  }

  @ViewBuilder
  private func votingOtherPhrasesSection(for round: RoundPayload) -> some View {
    VStack {
      Text("Other players’ phrases")
        .font(.headline)
      Text("Pick a favorite and least favorite phrase for this round.")
    }
    let submissions = model.otherSubmissions(in: round)
    let firstSubmissionID = submissions.first?.id
    ForEach(submissions) { submission in
      let isFirst = submission.id == firstSubmissionID
      VStack(alignment: .leading, spacing: 8) {
        if let phrase = submission.phrase {
          Text(phrase)
        }
        HStack(spacing: 12) {
          if isFirst {
            Button(
              "",
              systemImage: model.selectedFavoriteID == submission.id
                ? "hand.thumbsup.fill"
                : "hand.thumbsup"
            ) {
              model.toggleFavorite(for: submission)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Favorite phrase")
            .accessibilityIdentifier("vote-favorite-\(submission.id)")
            .onboardingTarget(.favoriteVoteButton)
            .id(OnboardingTarget.favoriteVoteButton)
          } else {
            Button(
              "",
              systemImage: model.selectedFavoriteID == submission.id
                ? "hand.thumbsup.fill"
                : "hand.thumbsup"
            ) {
              model.toggleFavorite(for: submission)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Favorite phrase")
            .accessibilityIdentifier("vote-favorite-\(submission.id)")
          }

          if isFirst {
            Button(
              "",
              systemImage: model.selectedLeastID == submission.id
                ? "hand.thumbsdown.fill"
                : "hand.thumbsdown"
            ) {
              model.toggleLeast(for: submission)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Least favorite phrase")
            .accessibilityIdentifier("vote-least-\(submission.id)")
            .onboardingTarget(.leastVoteButton)
            .id(OnboardingTarget.leastVoteButton)
          } else {
            Button(
              "",
              systemImage: model.selectedLeastID == submission.id
                ? "hand.thumbsdown.fill"
                : "hand.thumbsdown"
            ) {
              model.toggleLeast(for: submission)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Least favorite phrase")
            .accessibilityIdentifier("vote-least-\(submission.id)")
          }

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
            .accessibilityIdentifier("virtual-vote-list-\(submission.playerID)")
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
    .accessibilityIdentifier("submit-votes-button")
    .onboardingTarget(.submitVotesButton)
    .id(OnboardingTarget.submitVotesButton)
    .onAppear {
      isVotesSubmitButtonVisible = true
    }
    .onDisappear {
      isVotesSubmitButtonVisible = false
    }
  }

  @ViewBuilder
  private func completedSubmissionContent(for submission: RoundSubmission) -> some View {
    let isLocal = submission.playerID == model.localPlayerID
    let revealAll = model.game.status == "completed"
    if let marks = submission.marks {
      MarksView(
        marks: marks,
        letters: (revealAll || isLocal) ? submission.guessWord?.map { String($0) } : nil,
        size: 36,
        phrase: !isLocal ? submission.phrase : nil,
        isOtherPlayer: !isLocal
      )
    }
    if let phrase = submission.phrase {
      Text(phrase)
    }
  }

  @ViewBuilder
  private func neutralGuessTiles(for guessWord: String, size: CGFloat) -> some View {
    let letters = Array(guessWord)
    HStack(spacing: 6) {
      ForEach(letters.indices, id: \.self) { index in
        Text(String(letters[index]).uppercased())
          .font(.caption)
          .bold()
          .frame(width: size, height: size)
          .background(Color.white)
          .foregroundStyle(.black)
          .clipShape(.rect(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color.black, lineWidth: 1)
          )
      }
    }
  }

  @ViewBuilder
  private func roundStatusRow<Accessory: View>(
    text: String,
    symbol: String,
    style: StatusStyle,
    @ViewBuilder trailingAction: () -> Accessory = { EmptyView() }
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(style.color)
      Text(text)
        .foregroundStyle(style.textColor)
      Spacer()
      trailingAction()
    }
  }

  @ViewBuilder
  private func debugAction(
    for playerID: String,
    submission: RoundSubmission?,
    round: RoundPayload
  ) -> some View {
    if showDebug, submission?.playerVirtual ?? model.isVirtualPlayer(playerID) {
      if round.status == "waiting", submission?.createdAt == nil {
        Button("Guess") {
          Task {
            await model.submitVirtualGuess(for: playerID)
          }
        }
        .buttonStyle(.bordered)
        .tint(theme.accent)
        .accessibilityIdentifier("virtual-guess-\(playerID)")
      } else if round.status == "voting", submission?.voted != true {
        Button("Vote") {
          Task {
            await model.submitVirtualVote(for: playerID)
          }
        }
        .buttonStyle(.bordered)
        .tint(theme.accent)
        .accessibilityIdentifier("virtual-vote-status-\(playerID)")
      } else {
        EmptyView()
      }
    } else {
      EmptyView()
    }
  }

  private enum StatusStyle {
    case secondary
    case success

    var color: Color {
      switch self {
      case .secondary:
        return .orange
      case .success:
        return .green
      }
    }

    var textColor: Color {
      switch self {
      case .secondary:
        return .secondary
      case .success:
        return .secondary
      }
    }
  }
}

private enum ReportIssueStep: Equatable {
  case options
  case problemWithGame
  case inappropriateContent

  var title: String {
    switch self {
    case .options:
      "Report Issue"
    case .problemWithGame:
      "Problem with game"
    case .inappropriateContent:
      "Inappropriate Content"
    }
  }
}

struct ReportIssueSheet: View {
  let model: GameRoomModel

  @Environment(\.dismiss) private var dismiss
  @State private var step: ReportIssueStep = .options
  @State private var problemDescription = ""
  @State private var reporterName = ""
  @State private var reporterEmail = ""
  @State private var selectedPhraseIDs = Set<String>()
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var showSuccessAlert = false

  private var reportablePhrases: [ReportablePhrase] {
    model.reportablePhrases()
  }

  var body: some View {
    NavigationStack {
      Form {
        switch step {
        case .options:
          optionsContent
        case .problemWithGame:
          problemWithGameContent
        case .inappropriateContent:
          inappropriateContent
        }

        if let errorMessage, !errorMessage.isEmpty {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(step.title)
      .toolbar {
        if step != .options {
          ToolbarItem(placement: .topBarLeading) {
            Button("Back") {
              errorMessage = nil
              step = .options
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .alert("Report Sent", isPresented: $showSuccessAlert) {
        Button("Done") {
          dismiss()
        }
      } message: {
        Text("Thanks. Your report was submitted.")
      }
    }
  }

  private var optionsContent: some View {
    Section {
      Button("Problem with game", systemImage: "wrench.and.screwdriver.fill") {
        errorMessage = nil
        step = .problemWithGame
      }
      .accessibilityIdentifier("report-problem-with-game-button")

      Button("Inappropriate Content", systemImage: "hand.raised.fill") {
        errorMessage = nil
        step = .inappropriateContent
      }
      .accessibilityIdentifier("report-inappropriate-content-button")
    } footer: {
      Text("Select what you want to report.")
    }
  }

  private var problemWithGameContent: some View {
    Group {
      Section("Describe the problem") {
        TextEditor(text: $problemDescription)
          .frame(minHeight: 140)
          .textInputAutocapitalization(.sentences)
          .accessibilityIdentifier("report-problem-description-field")
      }

      Section("Optional contact info") {
        TextField("Name (optional)", text: $reporterName)
          .textContentType(.name)
          .accessibilityIdentifier("report-problem-name-field")
        TextField("Email (optional)", text: $reporterEmail)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.emailAddress)
          .accessibilityIdentifier("report-problem-email-field")
      }

      Section {
        Button {
          Task {
            await submitProblemWithGameReport()
          }
        } label: {
          if isSubmitting {
            ProgressView()
          } else {
            Text("Send Report")
          }
        }
        .disabled(isSubmitting || trimmedProblemDescription.isEmpty)
        .accessibilityIdentifier("report-problem-submit-button")
      }
    }
  }

  private var inappropriateContent: some View {
    Group {
      if reportablePhrases.isEmpty {
        Section {
          Text("No other-player phrases are available to report yet.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section("Select phrase(s) to report") {
          ForEach(reportablePhrases) { phrase in
            Button {
              toggleSelection(for: phrase.id)
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedPhraseIDs.contains(phrase.id) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selectedPhraseIDs.contains(phrase.id) ? .red : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                  Text(phrase.phrase)
                    .foregroundStyle(.primary)
                  Text("Round \(phrase.roundNumber) • \(phrase.playerName) (\(phrase.playerID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("report-phrase-\(phrase.id)")
          }
        }

        Section {
          Button {
            Task {
              await submitInappropriateContentReport()
            }
          } label: {
            if isSubmitting {
              ProgressView()
            } else {
              Text("Send Report")
            }
          }
          .disabled(isSubmitting || selectedPhraseIDs.isEmpty)
          .accessibilityIdentifier("report-inappropriate-submit-button")
        }
      }
    }
  }

  private var trimmedProblemDescription: String {
    problemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func toggleSelection(for phraseID: String) {
    if selectedPhraseIDs.contains(phraseID) {
      selectedPhraseIDs.remove(phraseID)
    } else {
      selectedPhraseIDs.insert(phraseID)
    }
  }

  private func submitProblemWithGameReport() async {
    guard !isSubmitting else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    errorMessage = nil

    do {
      try await model.submitProblemWithGameReport(
        description: trimmedProblemDescription,
        name: reporterName,
        email: reporterEmail
      )
      showSuccessAlert = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func submitInappropriateContentReport() async {
    guard !isSubmitting else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    errorMessage = nil

    let selected = reportablePhrases.filter { selectedPhraseIDs.contains($0.id) }
    do {
      try await model.submitInappropriateContentReport(selectedPhrases: selected)
      showSuccessAlert = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

enum SubmissionReminderKind {
  case guess
  case vote
}

struct SubmissionReminderView: View {
  let kind: SubmissionReminderKind
  let theme: AppTheme

  var body: some View {
    let labelText = switch kind {
    case .guess:
      "Scroll to submit your guess"
    case .vote:
      "Scroll to submit your votes"
    }

    HStack(spacing: 8) {
      Image(systemName: "arrow.down")
        .foregroundStyle(theme.textSecondary)
      Text(labelText)
        .font(.caption)
        .bold()
        .foregroundStyle(theme.textPrimary)
    }
    .padding(.horizontal, theme.cellPadding)
    .padding(.vertical, theme.cellPadding / 2)
    .background(
      RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        .fill(theme.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        .stroke(theme.border, lineWidth: theme.borderWidth)
    )
    .clipShape(.rect(cornerRadius: theme.cornerRadius))
    .accessibilityLabel(labelText)
  }
}
