import GameKit
import SwiftUI
import UIKit

struct MatchmakerView: UIViewControllerRepresentable {
  let joinCode: String
  let minPlayers: Int
  let maxPlayers: Int
  let onFinish: () -> Void

  func makeCoordinator() -> MatchmakerCoordinator {
    MatchmakerCoordinator(onFinish: onFinish)
  }

  func makeUIViewController(context: Context) -> GKMatchmakerViewController {
    let request = GKMatchRequest()
    request.minPlayers = minPlayers
    request.maxPlayers = maxPlayers
    request.inviteMessage = "Join Wordsmoke: \(joinCode)"

    guard let controller = GKMatchmakerViewController(matchRequest: request) else {
      let empty = GKMatchmakerViewController()
      Task { @MainActor in
        onFinish()
      }
      return empty
    }
    controller.matchmakingMode = .inviteOnly
    controller.matchmakerDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: GKMatchmakerViewController, context: Context) {
  }
}

struct MatchmakerInviteView: UIViewControllerRepresentable {
  let invite: GKInvite
  let onFinish: () -> Void

  func makeCoordinator() -> MatchmakerCoordinator {
    MatchmakerCoordinator(onFinish: onFinish)
  }

  func makeUIViewController(context: Context) -> GKMatchmakerViewController {
    guard let controller = GKMatchmakerViewController(invite: invite) else {
      let empty = GKMatchmakerViewController()
      Task { @MainActor in
        onFinish()
      }
      return empty
    }
    controller.matchmakerDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: GKMatchmakerViewController, context: Context) {
  }
}

final class MatchmakerCoordinator: NSObject, @MainActor GKMatchmakerViewControllerDelegate {
  private let onFinish: () -> Void

  init(onFinish: @escaping () -> Void) {
    self.onFinish = onFinish
  }

  func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
    onFinish()
  }

  func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
    print("[GameCenter] Matchmaker failed: \(error)")
    onFinish()
  }

  func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
    onFinish()
  }
}
