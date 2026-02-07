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
  static let useDevelopmentKey = "server.useDevelopment"
  static let developmentURLKey = "server.developmentURL"
  static let uiTestFlagKey = "WORDSMOKE_UI_TESTS"
  static let baseURLOverrideKey = "WORDSMOKE_BASE_URL"
  static let debugMatchmakingTokenKey = "WORDSMOKE_DEBUG_MATCHMAKING_TOKEN"
  static let defaultDevelopmentURL = URL(string: "https://karoline-unconsulted-oversensibly.ngrok-free.dev")!

  static var defaultServerEnvironment: ServerEnvironment {
    #if DEBUG
    return .development
    #else
    return .production
    #endif
  }

  static var allowsDeveloperSettings: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
  }

  static var useDevelopment: Bool {
    #if DEBUG
    if let stored = UserDefaults.standard.object(forKey: useDevelopmentKey) as? Bool {
      return stored
    }
    return defaultServerEnvironment == .development
    #else
    return false
    #endif
  }

  static var developmentURL: URL {
    if let rawValue = UserDefaults.standard.string(forKey: developmentURLKey),
       let url = URL(string: rawValue) {
      return url
    }
    return defaultDevelopmentURL
  }

  static var baseURL: URL {
    #if DEBUG
    if let override = ProcessInfo.processInfo.environment[baseURLOverrideKey],
       let url = URL(string: override) {
      return url
    }
    return useDevelopment ? developmentURL : ServerEnvironment.production.baseURL
    #else
    return ServerEnvironment.production.baseURL
    #endif
  }

  static var isUITest: Bool {
    ProcessInfo.processInfo.environment[uiTestFlagKey] == "1"
  }

  static var debugMatchmakingToken: String? {
  #if DEBUG
    if let token = ProcessInfo.processInfo.environment[debugMatchmakingTokenKey] {
      return token
    }
    if let token = Bundle.main.object(forInfoDictionaryKey: debugMatchmakingTokenKey) as? String {
      return token
    }
    return nil
  #else
    return nil
  #endif
  }
}
