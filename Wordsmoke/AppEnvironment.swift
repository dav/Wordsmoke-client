import Foundation

enum ServerEnvironment: String, CaseIterable, Identifiable {
  case development
  case production

  var id: String { rawValue }

  var title: String {
    switch self {
    case .development:
      return "Development"
    case .production:
      return "Production"
    }
  }

  var detail: String {
    switch self {
    case .development:
      return "Preview and staging features"
    case .production:
      return "Live service"
    }
  }

  var baseURL: URL {
    switch self {
    case .development:
      return URL(string: "https://karoline-unconsulted-oversensibly.ngrok-free.dev")!
    case .production:
      return URL(string: "https://wordsmoke.akuaku.org")!
    }
  }
}

enum AppEnvironment {
  static let serverEnvironmentKey = "server.environment"

  static var defaultServerEnvironment: ServerEnvironment {
    #if DEBUG
    return .development
    #else
    return .production
    #endif
  }

  static func serverEnvironment(from rawValue: String?) -> ServerEnvironment {
    guard let rawValue, let environment = ServerEnvironment(rawValue: rawValue) else {
      return defaultServerEnvironment
    }
    return environment
  }

  static var serverEnvironment: ServerEnvironment {
    serverEnvironment(from: UserDefaults.standard.string(forKey: serverEnvironmentKey))
  }

  static var baseURL: URL {
    serverEnvironment.baseURL
  }
}
