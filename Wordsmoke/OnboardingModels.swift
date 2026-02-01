import SwiftUI

enum OnboardingTarget: String, Hashable {
  case guessWordField
  case phraseField
  case submitGuessButton
  case favoriteVoteButton
  case leastVoteButton
  case submitVotesButton
}

enum OnboardingStepID: String, Hashable {
  case welcome
  case guessWord
  case phrase
  case submitGuess
  case favoriteVote
  case leastVote
  case submitVotes
}

struct OnboardingStep: Identifiable, Hashable {
  let id: OnboardingStepID
  let title: String
  let message: String
  let target: OnboardingTarget?
  let primaryActionTitle: String
  let requiresTarget: Bool

  var analyticsProperties: [String: Any] {
    var properties: [String: Any] = [
      "step_id": id.rawValue,
      "step_title": title
    ]
    if let target {
      properties["step_target"] = target.rawValue
    }
    return properties
  }
}

struct OnboardingTargetPreferenceKey: PreferenceKey {
  static var defaultValue: [OnboardingTarget: Anchor<CGRect>] { [:] }

  static func reduce(
    value: inout [OnboardingTarget: Anchor<CGRect>],
    nextValue: () -> [OnboardingTarget: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

extension View {
  func onboardingTarget(_ target: OnboardingTarget) -> some View {
    anchorPreference(key: OnboardingTargetPreferenceKey.self, value: .bounds) { anchor in
      [target: anchor]
    }
  }
}
