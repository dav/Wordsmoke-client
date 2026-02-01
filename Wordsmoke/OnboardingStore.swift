import Foundation
import Observation

@MainActor
@Observable
final class OnboardingStore {
  private let hasCompletedKey = "onboarding.completed"
  private let pendingStartKey = "onboarding.pendingStart"
  private let userDefaults: UserDefaults

  var hasCompleted: Bool {
    didSet {
      userDefaults.set(hasCompleted, forKey: hasCompletedKey)
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
    if let storedValue = userDefaults.object(forKey: pendingStartKey) as? Bool {
      pendingStart = storedValue
    } else {
      pendingStart = !completed
    }
  }

  var shouldStart: Bool {
    pendingStart || !hasCompleted
  }

  func requestStart() {
    pendingStart = true
    hasCompleted = false
  }

  func consumeStart() {
    pendingStart = false
  }

  func markCompleted() {
    hasCompleted = true
    pendingStart = false
  }

  func reset() {
    hasCompleted = false
    pendingStart = false
  }
}
