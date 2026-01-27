import Observation
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Wordsmoke")
          .font(.largeTitle)
          .bold()
          .frame(maxWidth: .infinity, alignment: .center)

        // Debug Status
        VStack(alignment: .leading, spacing: 12) {
          Text("Status")
            .font(.headline)

          Text(model.statusMessage)
            .foregroundStyle(.secondary)

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
        .padding()
        .frame(maxWidth: 520)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemBackground))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color(.separator), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)

        if model.session != nil {
          HStack(spacing: 12) {
            Button("New Game") {
              Task {
                await model.createGameAndInvite(goalLength: 5)
              }
            }
            .buttonStyle(.bordered)
          }
        }

        if model.session != nil {
          let activeGames = model.games.filter { $0.status != "completed" }
          let completedGames = model.games.filter { $0.status == "completed" }
            .sorted { ($0.endedAt ?? "") > ($1.endedAt ?? "") }

          ActiveGamesView(games: activeGames, title: "Active Games") { game in
            model.selectGame(game)
          } onRefresh: {
            Task {
              await model.loadGames()
            }
          }

          CompletedGamesView(games: completedGames) { game in
            model.selectGame(game)
          }
        }

        if let game = model.currentGame, game.status == "waiting" {
          Button("Start Game") {
            Task {
              await model.startGame()
            }
          }
          .buttonStyle(.borderedProminent)
        }

        if let game = model.currentGame, game.status == "active" {
          Button("Enter Game") {
            model.enterGame()
          }
          .buttonStyle(.borderedProminent)
        }

        Spacer()
      }
      .padding()
      .navigationTitle("")
      .navigationBarHidden(true)
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
  let onSelect: (GameResponse) -> Void
  let onRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.title3)
          .bold()
        Spacer()
        Button("Refresh") {
          onRefresh()
        }
        .buttonStyle(.bordered)
      }

      if games.isEmpty {
        Text("No games yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(games, id: \.id) { game in
          Button {
            onSelect(game)
          } label: {
            HStack {
              VStack(alignment: .leading) {
                Text("Join Code: \(game.joinCode)")
                  .font(.callout)
                  .foregroundStyle(.primary)
                Text("Status: \(game.status)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if let playersCount = game.playersCount {
                Text("\(playersCount) players")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }
}

struct CompletedGamesView: View {
  let games: [GameResponse]
  let onSelect: (GameResponse) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Completed Games")
        .font(.title3)
        .bold()

      if games.isEmpty {
        Text("No completed games yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(games, id: \.id) { game in
          Button {
            onSelect(game)
          } label: {
            HStack {
              VStack(alignment: .leading) {
                Text("Join Code: \(game.joinCode)")
                  .font(.callout)
                  .foregroundStyle(.primary)
                if let winnerNames = game.winnerNames, let roundNumber = game.winningRoundNumber, !winnerNames.isEmpty {
                  Text("Won by: \(winnerNames.joined(separator: ", ")) in round \(roundNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let roundNumber = game.winningRoundNumber {
                  Text("Completed in round \(roundNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                  Text("Completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              Spacer()
              if let playersCount = game.playersCount {
                Text("\(playersCount) players")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }
}
