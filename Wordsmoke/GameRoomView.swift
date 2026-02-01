import SwiftUI

struct GameRoomView: View {
  @Bindable var model: GameRoomModel
  @Bindable var onboarding: OnboardingStore
  let analytics: AnalyticsService
  @Environment(\.appTheme) var theme
  @Environment(\.debugEnabled) var showDebug
  @State private var onboardingIndex = 0
  @State private var onboardingIsActive = false
  @State private var onboardingVisibleTargets = Set<OnboardingTarget>()
  @State private var lastTrackedStepID: OnboardingStepID?

  var body: some View {
    ScrollViewReader { proxy in
      ZStack {
        Form {
          if showDebug {
            Section("Status") {
              Text("Status: \(model.game.status)")
            }
          }

          if model.game.status == "waiting", let participants = model.game.participants {
            Section {
              ForEach(participants, id: \.id) { participant in
                HStack {
                  Text(participant.player.displayName)
                  Spacer()
                  Text(participant.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              if participants.count < 2 {
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
                Button("Start Game") {
                  Task {
                    await model.startGame()
                  }
                }
                .buttonStyle(.borderedProminent)
                .disabled((model.game.playersCount ?? 0) < 2 || model.isBusy)
                .accessibilityIdentifier("game-room-start-button")
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
              Section("Your Vote") {
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
          }
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
}
