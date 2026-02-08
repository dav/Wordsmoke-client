import Foundation

enum ErrorLogLevel: String {
  case debug
  case info
  case warning
  case error
  case critical

  var sendsRemoteTelemetry: Bool {
    switch self {
    case .warning, .error, .critical:
      return true
    case .debug, .info:
      return false
    }
  }
}

enum ErrorCategory: String {
  case api
  case appModel = "app_model"
  case gameCenter = "game_center"
  case actionCable = "action_cable"
  case matchmaking
  case build
}

enum ErrorReporter {
  static func log(
    _ message: String,
    level: ErrorLogLevel = .debug,
    category: ErrorCategory = .appModel,
    error: Error? = nil,
    metadata: [String: String] = [:],
    file: StaticString = #fileID,
    line: UInt = #line
  ) {
    var payload = metadata
    payload["log_level"] = level.rawValue
    payload["category"] = category.rawValue
    payload["message"] = truncate(message)
    payload["file"] = "\(file)"
    payload["line"] = "\(line)"

    if let error {
      let nsError = error as NSError
      payload["error_domain"] = nsError.domain
      payload["error_code"] = "\(nsError.code)"
      payload["error_description"] = truncate(nsError.localizedDescription)
    }

    logToConsole(payload: payload)
    trackTelemetryIfNeeded(level: level, payload: payload)
  }

  private static func logToConsole(payload: [String: String]) {
    let category = payload["category"] ?? "unknown"
    let level = payload["log_level"] ?? "debug"
    let message = payload["message"] ?? "log"
    let description = payload["error_description"]

    if let description {
      print("[\(category.uppercased())][\(level.uppercased())] \(message): \(description)")
    } else {
      print("[\(category.uppercased())][\(level.uppercased())] \(message)")
    }
  }

  private static func trackTelemetryIfNeeded(level: ErrorLogLevel, payload: [String: String]) {
    guard level.sendsRemoteTelemetry else { return }

    Task { @MainActor in
      var eventProperties: [String: Any] = [:]
      for (key, value) in payload {
        eventProperties[key] = value
      }
      AnalyticsService.shared.track(.clientError, properties: eventProperties)
    }
  }

  private static func truncate(_ value: String, maxLength: Int = 500) -> String {
    if value.count <= maxLength {
      return value
    }
    return String(value.prefix(maxLength))
  }
}
