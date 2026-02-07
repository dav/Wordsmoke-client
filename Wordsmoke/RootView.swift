import GameKit
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
  @State private var showingJoinSheet = false
  @State private var onboardingStore = OnboardingStore()

  private var theme: AppTheme {
    ThemeSelection(rawValue: themeSelectionRaw)?.theme ?? .system
  }

  private var serverStatusText: String {
    let label = useDevelopment ? "dev" : "prod"
    return "Connected to \(label) server"
  }

  var body: some View {
    RootScaffoldView(
      model: model,
      theme: theme,
      showDebug: showDebug,
      serverStatusText: serverStatusText,
      scenePhase: scenePhase,
      useDevelopment: $useDevelopment,
      developmentURLRaw: $developmentURLRaw,
      showingSettings: $showingSettings,
      showingJoinSheet: $showingJoinSheet,
      onboardingStore: $onboardingStore,
      themeSelectionRaw: $themeSelectionRaw
    )
    .environment(\.appTheme, theme)
    .environment(\.debugEnabled, showDebug)
  }

  private struct RootScaffoldView: View {
    @Bindable var model: AppModel
    let theme: AppTheme
    let showDebug: Bool
    let serverStatusText: String
    let scenePhase: ScenePhase
    @Binding var useDevelopment: Bool
    @Binding var developmentURLRaw: String
    @Binding var showingSettings: Bool
    @Binding var showingJoinSheet: Bool
    @Binding var onboardingStore: OnboardingStore
    @Binding var themeSelectionRaw: String

    var body: some View {
      NavigationStack(path: $model.navigationPath) {
        RootContentView(
          model: model,
          theme: theme,
          showDebug: showDebug,
          serverStatusText: serverStatusText,
          onShowSettings: {
            showingSettings = true
          },
          onShowJoinSheet: {
            showingJoinSheet = true
          }
        )
        .padding()
        .navigationTitle("")
        .navigationBarHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .tint(theme.accent)
        .modifier(RootLifecycleModifier(
          model: model,
          scenePhase: scenePhase,
          useDevelopment: $useDevelopment,
          developmentURLRaw: $developmentURLRaw
        ))
        .modifier(RootSheetsModifier(
          model: model,
          theme: theme,
          showingSettings: $showingSettings,
          showingJoinSheet: $showingJoinSheet,
          onboardingStore: $onboardingStore,
          themeSelectionRaw: $themeSelectionRaw
        ))
      }
    }
  }

  private struct RootLifecycleModifier: ViewModifier {
    @Bindable var model: AppModel
    let scenePhase: ScenePhase
    @Binding var useDevelopment: Bool
    @Binding var developmentURLRaw: String

    func body(content: Content) -> some View {
      content
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
        .onChange(of: model.gameCenter.receivedTurnBasedMatch?.id) { _, _ in
          if let match = model.gameCenter.receivedTurnBasedMatch?.match {
            model.gameCenter.receivedTurnBasedMatch = nil
            Task {
              await model.handleIncomingTurnBasedMatch(match)
            }
          }
        }
    }

    private func updateLobbyPolling(for scenePhase: ScenePhase) {
      let isOnRootScreen = model.navigationPath.count == 0
      if scenePhase == .active, model.session != nil, isOnRootScreen {
        model.startLobbyPolling()
      } else {
        model.stopLobbyPolling()
      }
    }
  }

  private struct RootSheetsModifier: ViewModifier {
    @Bindable var model: AppModel
    let theme: AppTheme
    @Binding var showingSettings: Bool
    @Binding var showingJoinSheet: Bool
    @Binding var onboardingStore: OnboardingStore
    @Binding var themeSelectionRaw: String

    func body(content: Content) -> some View {
      content
        .sheet(item: $model.gameCenter.authenticationViewControllerItem) { item in
          GameCenterAuthView(viewController: item.viewController)
        }
        .sheet(isPresented: $model.showNewGameSheet) {
          NewGameSheetView(
            availableLengths: model.availableGoalLengths,
            defaultLength: model.pendingGoalLength,
            defaultPlayerCount: model.pendingPlayerCount
          ) { goalLength, playerCount in
            Task {
              await model.createGameWithLength(goalLength, playerCount: playerCount)
            }
          } onCancel: {
            model.showNewGameSheet = false
          }
        }
        .sheet(isPresented: $showingJoinSheet) {
          JoinGameSheetView(theme: theme, isBusy: model.isBusy) { joinCode in
            Task {
              let joined = await model.joinGame(joinCode: joinCode)
              if joined {
                showingJoinSheet = false
              }
            }
          } onCancel: {
            showingJoinSheet = false
          }
        }
        .sheet(isPresented: $model.showInvitePlayersSheet) {
          InvitePlayersView(
            appModel: model,
            goalLength: model.pendingGoalLength,
            playerCount: model.pendingPlayerCount
          ) {
            model.dismissInvitePlayers()
          }
        }
        .sheet(item: $model.gameCenter.inviteMatchmakerItem) { item in
          MatchmakerInviteView(invite: item.invite) {
            model.gameCenter.inviteMatchmakerItem = nil
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
  }

  private struct RootContentView: View {
    @Bindable var model: AppModel
    let theme: AppTheme
    let showDebug: Bool
    let serverStatusText: String
    let onShowSettings: () -> Void
    let onShowJoinSheet: () -> Void

    private var activeGames: [GameResponse] {
      model.games.filter { $0.status != "completed" }
    }

    private var completedGames: [GameResponse] {
      model.games
        .filter { $0.status == "completed" }
        .sorted { ($0.endedAt ?? "") > ($1.endedAt ?? "") }
    }

    var body: some View {
      let isLoadingGames = !model.hasLoadedGames

      VStack(alignment: .leading, spacing: theme.sectionSpacing) {
        HeaderView(theme: theme, onShowSettings: onShowSettings)

        if showDebug || model.connectionErrorMessage != nil || !model.gameCenter.isAuthenticated {
          StatusCardView(
            model: model,
            theme: theme,
            showDebug: showDebug,
            serverStatusText: serverStatusText
          )
        }

        if model.session != nil {
          LobbyButtonsView(theme: theme, onShowJoinSheet: onShowJoinSheet) {
            model.presentNewGameSheet()
          }
        }

        if model.session != nil {
          ActiveGamesView(
            games: activeGames,
            title: "Active Games",
            isLoading: isLoadingGames,
            showDebug: showDebug,
            currentPlayerName: model.session?.playerName,
            theme: theme
          ) { game in
            model.selectGame(game)
          }

          CompletedGamesView(
            games: completedGames,
            isLoading: isLoadingGames,
            showDebug: showDebug,
            currentPlayerName: model.session?.playerName,
            theme: theme
          ) { game in
            model.selectGame(game)
          }
        }

        Spacer()
      }
      .task(id: model.session?.token) {
        guard model.session != nil, !model.hasLoadedGames else { return }
        await model.loadGames()
      }
    }
  }

  private struct HeaderView: View {
    let theme: AppTheme
    let onShowSettings: () -> Void

    var body: some View {
      ZStack {
        Text("Wordsmoke")
          .font(.largeTitle)
          .bold()
          .foregroundStyle(theme.textPrimary)
          .frame(maxWidth: .infinity, alignment: .center)

        HStack(spacing: 12) {
          Spacer()
          Button(action: onShowSettings) {
            Image(systemName: "gearshape")
              .font(.system(size: 16, weight: .semibold))
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.bordered)
          .tint(theme.accent)
          .accessibilityIdentifier("settings-button")
        }
      }
    }
  }

  private struct StatusCardView: View {
    @Bindable var model: AppModel
    let theme: AppTheme
    let showDebug: Bool
    let serverStatusText: String

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Status")
          .font(.headline)
          .foregroundStyle(theme.textPrimary)

        Text(serverStatusText)
          .foregroundStyle(theme.textSecondary)

        if model.isBusy {
          ProgressView()
        }

        if model.gameCenter.isAuthenticated {
          if model.session == nil {
            if showDebug {
              Button("Connect to Server") {
                Task {
                  await model.connectToServer()
                }
              }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("connect-server-button")
            } else if let errorMessage = model.connectionErrorMessage {
              Text(errorMessage)
                .foregroundStyle(theme.textSecondary)
            }
          }
        } else {
          Text("Sign in to Game Center to get started.")
        }

        if showDebug, let session = model.session {
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
  }

  private struct LobbyButtonsView: View {
    let theme: AppTheme
    let onShowJoinSheet: () -> Void
    let onStartNewGame: () -> Void

    var body: some View {
      HStack(spacing: 12) {
        Button("New Game", action: onStartNewGame)
          .buttonStyle(AccentPillButtonStyle(theme: theme))
          .accessibilityIdentifier("new-game-button")

        Button("Join Game w/ Invite Code", action: onShowJoinSheet)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("join-game-button")
      }
    }
  }
}
