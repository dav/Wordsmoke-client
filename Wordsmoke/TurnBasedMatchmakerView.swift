import GameKit
import SwiftUI
import UIKit

struct TurnBasedMatchmakerView: UIViewControllerRepresentable {
  let minPlayers: Int
  let maxPlayers: Int
  let onMatch: (GKTurnBasedMatch) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> TurnBasedMatchmakerCoordinator {
    TurnBasedMatchmakerCoordinator(onMatch: onMatch, onCancel: onCancel)
  }

  func makeUIViewController(context: Context) -> GKTurnBasedMatchmakerViewController {
    let request = GKMatchRequest()
    request.minPlayers = minPlayers
    request.maxPlayers = maxPlayers
    request.defaultNumberOfPlayers = minPlayers

    let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
    controller.matchmakingMode = .inviteOnly
    controller.showExistingMatches = false
    controller.turnBasedMatchmakerDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: GKTurnBasedMatchmakerViewController, context: Context) {
  }
}

final class TurnBasedMatchmakerCoordinator: NSObject, @MainActor GKTurnBasedMatchmakerViewControllerDelegate {
  private let onMatch: (GKTurnBasedMatch) -> Void
  private let onCancel: () -> Void

  init(onMatch: @escaping (GKTurnBasedMatch) -> Void, onCancel: @escaping () -> Void) {
    self.onMatch = onMatch
    self.onCancel = onCancel
  }

  func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
    onCancel()
  }

  func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, didFailWithError error: Error) {
    Log.log(
      "Turn-based matchmaker failed",
      level: .warning,
      category: .gameCenter,
      error: error,
      metadata: ["operation": "turn_based_matchmaker_view_controller"]
    )
    onCancel()
  }

  func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, didFind match: GKTurnBasedMatch) {
    onMatch(match)
  }
}
