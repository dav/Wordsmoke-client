import Observation
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      VStack(alignment: .leading) {
        Text("Wordsmoke")
          .font(.largeTitle)
          .bold()

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
          } else {
            Text("Connected to server.")
              .foregroundStyle(.secondary)
          }
        } else {
          Text("Sign in to Game Center to get started.")
        }

        if let session = model.session {
          SessionSummaryView(session: session)
        }

        if model.session != nil {
          HStack(spacing: 12) {
            Button("Create Game") {
              Task {
                await model.createGameAndInvite(goalLength: 5)
              }
            }
            .buttonStyle(.bordered)

            if model.currentGame != nil {
              Button("Refresh Game") {
                Task {
                  await model.refreshGame()
                }
              }
              .buttonStyle(.bordered)
            }
          }
        }

        if model.session != nil {
          ActiveGamesView(games: model.games) { game in
            model.selectGame(game)
          } onRefresh: {
            Task {
              await model.loadGames()
            }
          }
        }

        if let game = model.currentGame {
          GameSummaryView(game: game)
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
      Text("Player: \(session.playerID)")
        .font(.callout)
      Text("Account: \(session.accountID)")
        .font(.callout)
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
  let onSelect: (GameResponse) -> Void
  let onRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Active Games")
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
