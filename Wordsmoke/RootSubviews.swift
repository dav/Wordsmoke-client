import SwiftUI

struct SessionSummaryView: View {
  let session: SessionResponse

  var body: some View {
    VStack(alignment: .leading) {
      Text("Session")
        .font(.title2)
        .bold()
      Text("Player: \(session.playerName ?? "Unknown")")
        .font(.callout)
      Text(session.playerID)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

struct GameSummaryView: View {
  let game: GameResponse

  var body: some View {
    VStack(alignment: .leading) {
      Text("Game")
        .font(.title2)
        .bold()
      Text("Join Code: \(game.joinCode)")
        .font(.callout)
      Text("Status: \(game.status)")
        .font(.callout)
      if let playersCount = game.playersCount {
        Text("Players: \(playersCount)")
          .font(.callout)
      }
    }
  }
}

struct ActiveGameRow: View {
  let game: GameResponse
  let showDebug: Bool
  let currentPlayerName: String?
  let currentPlayerID: String?
  let theme: AppTheme
  let onSelect: () -> Void
  var onDelete: (() -> Void)?

  private var canDelete: Bool {
    guard let currentPlayerID, let creatorId = game.creatorId else { return false }
    return game.status == "waiting" && creatorId == currentPlayerID
  }

  var body: some View {
    Button(action: onSelect) {
      if showDebug {
        HStack {
          VStack(alignment: .leading) {
            let participantNames = playerNames(omittingCurrentPlayer: true)
            if !participantNames.isEmpty {
              Text(participantNames.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }
            Text("Join Code: \(game.joinCode)")
              .font(.callout)
              .foregroundStyle(theme.textPrimary)
            Text("Status: \(game.status)")
              .font(.caption)
              .foregroundStyle(theme.textSecondary)
          }
          Spacer()
          if let playersCount = game.playersCount {
            Text("\(playersCount) players")
              .font(.caption)
              .foregroundStyle(theme.textSecondary)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          playerNamesLine
            .font(.callout)
            .foregroundStyle(theme.textPrimary)
          Text(statusLine)
            .font(.caption)
            .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(CardButtonStyle(theme: theme))
    .accessibilityIdentifier("active-game-\(game.id)")
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if canDelete {
        Button(role: .destructive) {
          onDelete?()
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }
    .contextMenu {
      if canDelete {
        Button(role: .destructive) {
          onDelete?()
        } label: {
          Label("Delete Game", systemImage: "trash")
        }
      }
    }
  }

  private var playerNamesLine: Text {
    let names = playerNames(omittingCurrentPlayer: true)
    if names.isEmpty {
      return Text("Players unavailable")
    }
    return Text(names.joined(separator: ", "))
  }

  private func playerNames(omittingCurrentPlayer: Bool) -> [String] {
    let currentName = currentPlayerName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let participantNames = game.participantNames {
      return normalizedNames(
        from: participantNames,
        omittingCurrentPlayer: omittingCurrentPlayer,
        currentName: currentName
      )
    }
    if let participants = game.participants {
      return normalizedNames(
        from: participants.map { $0.player.displayName },
        omittingCurrentPlayer: omittingCurrentPlayer,
        currentName: currentName
      )
    }
    if let winnerNames = game.winnerNames {
      return normalizedNames(
        from: winnerNames,
        omittingCurrentPlayer: omittingCurrentPlayer,
        currentName: currentName
      )
    }
    return []
  }

  private func normalizedNames(
    from names: [String],
    omittingCurrentPlayer: Bool,
    currentName: String?
  ) -> [String] {
    let filtered = names.filter { name in
      guard omittingCurrentPlayer, let currentName else { return true }
      return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != currentName
    }
    return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var statusLine: String {
    if game.status == "waiting" {
      return "not started"
    }

    let currentRoundNumber = game.currentRoundNumber ?? game.rounds?
      .first(where: { $0.id == game.currentRoundID })?
      .number ?? game.rounds?.last?.number
    if let currentRoundNumber {
      return "round \(currentRoundNumber)"
    }
    return "round ?"
  }
}

struct CompletedGameRow: View {
  let game: GameResponse
  let showDebug: Bool
  let currentPlayerName: String?
  let theme: AppTheme
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      if showDebug {
        HStack {
          VStack(alignment: .leading) {
            let participantNames = playerNames
            if !participantNames.isEmpty {
              Text(participantNames.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }
            Text("Join Code: \(game.joinCode)")
              .font(.callout)
              .foregroundStyle(theme.textPrimary)
            if let winnerNames = game.winnerNames,
               let roundNumber = game.winningRoundNumber,
               !winnerNames.isEmpty {
              Text("Won by: \(winnerNames.joined(separator: ", ")) in round \(roundNumber)")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            } else if let roundNumber = game.winningRoundNumber {
              Text("Completed in round \(roundNumber)")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            } else {
              Text("Completed")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }
          }
          Spacer()
          if let playersCount = game.playersCount {
            Text("\(playersCount) players")
              .font(.caption)
              .foregroundStyle(theme.textSecondary)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          playerNamesLineWithTrophies
            .font(.callout)
            .foregroundStyle(theme.textPrimary)
          Text(completedRoundsLine)
            .font(.caption)
            .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(CardButtonStyle(theme: theme))
    .accessibilityIdentifier("completed-game-\(game.id)")
  }

  private var playerNamesLineWithTrophies: some View {
    let names = playerNames
    let winners = Set(game.winnerNames ?? [])

    return HStack(spacing: 0) {
      if names.isEmpty {
        Text("Players unavailable")
      } else {
        ForEach(Array(names.enumerated()), id: \.offset) { index, name in
          if index > 0 {
            Text(", ")
          }
          if winners.contains(name) {
            Image(systemName: "trophy.fill")
              .foregroundStyle(theme.accent)
              .padding(.trailing, 4)
          }
          Text(name)
        }
      }
    }
  }

  private var playerNames: [String] {
    if let participantNames = game.participantNames {
      return normalizedNames(from: participantNames)
    }
    if let participants = game.participants {
      return normalizedNames(from: participants.map { $0.player.displayName })
    }
    if let winnerNames = game.winnerNames {
      return normalizedNames(from: winnerNames)
    }
    return []
  }

  private func normalizedNames(from names: [String]) -> [String] {
    names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var completedRoundsLine: String {
    if let roundNumber = game.winningRoundNumber {
      return "\(roundNumber) rounds"
    }
    if let roundsCount = game.rounds?.count {
      return "\(roundsCount) rounds"
    }
    return "rounds ?"
  }
}

struct InviteShareSheetView: View {
  let joinCode: String
  let theme: AppTheme
  let onDone: () -> Void

  var body: some View {
    let shareMessage = "Join my Wordsmoke game with code \(joinCode)."
    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
      Text("Invite Players")
        .font(.title2)
        .bold()
        .foregroundStyle(theme.textPrimary)

      VStack(alignment: .leading, spacing: theme.cellPadding) {
        Text("Join Code")
          .font(.headline)
          .foregroundStyle(theme.textSecondary)
        Text(joinCode)
          .font(.largeTitle)
          .bold()
          .foregroundStyle(theme.textPrimary)
          .textSelection(.enabled)
      }
      .padding(theme.cellPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
          .fill(theme.cardBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
          .stroke(theme.border, lineWidth: theme.borderWidth)
      )

      Text("Share this code so others can join from the Join Game screen.")
        .foregroundStyle(theme.textSecondary)

      ShareLink(item: shareMessage) {
        Label("Share Invite", systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)

      Button("Done") {
        onDone()
      }
      .buttonStyle(.bordered)
    }
    .padding()
    .background(theme.background)
  }
}

struct JoinGameSheetView: View {
  let theme: AppTheme
  let isBusy: Bool
  let onJoin: (String) -> Void
  let onCancel: () -> Void
  @State private var joinCode = ""

  var body: some View {
    let cleanedCode = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
    let isJoinDisabled = cleanedCode.isEmpty || isBusy

    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
      Text("Join Game")
        .font(.title2)
        .bold()
        .foregroundStyle(theme.textPrimary)

      Text("Enter the join code you received from the host.")
        .foregroundStyle(theme.textSecondary)

      TextField("Join code", text: $joinCode)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .padding(theme.cellPadding)
        .background(
          RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
            .fill(theme.cardBackground)
        )
        .overlay(
          RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
            .stroke(theme.border, lineWidth: theme.borderWidth)
        )

      Button("Join") {
        onJoin(cleanedCode)
      }
      .buttonStyle(.borderedProminent)
      .disabled(isJoinDisabled)

      Button("Cancel") {
        onCancel()
      }
      .buttonStyle(.bordered)
    }
    .padding()
    .background(theme.background)
  }
}
