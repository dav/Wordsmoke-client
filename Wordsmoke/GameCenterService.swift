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

@MainActor
@Observable
final class GameCenterService {
  var authenticationViewControllerItem: AuthViewControllerItem?
  var isAuthenticated = false
  var playerDisplayName: String?
  var playerID: String?
  var lastErrorDescription: String?
  var lastError: Error?

  func configure() {
    GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
      guard let self else { return }

      if let viewController {
        authenticationViewControllerItem = AuthViewControllerItem(viewController: viewController)
        return
      }

      authenticationViewControllerItem = nil

      if let error {
        lastErrorDescription = error.localizedDescription
        lastError = error
        isAuthenticated = false
        return
      }

      let localPlayer = GKLocalPlayer.local
      isAuthenticated = localPlayer.isAuthenticated
      playerDisplayName = localPlayer.displayName
      playerID = localPlayer.teamPlayerID
      lastErrorDescription = nil
      lastError = nil
    }
  }

  func fetchIdentitySignature() async throws -> GameCenterSignature {
    let localPlayer = GKLocalPlayer.local
    do {
      let (publicKeyURL, signature, salt, timestamp) = try await localPlayer.fetchItemsForIdentityVerificationSignature()
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
}
