import Foundation
import GameKit
import Observation
import UIKit

struct GameCenterSignature: Sendable {
  let publicKeyURL: URL
  let signature: Data
  let salt: Data
  let timestamp: UInt64
  let teamPlayerID: String
  let bundleID: String
}

struct AuthViewControllerItem: Identifiable {
  let id = UUID()
  let viewController: UIViewController
}

struct InviteMatchmakerItem: Identifiable {
  let id = UUID()
  let invite: GKInvite
}

struct TurnBasedMatchItem: Identifiable {
  let id = UUID()
  let match: GKTurnBasedMatch
}

struct TurnBasedMatchSummary: Sendable {
  let matchID: String
  let localParticipantStatus: GKTurnBasedParticipant.Status?
}

@MainActor
@Observable
final class GameCenterService: NSObject {
  var authenticationViewControllerItem: AuthViewControllerItem?
  var inviteMatchmakerItem: InviteMatchmakerItem?
  var receivedTurnBasedMatch: TurnBasedMatchItem?
  var isAuthenticated = false
  var playerDisplayName: String?
  var playerID: String?
  var lastErrorDescription: String?
  var lastError: Error?
  private let eventListener = GameCenterEventListener()
  private var isListenerRegistered = false

#if targetEnvironment(simulator)
  func configure() {
    authenticationViewControllerItem = nil
    inviteMatchmakerItem = nil
    isAuthenticated = true
    playerDisplayName = "Simulator"
    playerID = "SIMULATOR-LOCAL"
    lastErrorDescription = nil
    lastError = nil
  }

  func fetchIdentitySignature() async throws -> GameCenterSignature {
    let bundleID = Bundle.main.bundleIdentifier ?? ""
    let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

    return GameCenterSignature(
      publicKeyURL: URL(string: "https://example.com")!,
      signature: Data(),
      salt: Data(),
      timestamp: timestamp,
      teamPlayerID: playerID ?? "SIMULATOR-LOCAL",
      bundleID: bundleID
    )
  }

  func loadTurnBasedMatchSummaries() async throws -> [TurnBasedMatchSummary] {
    []
  }
#else
  func configure() {
    GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
      guard let self else { return }

      if let viewController {
        authenticationViewControllerItem = AuthViewControllerItem(viewController: viewController)
        return
      }

      authenticationViewControllerItem = nil
      inviteMatchmakerItem = nil

      if let error {
        lastErrorDescription = error.localizedDescription
        lastError = error
        isAuthenticated = false
        unregisterListenerIfNeeded()
        return
      }

      let localPlayer = GKLocalPlayer.local
      isAuthenticated = localPlayer.isAuthenticated
      playerDisplayName = localPlayer.displayName
      playerID = localPlayer.teamPlayerID
      lastErrorDescription = nil
      lastError = nil

      if isAuthenticated {
        registerListenerIfNeeded()
      } else {
        unregisterListenerIfNeeded()
      }
    }
  }

  func fetchIdentitySignature() async throws -> GameCenterSignature {
    let localPlayer = GKLocalPlayer.local
    do {
      let (publicKeyURL, signature, salt, timestamp) =
        try await localPlayer.fetchItemsForIdentityVerificationSignature()
      let bundleID = Bundle.main.bundleIdentifier ?? ""

      return GameCenterSignature(
        publicKeyURL: publicKeyURL,
        signature: signature,
        salt: salt,
        timestamp: timestamp,
        teamPlayerID: localPlayer.teamPlayerID,
        bundleID: bundleID
      )
    } catch {
      lastErrorDescription = error.localizedDescription
      lastError = error
      throw error
    }
  }

  func loadTurnBasedMatchSummaries() async throws -> [TurnBasedMatchSummary] {
    let localPlayerID = GKLocalPlayer.local.teamPlayerID
    let matches = try await GKTurnBasedMatch.loadMatches()

    return matches.map { match in
      let localParticipant = match.participants.first { participant in
        participant.player?.teamPlayerID == localPlayerID
      }

      return TurnBasedMatchSummary(
        matchID: match.matchID,
        localParticipantStatus: localParticipant?.status
      )
    }
  }
#endif

  func handleInviteAcceptance(_ invite: GKInvite) {
    inviteMatchmakerItem = InviteMatchmakerItem(invite: invite)
  }

  func handleReceivedTurnBasedMatch(_ match: GKTurnBasedMatch) {
    receivedTurnBasedMatch = TurnBasedMatchItem(match: match)
  }

  private func registerListenerIfNeeded() {
    guard !isListenerRegistered else { return }
    eventListener.onInviteAccepted = { [weak self] invite in
      Task { @MainActor in
        self?.handleInviteAcceptance(invite)
      }
    }
    eventListener.onTurnBasedMatchReceived = { [weak self] match in
      Task { @MainActor in
        self?.handleReceivedTurnBasedMatch(match)
      }
    }
    GKLocalPlayer.local.register(eventListener)
    isListenerRegistered = true
  }

  private func unregisterListenerIfNeeded() {
    guard isListenerRegistered else { return }
    GKLocalPlayer.local.unregisterListener(eventListener)
    eventListener.onInviteAccepted = nil
    eventListener.onTurnBasedMatchReceived = nil
    isListenerRegistered = false
  }
}

final class GameCenterEventListener: NSObject, GKLocalPlayerListener {
  var onInviteAccepted: ((GKInvite) -> Void)?
  var onTurnBasedMatchReceived: ((GKTurnBasedMatch) -> Void)?

  func player(_ player: GKPlayer, didAccept invite: GKInvite) {
    onInviteAccepted?(invite)
  }

  func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
    guard didBecomeActive else { return }
    onTurnBasedMatchReceived?(match)
  }
}
