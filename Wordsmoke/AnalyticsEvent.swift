import Foundation

enum AnalyticsEvent: String {
  case onboardingStarted = "onboarding_started"
  case onboardingStepViewed = "onboarding_step_viewed"
  case onboardingStepCompleted = "onboarding_step_completed"
  case onboardingSkipped = "onboarding_skipped"
  case onboardingCompleted = "onboarding_completed"
  case onboardingRerunRequested = "onboarding_rerun_requested"
}
