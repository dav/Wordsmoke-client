import Observation
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @AppStorage("theme.selection") private var themeSelectionRaw = ThemeSelection.system.rawValue
  @AppStorage(AppEnvironment.serverEnvironmentKey) private var serverEnvironmentRaw =
    AppEnvironment.defaultServerEnvironment.rawValue
  @AppStorage("debug.enabled") private var showDebug = false
  @State private var showingSettings = false

  private var theme: AppTheme {
    ThemeSelection(rawValue: themeSelectionRaw)?.theme ?? .system
  }

  private var serverStatusText: String {
    let environment = AppEnvironment.serverEnvironment(from: serverEnvironmentRaw)
    let label = environment == .production ? "prod" : "dev"
    return "Connected to \(label) server"
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
            .accessibilityIdentifier("settings-button")
          }
        }

        if showDebug {
          // Debug Status
          VStack(alignment: .leading, spacing: 12) {
            Text("Status")
              .font(.headline)
              .foregroundStyle(theme.textPrimary)

            Text(serverStatusText)
              .foregroundStyle(theme.textSecondary)

            if model.gameCenter.isAuthenticated {
              if model.session == nil {
                Button("Connect to Server") {
                  Task {
                    await model.connectToServer()
                  }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("connect-server-button")
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
            .accessibilityIdentifier("new-game-button")
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
          .accessibilityIdentifier("start-game-root-button")
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
      .environment(\.debugEnabled, showDebug)
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
      .onChange(of: serverEnvironmentRaw) { _, newValue in
        model.updateServerEnvironment(AppEnvironment.serverEnvironment(from: newValue))
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
        SettingsView(
          themeSelectionRaw: $themeSelectionRaw,
          serverEnvironmentRaw: $serverEnvironmentRaw
        )
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
    .environment(\.appTheme, theme)
    .environment(\.debugEnabled, showDebug)
  }
}
