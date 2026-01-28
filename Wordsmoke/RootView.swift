import Observation
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @AppStorage("theme.selection") private var themeSelectionRaw = ThemeSelection.system.rawValue
  @State private var showDebug = false
  @State private var showingSettings = false

  private var theme: AppTheme {
    ThemeSelection(rawValue: themeSelectionRaw)?.theme ?? .system
  }

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      VStack(alignment: .leading, spacing: theme.sectionSpacing) {
        ZStack {
          Text("Wordsmoke")
            .font(.largeTitle)
            .bold()
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)

          HStack(spacing: 12) {
            Spacer()
            Button {
              showingSettings = true
            } label: {
              Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)

            Toggle(isOn: $showDebug) {
            }
            .toggleStyle(.switch)
            .tint(theme.accent)
          }
        }

        if showDebug {
          // Debug Status
          VStack(alignment: .leading, spacing: 12) {
            Text("Status")
              .font(.headline)
              .foregroundStyle(theme.textPrimary)

            Text(model.statusMessage)
              .foregroundStyle(theme.textSecondary)

            if model.gameCenter.isAuthenticated {
              if model.session == nil {
                Button("Connect to Server") {
                  Task {
                    await model.connectToServer()
                  }
                }
                .buttonStyle(.borderedProminent)
              }
            } else {
              Text("Sign in to Game Center to get started.")
            }

            if let session = model.session {
              SessionSummaryView(session: session)
            }
          }
          .padding(theme.cellPadding)
          .frame(maxWidth: 520)
          .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
              .fill(theme.cardBackground)
          )
          .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
              .stroke(theme.border, lineWidth: theme.borderWidth)
          )
          .frame(maxWidth: .infinity, alignment: .center)
        }

        if model.session != nil {
          HStack(spacing: 12) {
            Button("New Game") {
              Task {
                await model.createGameAndInvite(goalLength: 5)
              }
            }
            .buttonStyle(AccentPillButtonStyle(theme: theme))
          }
        }

        if model.session != nil {
          let activeGames = model.games.filter { $0.status != "completed" }
          let completedGames = model.games.filter { $0.status == "completed" }
            .sorted { ($0.endedAt ?? "") > ($1.endedAt ?? "") }

          ActiveGamesView(
            games: activeGames,
            title: "Active Games",
            showDebug: showDebug,
            currentPlayerName: model.session?.playerName,
            theme: theme
          ) { game in
            model.selectGame(game)
          }

          CompletedGamesView(
            games: completedGames,
            showDebug: showDebug,
            currentPlayerName: model.session?.playerName,
            theme: theme
          ) { game in
            model.selectGame(game)
          }
        }

        if let game = model.currentGame, game.status == "waiting" {
          Button("Start Game") {
            Task {
              await model.startGame()
            }
          }
          .buttonStyle(AccentPillButtonStyle(theme: theme))
        }

        if let game = model.currentGame, game.status == "active" {
          Button("Enter Game") {
            model.enterGame()
          }
          .buttonStyle(AccentPillButtonStyle(theme: theme))
        }

        Spacer()
      }
      .padding()
      .navigationTitle("")
      .navigationBarHidden(true)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.background)
      .tint(theme.accent)
      .environment(\.appTheme, theme)
      .task {
        await model.start()
      }
      .onChange(of: model.gameCenter.isAuthenticated) { _, _ in
        model.handleAuthChange()
      }
      .onChange(of: model.session?.token) { _, _ in
        if model.session != nil {
          Task {
            await model.loadGames()
          }
        }
      }
      .sheet(item: $model.gameCenter.authenticationViewControllerItem) { item in
        GameCenterAuthView(viewController: item.viewController)
      }
      .sheet(item: $model.inviteSheet) { sheet in
        MatchmakerView(
          joinCode: sheet.joinCode,
          minPlayers: sheet.minPlayers,
          maxPlayers: sheet.maxPlayers
        ) {
          model.dismissInviteSheet()
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView(themeSelectionRaw: $themeSelectionRaw)
      }
      .navigationDestination(for: AppRoute.self) { route in
        switch route {
        case .game:
          if let gameRoomModel = model.gameRoomModel {
            GameRoomView(model: gameRoomModel)
          } else {
            Text("Game unavailable")
          }
        }
      }
    }
  }
}

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

  private func normalizedNames(from names: [String], omittingCurrentPlayer: Bool, currentName: String?) -> [String] {
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
                  if let winnerNames = game.winnerNames, let roundNumber = game.winningRoundNumber, !winnerNames.isEmpty {
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
    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
