import Foundation
import GameKit
import Observation

@MainActor
@Observable
final class InvitePlayersViewModel {
  let provider: MatchmakingProvider
  let requiredInvitees: Int
  private(set) var invitees: [MatchmakingInvitee] = []
  var selectedIDs: Set<String> = []
  var isLoading = false
  var errorMessage: String?
  var isFriendListDenied = false

  init(provider: MatchmakingProvider, playerCount: Int) {
    self.provider = provider
    self.requiredInvitees = max(playerCount - 1, 0)
  }

  var sourceTitle: String {
    provider.source.title
  }

  var sourceDetail: String {
    provider.source.detail
  }

  var canSendInvites: Bool {
    selectedIDs.count == requiredInvitees && !isLoading
  }

  func loadInvitees() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      invitees = try await provider.loadInvitees()
      errorMessage = nil
      isFriendListDenied = false
    } catch {
      let isFriendDenied = (error as NSError).domain == GKError.errorDomain
        && error.localizedDescription.localizedCaseInsensitiveContains("friend")
      isFriendListDenied = isFriendDenied
      if isFriendDenied {
        errorMessage = "To invite friends, enable \u{201c}Share Friends List\u{201d} in Settings \u{2192} Game Center."
      } else {
        errorMessage = error.localizedDescription
      }
    }
  }

  func toggleSelection(for invitee: MatchmakingInvitee) {
    if selectedIDs.contains(invitee.id) {
      selectedIDs.remove(invitee.id)
    } else if selectedIDs.count < requiredInvitees {
      selectedIDs.insert(invitee.id)
    }
  }
}
