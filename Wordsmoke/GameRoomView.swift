import SwiftUI

struct GameRoomView: View {
  @Bindable var model: GameRoomModel
  @Environment(\.appTheme) var theme
  @Environment(\.debugEnabled) var showDebug

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
}
