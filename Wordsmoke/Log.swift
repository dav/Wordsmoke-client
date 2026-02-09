import Foundation
import Sentry

enum LogLevel: String {
  case debug
  case info
  case warning
  case error
  case critical

  var sendsAmplitudeTelemetry: Bool {
    switch self {
    case .warning, .error, .critical:
      return true
    case .debug, .info:
      return false
    }
  }
}

enum LogCategory: String {
  case api
  case appModel = "app_model"
  case gameCenter = "game_center"
  case actionCable = "action_cable"
  case matchmaking
  case push
  case build
}

enum Log {
  static func log(
    _ message: String,
    level: LogLevel = .debug,
    category: LogCategory = .appModel,
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
    sendRemoteTelemetry(level: level, message: message, payload: payload)
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

  private static func sendRemoteTelemetry(level: LogLevel, message: String, payload: [String: String]) {
    #if DEBUG
    return
    #else
    // Sentry structured logging — all levels
    let sentryLogger = SentrySDK.logger
    var attributes: [String: String] = [:]
    for (key, value) in payload where key != "message" && key != "log_level" {
      attributes[key] = value
    }

    switch level {
    case .debug:
      sentryLogger.debug(message, attributes: attributes)
    case .info:
      sentryLogger.info(message, attributes: attributes)
    case .warning:
      sentryLogger.warn(message, attributes: attributes)
    case .error:
      sentryLogger.error(message, attributes: attributes)
    case .critical:
      sentryLogger.fatal(message, attributes: attributes)
    }

    // Amplitude — warning+ only
    guard level.sendsAmplitudeTelemetry else { return }

    Task { @MainActor in
      var eventProperties: [String: Any] = [:]
      for (key, value) in payload {
        eventProperties[key] = value
      }
      AnalyticsService.shared.track(.clientError, properties: eventProperties)
    }
    #endif
  }

  private static func truncate(_ value: String, maxLength: Int = 500) -> String {
    if value.count <= maxLength {
      return value
    }
    return String(value.prefix(maxLength))
  }
}
