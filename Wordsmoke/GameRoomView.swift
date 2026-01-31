import SwiftUI

struct GameRoomView: View {
  @Bindable var model: GameRoomModel
  @Environment(\.appTheme) var theme
  @Environment(\.debugEnabled) var showDebug

  var body: some View {
    ScrollViewReader { proxy in
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
    }
  }
}
