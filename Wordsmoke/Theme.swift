import SwiftUI

enum ThemeSelection: String, CaseIterable, Identifiable, Hashable {
  case system
  case sunrise
  case ocean
  case forest

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system:
      return "System"
    case .sunrise:
      return "Sunrise"
    case .ocean:
      return "Ocean"
    case .forest:
      return "Forest"
    }
  }

  var description: String {
    switch self {
    case .system:
      return "Match iOS system colors and accent."
    case .sunrise:
      return "Warm, friendly highlights."
    case .ocean:
      return "Cool, crisp accents."
    case .forest:
      return "Earthy, grounded tones."
    }
  }

  var theme: AppTheme {
    switch self {
    case .system:
      return .system
    case .sunrise:
      return .sunrise
    case .ocean:
      return .ocean
    case .forest:
      return .forest
    }
  }
}

struct AppTheme {
  let accent: Color
  let background: Color
  let cardBackground: Color
  let textPrimary: Color
  let textSecondary: Color
  let border: Color
  let cornerRadius: CGFloat
  let borderWidth: CGFloat
  let cellPadding: CGFloat
  let sectionSpacing: CGFloat

  static let system = AppTheme(
    accent: .accentColor,
    background: Color(.systemBackground),
    cardBackground: Color(.secondarySystemBackground),
    textPrimary: Color(.label),
    textSecondary: Color(.secondaryLabel),
    border: Color(.separator),
    cornerRadius: 14,
    borderWidth: 1,
    cellPadding: 14,
    sectionSpacing: 16
  )

  static let sunrise = AppTheme(
    accent: Color(red: 0.93, green: 0.44, blue: 0.25),
    background: Color(red: 0.99, green: 0.97, blue: 0.94),
    cardBackground: Color(red: 0.99, green: 0.92, blue: 0.86),
    textPrimary: Color(red: 0.20, green: 0.12, blue: 0.08),
    textSecondary: Color(red: 0.45, green: 0.28, blue: 0.20),
    border: Color(red: 0.92, green: 0.78, blue: 0.69),
    cornerRadius: 16,
    borderWidth: 1,
    cellPadding: 16,
    sectionSpacing: 18
  )

  static let ocean = AppTheme(
    accent: Color(red: 0.15, green: 0.55, blue: 0.78),
    background: Color(red: 0.95, green: 0.98, blue: 1.00),
    cardBackground: Color(red: 0.90, green: 0.95, blue: 0.99),
    textPrimary: Color(red: 0.07, green: 0.18, blue: 0.27),
    textSecondary: Color(red: 0.25, green: 0.40, blue: 0.52),
    border: Color(red: 0.78, green: 0.87, blue: 0.93),
    cornerRadius: 16,
    borderWidth: 1,
    cellPadding: 16,
    sectionSpacing: 18
  )

  static let forest = AppTheme(
    accent: Color(red: 0.18, green: 0.52, blue: 0.32),
    background: Color(red: 0.96, green: 0.98, blue: 0.96),
    cardBackground: Color(red: 0.90, green: 0.95, blue: 0.91),
    textPrimary: Color(red: 0.10, green: 0.20, blue: 0.12),
    textSecondary: Color(red: 0.28, green: 0.40, blue: 0.30),
    border: Color(red: 0.78, green: 0.86, blue: 0.79),
    cornerRadius: 16,
    borderWidth: 1,
    cellPadding: 16,
    sectionSpacing: 18
  )
}

private struct AppThemeKey: EnvironmentKey {
  static let defaultValue = AppTheme.system
}

extension EnvironmentValues {
  var appTheme: AppTheme {
    get { self[AppThemeKey.self] }
    set { self[AppThemeKey.self] = newValue }
  }
}

private struct DebugEnabledKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var debugEnabled: Bool {
    get { self[DebugEnabledKey.self] }
    set { self[DebugEnabledKey.self] = newValue }
  }
}

struct CardButtonStyle: ButtonStyle {
  let theme: AppTheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(theme.cellPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.cardBackground)
      .overlay(
        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
          .stroke(theme.border, lineWidth: theme.borderWidth)
      )
      .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

struct AccentPillButtonStyle: ButtonStyle {
  let theme: AppTheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
      .foregroundStyle(Color.white)
      .clipShape(Capsule())
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
