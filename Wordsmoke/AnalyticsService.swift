import AmplitudeSwift

@MainActor
final class AnalyticsService {
  static let shared = AnalyticsService()

  private let amplitude: Amplitude

  init() {
    amplitude = Amplitude(
      configuration: Configuration(
        apiKey: "885989fb9c8cf7d1e72869376c936217" // https://app.amplitude.com/analytics/sekai-no/settings/api-keys/api
      )
    )
  }

  func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
    amplitude.track(eventType: event.rawValue, eventProperties: properties)
  }
}
