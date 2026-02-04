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

@MainActor
@Observable
final class GameCenterService: NSObject {
  var authenticationViewControllerItem: AuthViewControllerItem?
  var inviteMatchmakerItem: InviteMatchmakerItem?
  var isAuthenticated = false
  var playerDisplayName: String?
  var playerID: String?
  var lastErrorDescription: String?
  var lastError: Error?
  private let inviteListener = GameCenterInviteListener()
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
#endif

  func handleInviteAcceptance(_ invite: GKInvite) {
    inviteMatchmakerItem = InviteMatchmakerItem(invite: invite)
  }

  private func registerListenerIfNeeded() {
    guard !isListenerRegistered else { return }
    inviteListener.onInviteAccepted = { [weak self] invite in
      Task { @MainActor in
        self?.handleInviteAcceptance(invite)
      }
    }
    GKLocalPlayer.local.register(inviteListener)
    isListenerRegistered = true
  }

  private func unregisterListenerIfNeeded() {
    guard isListenerRegistered else { return }
    GKLocalPlayer.local.unregisterListener(inviteListener)
    inviteListener.onInviteAccepted = nil
    isListenerRegistered = false
  }
}

final class GameCenterInviteListener: NSObject, GKLocalPlayerListener {
  var onInviteAccepted: ((GKInvite) -> Void)?

  func player(_ player: GKPlayer, didAccept invite: GKInvite) {
    onInviteAccepted?(invite)
  }
}
