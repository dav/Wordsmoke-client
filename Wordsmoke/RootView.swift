import Observation
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("theme.selection") private var themeSelectionRaw = ThemeSelection.system.rawValue
  @AppStorage(AppEnvironment.useDevelopmentKey) private var useDevelopment =
    AppEnvironment.defaultServerEnvironment == .development
  @AppStorage(AppEnvironment.developmentURLKey) private var developmentURLRaw =
    AppEnvironment.defaultDevelopmentURL.absoluteString
  @AppStorage("debug.enabled") private var showDebug = false
  @State private var showingSettings = false
  @State private var onboardingStore = OnboardingStore()

  private var theme: AppTheme {
    ThemeSelection(rawValue: themeSelectionRaw)?.theme ?? .system
  }

  private var serverStatusText: String {
    let label = useDevelopment ? "dev" : "prod"
    return "Connected to \(label) server"
  }

  private func updateLobbyPolling(for scenePhase: ScenePhase) {
    let isOnRootScreen = model.navigationPath.count == 0
    if scenePhase == .active, model.session != nil, isOnRootScreen {
      model.startLobbyPolling()
    } else {
      model.stopLobbyPolling()
    }
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
        updateLobbyPolling(for: scenePhase)
      }
      .onDisappear {
        model.stopLobbyPolling()
      }
      .onChange(of: model.gameCenter.isAuthenticated) { _, _ in
        model.handleAuthChange()
      }
      .onChange(of: model.session?.token) { _, _ in
        if model.session != nil {
          Task {
            await model.loadGames()
          }
          updateLobbyPolling(for: scenePhase)
        } else {
          model.stopLobbyPolling()
        }
      }
      .onChange(of: model.navigationPath.count) { _, _ in
        updateLobbyPolling(for: scenePhase)
      }
      .onChange(of: scenePhase) { _, newValue in
        updateLobbyPolling(for: newValue)
      }
      .onChange(of: useDevelopment) { _, _ in
        model.updateBaseURLIfNeeded()
      }
      .onChange(of: developmentURLRaw) { _, _ in
        model.updateBaseURLIfNeeded()
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
          onboarding: onboardingStore,
          analytics: model.analytics
        )
      }
      .navigationDestination(for: AppRoute.self) { route in
        switch route {
        case .game:
          if let gameRoomModel = model.gameRoomModel {
            GameRoomView(model: gameRoomModel, onboarding: onboardingStore, analytics: model.analytics)
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
