import Foundation
import Observation

@MainActor
@Observable
final class OnboardingStore {
  private let hasCompletedKey = "onboarding.completed"
  private let hasCompletedVotingKey = "onboarding.completedVoting"
  private let pendingStartKey = "onboarding.pendingStart"
  private let userDefaults: UserDefaults

  var hasCompleted: Bool {
    didSet {
      userDefaults.set(hasCompleted, forKey: hasCompletedKey)
    }
  }

  var hasCompletedVoting: Bool {
    didSet {
      userDefaults.set(hasCompletedVoting, forKey: hasCompletedVotingKey)
    }
  }

  var pendingStart: Bool {
    didSet {
      userDefaults.set(pendingStart, forKey: pendingStartKey)
    }
  }

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    let completed = userDefaults.bool(forKey: hasCompletedKey)
    hasCompleted = completed
    hasCompletedVoting = userDefaults.bool(forKey: hasCompletedVotingKey)
    if let storedValue = userDefaults.object(forKey: pendingStartKey) as? Bool {
      pendingStart = storedValue
    } else {
      pendingStart = !completed
    }

    if ProcessInfo.processInfo.environment["WORDSMOKE_RESET_ONBOARDING"] == "1" {
      hasCompleted = false
      hasCompletedVoting = false
      pendingStart = true
    }
  }

  var shouldStart: Bool {
    pendingStart || !hasCompleted
  }

  var shouldStartVotingOnboarding: Bool {
    hasCompleted && !hasCompletedVoting
  }

  func requestStart() {
    pendingStart = true
    hasCompleted = false
    hasCompletedVoting = false
  }

  func consumeStart() {
    pendingStart = false
  }

  func markCompleted() {
    hasCompleted = true
    hasCompletedVoting = true
    pendingStart = false
  }

  func markSubmissionCompleted() {
    hasCompleted = true
    pendingStart = false
  }

  func reset() {
    hasCompleted = false
    hasCompletedVoting = false
    pendingStart = false
  }
}
