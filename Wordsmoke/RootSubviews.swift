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

struct ActiveGamesView: View {
  let games: [GameResponse]
  let title: String
  let showDebug: Bool
  let currentPlayerName: String?
  let theme: AppTheme
  let onSelect: (GameResponse) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.title3)
        .bold()
        .foregroundStyle(theme.textPrimary)

      if games.isEmpty {
        Text("No games yet.")
          .foregroundStyle(theme.textSecondary)
      } else {
        ForEach(games, id: \.id) { game in
          Button {
            onSelect(game)
          } label: {
            if showDebug {
              HStack {
                VStack(alignment: .leading) {
                  let participantNames = playerNames(for: game, omittingCurrentPlayer: true)
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
                playerNamesLine(for: game)
                  .font(.callout)
                  .foregroundStyle(theme.textPrimary)
                Text(statusLine(for: game))
                  .font(.caption)
                  .foregroundStyle(theme.textSecondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(CardButtonStyle(theme: theme))
        }
      }
    }
  }

  private func playerNamesLine(for game: GameResponse) -> Text {
    let names = playerNames(for: game, omittingCurrentPlayer: true)
    if names.isEmpty {
      return Text("Players unavailable")
    }
    return Text(names.joined(separator: ", "))
  }

  private func playerNames(for game: GameResponse, omittingCurrentPlayer: Bool) -> [String] {
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

  private func statusLine(for game: GameResponse) -> String {
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

struct CompletedGamesView: View {
  let games: [GameResponse]
  let showDebug: Bool
  let currentPlayerName: String?
  let theme: AppTheme
  let onSelect: (GameResponse) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Completed Games")
        .font(.title3)
        .bold()
        .foregroundStyle(theme.textPrimary)

      if games.isEmpty {
        Text("No completed games yet.")
          .foregroundStyle(theme.textSecondary)
      } else {
        ForEach(games, id: \.id) { game in
          Button {
            onSelect(game)
          } label: {
            if showDebug {
              HStack {
                VStack(alignment: .leading) {
                  let participantNames = playerNames(for: game)
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
                playerNamesLineWithTrophies(for: game)
                  .font(.callout)
                  .foregroundStyle(theme.textPrimary)
                Text(completedRoundsLine(for: game))
                  .font(.caption)
                  .foregroundStyle(theme.textSecondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(CardButtonStyle(theme: theme))
        }
      }
    }
  }

  private func playerNamesLineWithTrophies(for game: GameResponse) -> some View {
    let names = playerNames(for: game)
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

  private func playerNames(for game: GameResponse) -> [String] {
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

  private func completedRoundsLine(for game: GameResponse) -> String {
    if let roundNumber = game.winningRoundNumber {
      return "\(roundNumber) rounds"
    }
    if let roundsCount = game.rounds?.count {
      return "\(roundsCount) rounds"
    }
    return "rounds ?"
  }
}
