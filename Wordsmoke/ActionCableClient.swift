import Foundation

@MainActor
final class ActionCableClient {
  private let url: URL
  private var webSocketTask: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  var onMessage: (([String: Any]) -> Void)?

  init(url: URL) {
    self.url = url
  }

  func connect() {
    disconnect()
    let request = URLRequest(url: url)
    let task = URLSession.shared.webSocketTask(with: request)
    webSocketTask = task
    task.resume()
    listen()
  }

  func disconnect() {
    receiveTask?.cancel()
    receiveTask = nil
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
  }

  func subscribe(identifier: String) {
    let payload: [String: Any] = [
      "command": "subscribe",
      "identifier": identifier
    ]
    send(payload)
  }

  func send(_ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let text = String(data: data, encoding: .utf8) else {
      return
    }

    Task {
      do {
        try await webSocketTask?.send(.string(text))
      } catch {
        ErrorReporter.log(
          "Action Cable send failed",
          level: .warning,
          category: .actionCable,
          error: error,
          metadata: ["operation": "send"]
        )
      }
    }
  }

  private func listen() {
    receiveTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          guard let message = try await webSocketTask?.receive() else {
            return
          }
          switch message {
          case .string(let text):
            handle(text)
          case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
              handle(text)
            }
          @unknown default:
            break
          }
        } catch {
          ErrorReporter.log(
            "Action Cable receive failed",
            level: .warning,
            category: .actionCable,
            error: error,
            metadata: ["operation": "receive"]
          )
          return
        }
      }
    }
  }

  private func handle(_ text: String) {
    guard let data = text.data(using: .utf8),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return
    }
    guard let message = payload["message"] as? [String: Any] else {
      return
    }
    onMessage?(message)
  }
}
