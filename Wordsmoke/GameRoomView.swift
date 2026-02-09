import SwiftUI
import UIKit

struct GameRoomView: View {
  enum SubmissionField {
    case guess
    case phrase
  }

  @Bindable var model: GameRoomModel
  @Bindable var onboarding: OnboardingStore
  let analytics: AnalyticsService
  private let gameRoomBottomAnchorID = "game-room-bottom-anchor"
  @Environment(\.appTheme) var theme
  @Environment(\.debugEnabled) var showDebug
  @Environment(\.scenePhase) private var scenePhase
  @FocusState var focusedField: SubmissionField?
  @State private var onboardingIndex = 0
  @State private var onboardingIsActive = false
  @State private var onboardingVisibleTargets = Set<OnboardingTarget>()
  @State private var lastTrackedStepID: OnboardingStepID?
  @State var isGuessSubmitButtonVisible = false
  @State var isVotesSubmitButtonVisible = false
  @State var isReportIssueSheetPresented = false
  @State var isStartGameConfirmationPresented = false
  @State var inviteCodeWasCopied = false

  var body: some View {
    ScrollViewReader { proxy in
      let reminderKind: SubmissionReminderKind? = {
        guard let round = model.round else { return nil }
        if shouldShowSubmissionForm(for: round) {
          return isGuessSubmitButtonVisible ? nil : .guess
        }
        if round.status == "voting", model.hasSubmittedOwnGuess(), !model.voteSubmitted {
          return isVotesSubmitButtonVisible ? nil : .vote
        }
        return nil
      }()

      ZStack(alignment: .bottomTrailing) {
        Form {
          if showDebug {
            Section("Status") {
              Text("Status: \(model.game.status)")
            }
          }

          if model.game.status == "waiting" {
            let waitingStatuses = model.waitingRoomPlayerStatuses()
            let playersCount = model.game.playersCount ?? model.game.participants?.count ?? waitingStatuses.count
            Section {
              ForEach(waitingStatuses) { player in
                HStack {
                  Text(player.displayName)
                  Spacer()
                  Text(player.statusText)
                    .font(.caption)
                    .foregroundStyle(player.highlightsAsPositive ? .green : .secondary)
                }
                .accessibilityIdentifier("waiting-player-\(player.playerID)")
              }

              if playersCount < 2 {
                Text("Waiting for other players to join")
                  .font(.callout)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .center)
                  .accessibilityIdentifier("waiting-for-players-text")
              }
            } header: {
              HStack {
                Text("Players")
                Spacer()
                if model.isHost() {
                  Button("Start Game") {
                    triggerStartGame()
                  }
                  .buttonStyle(.borderedProminent)
                  .disabled(playersCount < 2 || model.isBusy)
                  .accessibilityIdentifier("game-room-start-button")
                }
              }
            }
            
            Section("Invite Code") {
              HStack {
                Text(model.game.joinCode)
                  .font(.title2.monospaced())
                  .accessibilityIdentifier("invite-code-value")
                Spacer()
                Button(inviteCodeWasCopied ? "Copied" : "Copy") {
                  copyInviteCodeToClipboard()
                }
                .buttonStyle(.bordered)
                .disabled(inviteCodeWasCopied)
                .accessibilityIdentifier("copy-invite-code-button")
              }
            }
          }

          let reportRounds = model.reportRounds()
          if !reportRounds.isEmpty {
            let orderedIDs = model.orderedPlayerIDsForReport(in: reportRounds)
            ForEach(orderedIDs, id: \.self) { playerID in
              Section {
                playerReportContent(for: playerID, rounds: reportRounds)
              } header: {
                Text(model.playerName(for: playerID, in: reportRounds) ?? "Player")
              }
            }
          } else if model.game.status != "waiting" {
            Section("Game Report") {
              Text("No round data yet.")
                .foregroundStyle(.secondary)
            }
          }

          if model.game.status == "completed", model.round == nil {
            Section {
              gameOverContent()
            } header: {
              Text("Game Over")
                .accessibilityIdentifier("game-over-section")
            }
            .id("game-over-section")
          } else if let round = model.round {
            if shouldShowSubmissionForm(for: round) {
              Section("Your Round \(round.number) Guess") {
                submissionForm()
              }
            } else if round.status == "voting" {
              Section("Your Round \(round.number) Vote") {
                votingActionSection(for: round)
              }
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
              .accessibilityIdentifier("refresh-round-button")
            }
          }

          reportIssueSection
            .id(gameRoomBottomAnchorID)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .listRowBackground(theme.cardBackground)
        .background(theme.background)
        .tint(theme.accent)
        .sheet(isPresented: $isReportIssueSheetPresented) {
          ReportIssueSheet(model: model)
        }
        .alert("Start without all invitees?", isPresented: $isStartGameConfirmationPresented) {
          Button("Cancel", role: .cancel) {
          }
          Button("Start Anyway") {
            Task {
              await model.startGame()
            }
          }
        } message: {
          Text("Some invited players have not accepted yet. Start the game anyway?")
        }
        .task {
          if model.round == nil {
            await model.refreshRound()
          }
          setInitialFocus()
        }
        .onAppear {
          if scenePhase == .active {
            model.startPolling()
          }
          startOnboardingIfNeeded()
          if model.game.status == "completed", model.round == nil {
            Task { @MainActor in
              withAnimation {
                proxy.scrollTo("game-over-section", anchor: .bottom)
              }
            }
          }
        }
        .onDisappear {
          model.stopPolling()
        }
        .onChange(of: scenePhase) { _, newValue in
          if newValue == .active {
            model.startPolling()
          } else {
            model.stopPolling()
          }
        }
        .onChange(of: model.game.status) { _, newValue in
          guard newValue == "completed", model.round == nil else { return }
          withAnimation {
            proxy.scrollTo("game-over-section", anchor: .bottom)
          }
        }
        .onChange(of: onboarding.pendingStart) { _, _ in
          startOnboardingIfNeeded()
        }
        .onChange(of: currentOnboardingStepID) { _, newValue in
          guard onboardingIsActive else { return }
          guard let stepID = newValue, stepID != lastTrackedStepID else { return }
          if let step = onboardingSteps.first(where: { $0.id == stepID }) {
            analytics.track(.onboardingStepViewed, properties: analyticsProperties(for: step))
            lastTrackedStepID = stepID
            if let target = step.target {
              scrollToOnboardingTarget(target, proxy: proxy)
            }
          }
        }
        .onChange(of: onboardingVisibleTargets) { _, _ in
          guard onboardingIsActive, let target = currentOnboardingStep?.target else { return }
          scrollToOnboardingTarget(target, proxy: proxy)
        }

        if let reminderKind {
          Button {
            scrollToSubmissionArea(proxy: proxy)
          } label: {
            SubmissionReminderView(kind: reminderKind, theme: theme)
          }
          .buttonStyle(.plain)
          .padding(.trailing, theme.sectionSpacing)
          .padding(.bottom, theme.sectionSpacing)
          .accessibilityIdentifier("submission-reminder")
        }
      }
      .overlayPreferenceValue(OnboardingTargetPreferenceKey.self) { anchors in
        if let step = currentOnboardingStep {
          OnboardingOverlay(step: step, anchors: anchors, onNext: advanceOnboarding, onSkip: skipOnboarding)
        }
      }
      .onPreferenceChange(OnboardingTargetPreferenceKey.self) { anchors in
        onboardingVisibleTargets = Set(anchors.keys)
      }
    }
    .navigationTitle("\(model.game.goalLength) Letter Word")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var onboardingSteps: [OnboardingStep] {
    [
      OnboardingStep(
        id: .welcome,
        title: "Welcome to Wordsmoke",
        message: "This quick tour walks you through your first round. You can skip anytime.",
        target: nil,
        primaryActionTitle: "Start Tour",
        requiresTarget: false
      ),
      OnboardingStep(
        id: .guessWord,
        title: "Enter a guess",
        message: "Type a \(model.game.goalLength)-letter guess for the hidden word.",
        target: .guessWordField,
        primaryActionTitle: "Next",
        requiresTarget: true
      ),
      OnboardingStep(
        id: .phrase,
        title: "Write a phrase",
        message: "Create a phrase that includes every letter from your guess. For example if you guessed POISE, a valid phrase could be \"Antiseptic Koalas.\"",
        target: .phraseField,
        primaryActionTitle: "Next",
        requiresTarget: true
      ),
      OnboardingStep(
        id: .submitGuess,
        title: "Submit your round",
        message: "Lock in your guess and phrase to move the round forward.",
        target: .submitGuessButton,
        primaryActionTitle: "Next",
        requiresTarget: true
      ),
      OnboardingStep(
        id: .favoriteVote,
        title: "Pick a favorite",
        message: "Vote for your favorite phrase from another player (whatever that means to you). Voting is used for tie breakers.",
        target: .favoriteVoteButton,
        primaryActionTitle: "Next",
        requiresTarget: true
      ),
      OnboardingStep(
        id: .leastVote,
        title: "Pick a least favorite",
        message: "Vote for the phrase you liked least.",
        target: .leastVoteButton,
        primaryActionTitle: "Next",
        requiresTarget: true
      ),
      OnboardingStep(
        id: .submitVotes,
        title: "Submit votes",
        message: "Send your votes to reveal the round report.",
        target: .submitVotesButton,
        primaryActionTitle: "Finish",
        requiresTarget: true
      )
    ]
  }

  private func triggerStartGame() {
    if model.shouldConfirmEarlyStart() {
      isStartGameConfirmationPresented = true
      return
    }

    Task {
      await model.startGame()
    }
  }

  private func copyInviteCodeToClipboard() {
    UIPasteboard.general.string = model.game.joinCode
    inviteCodeWasCopied = true
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      inviteCodeWasCopied = false
    }
  }

  private var currentOnboardingStep: OnboardingStep? {
    guard onboardingIsActive, onboardingIndex < onboardingSteps.count else { return nil }
    let step = onboardingSteps[onboardingIndex]
    guard isOnboardingStepEligible(step) else { return nil }
    if step.requiresTarget, let target = step.target, !onboardingVisibleTargets.contains(target) {
      return nil
    }
    return step
  }

  private var currentOnboardingStepID: OnboardingStepID? {
    currentOnboardingStep?.id
  }

  private func isOnboardingStepEligible(_ step: OnboardingStep) -> Bool {
    switch step.id {
    case .welcome:
      return true
    case .guessWord, .phrase, .submitGuess:
      guard let round = model.round else { return false }
      return shouldShowSubmissionForm(for: round)
    case .favoriteVote, .leastVote, .submitVotes:
      guard let round = model.round else { return false }
      return round.status == "voting" && model.hasSubmittedOwnGuess()
    }
  }

  private func startOnboardingIfNeeded() {
    guard !onboardingIsActive else { return }
    guard onboarding.shouldStart else { return }
    onboardingIsActive = true
    onboarding.consumeStart()
    onboardingIndex = 0
    lastTrackedStepID = nil
    analytics.track(.onboardingStarted, properties: onboardingContextProperties)
  }

  private func advanceOnboarding() {
    guard onboardingIsActive else { return }
    if onboardingIndex < onboardingSteps.count {
      let step = onboardingSteps[onboardingIndex]
      analytics.track(.onboardingStepCompleted, properties: analyticsProperties(for: step))
    }
    onboardingIndex += 1
    if onboardingIndex >= onboardingSteps.count {
      completeOnboarding()
    }
  }

  private func skipOnboarding() {
    if let step = currentOnboardingStep {
      analytics.track(.onboardingSkipped, properties: analyticsProperties(for: step))
    } else {
      analytics.track(.onboardingSkipped, properties: onboardingContextProperties)
    }
    onboardingIsActive = false
    onboarding.markCompleted()
  }

  private func completeOnboarding() {
    onboardingIsActive = false
    onboarding.markCompleted()
    analytics.track(.onboardingCompleted, properties: onboardingContextProperties)
  }

  private var onboardingContextProperties: [String: Any] {
    [
      "game_id": model.game.id,
      "game_code": model.game.joinCode
    ]
  }

  private func analyticsProperties(for step: OnboardingStep) -> [String: Any] {
    step.analyticsProperties.merging(onboardingContextProperties) { current, _ in
      current
    }
  }

  private func scrollToOnboardingTarget(_ target: OnboardingTarget, proxy: ScrollViewProxy) {
    Task { @MainActor in
      for _ in 0..<3 {
        withAnimation {
          proxy.scrollTo(target, anchor: .center)
        }
        try? await Task.sleep(for: .milliseconds(150))
      }
    }
  }

  private func setInitialFocus() {
    guard let round = model.round, shouldShowSubmissionForm(for: round) else { return }
    if model.guessWord.isEmpty {
      focusedField = .guess
    } else if model.phrase.isEmpty {
      focusedField = .phrase
    }
  }

  private func scrollToSubmissionArea(proxy: ScrollViewProxy) {
    Task { @MainActor in
      for _ in 0..<2 {
        withAnimation {
          proxy.scrollTo(gameRoomBottomAnchorID, anchor: .bottom)
        }
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }
}
