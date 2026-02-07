import Observation
import SwiftUI

struct InvitePlayersView: View {
  @Bindable var appModel: AppModel
  let goalLength: Int
  let playerCount: Int
  let onCancel: () -> Void
  @Environment(\.appTheme) private var theme
  @State private var viewModel: InvitePlayersViewModel

  init(
    appModel: AppModel,
    goalLength: Int,
    playerCount: Int,
    onCancel: @escaping () -> Void
  ) {
    self._appModel = Bindable(wrappedValue: appModel)
    self.goalLength = goalLength
    self.playerCount = playerCount
    self.onCancel = onCancel
    _viewModel = State(initialValue: InvitePlayersViewModel(
      provider: appModel.matchmakingProvider,
      playerCount: playerCount
    ))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(viewModel.sourceDetail)
            .foregroundStyle(theme.textSecondary)
        } header: {
          Text(viewModel.sourceTitle)
        }

        Section {
          HStack {
            Text("Select \(viewModel.requiredInvitees) player\(viewModel.requiredInvitees == 1 ? "" : "s")")
            Spacer()
            Text("\(viewModel.selectedIDs.count)/\(viewModel.requiredInvitees)")
              .foregroundStyle(theme.textSecondary)
          }
        }

        Section("Available") {
          if viewModel.invitees.isEmpty {
            Text("No players available.")
              .foregroundStyle(theme.textSecondary)
          } else {
            ForEach(viewModel.invitees) { invitee in
              InviteeRowView(
                invitee: invitee,
                isSelected: viewModel.selectedIDs.contains(invitee.id)
              ) {
                viewModel.toggleSelection(for: invitee)
              }
            }
          }
        }

        if let errorMessage = viewModel.errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Invite Players")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            onCancel()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send Invites") {
            Task {
              await appModel.createGameWithInvites(inviteeIDs: Array(viewModel.selectedIDs))
            }
          }
          .disabled(!viewModel.canSendInvites || appModel.isBusy)
        }
      }
      .task {
        await viewModel.loadInvitees()
      }
    }
    .presentationDetents([.large])
  }
}
