import Observation
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        Text("Wordsmoke")
          .font(.largeTitle)
          .bold()

        Text(model.statusMessage)
          .foregroundStyle(.secondary)

        if model.gameCenter.isAuthenticated {
          Button("Connect to Server") {
            Task {
              await model.connectToServer()
            }
          }
          .buttonStyle(.borderedProminent)
        } else {
          Text("Sign in to Game Center to get started.")
        }

        if let session = model.session {
          SessionSummaryView(session: session)
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
