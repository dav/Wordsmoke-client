import SwiftUI
import Sentry


@main
struct WordsmokeApp: App {
  @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

  init() {
    SentrySDK.start { options in
      options.dsn = "https://a9da4f45c58827135f838b57f7b98907@o4510851360620544.ingest.us.sentry.io/4510851370123264"

      // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
      //options.sendDefaultPii = true // Adds IP for users.

      // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
      // We recommend adjusting this value in production.
      options.tracesSampleRate = 0.2

      // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
      options.configureProfiling = {
        $0.sessionSampleRate = 0.5 // We recommend adjusting this value in production.
        $0.lifecycle = .trace
      }

      options.attachScreenshot = true // This adds a screenshot to the error events
      // options.attachViewHierarchy = true // This adds the view hierarchy to the error events

      options.experimental.enableLogs = true // Enable experimental logging features
    }
  }

  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .onChange(of: scenePhase) { _, newValue in
          if newValue == .active {
            Task {
              await model.refreshClientPolicy()
            }
          }
        }
        .onAppear {
          appDelegate.pushService = model.pushService
        }
    }
  }
}
