import SwiftUI

struct InviteeRowView: View {
  let invitee: MatchmakingInvitee
  let isSelected: Bool
  let onToggle: () -> Void
  @Environment(\.appTheme) private var theme

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: theme.cellPadding) {
        ZStack {
          Circle()
            .fill(theme.accent.opacity(0.15))
            .frame(width: 36, height: 36)
          Text(initials(for: invitee.displayName))
            .foregroundStyle(theme.accent)
            .bold()
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(invitee.displayName)
            .foregroundStyle(theme.textPrimary)
          if let subtitle = invitee.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(theme.textSecondary)
          }
        }

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("invitee-row-\(invitee.id)")
  }

  private func initials(for name: String) -> String {
    let parts = name.split(separator: " ")
    let initials = parts.prefix(2).compactMap { $0.first }
    return String(initials).uppercased()
  }
}
