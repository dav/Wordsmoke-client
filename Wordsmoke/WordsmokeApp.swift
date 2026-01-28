import SwiftUI

@main
struct WordsmokeApp: App {
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
    }
  }
}
