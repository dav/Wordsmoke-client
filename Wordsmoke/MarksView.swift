import SwiftUI

struct MarksView: View {
  let marks: [String]
  let letters: [String]?
  let size: CGFloat
  var phrase: String?
  var isOtherPlayer: Bool = false
  @State private var tappedTileIndex: Int?

  var body: some View {
    HStack(spacing: 6) {
      ForEach(marks.indices, id: \.self) { index in
        Text(displayText(for: index))
          .font(.caption)
          .bold()
          .frame(width: size, height: size)
          .background(background(for: marks[index]))
          .foregroundStyle(.white)
          .clipShape(.rect(cornerRadius: 6))
          .onTapGesture {
            tappedTileIndex = index
          }
      }
    }
    .alert(
      tileAlertTitle,
      isPresented: Binding(
        get: { tappedTileIndex != nil },
        set: { if !$0 { tappedTileIndex = nil } }
      )
    ) {
      Button("OK") { tappedTileIndex = nil }
    } message: {
      Text(tileAlertMessage)
    }
  }

  private var tileAlertTitle: String {
    guard let index = tappedTileIndex else { return "" }
    if let letters, index < letters.count {
      return "Letter: \(letters[index].uppercased())"
    }
    return "Tile Info"
  }

  private var tileAlertMessage: String {
    guard let index = tappedTileIndex else { return "" }
    let mark = index < marks.count ? marks[index] : ""
    var message = colorExplanation(for: mark)
    if isOtherPlayer, let phrase, !phrase.isEmpty {
      message += "\n\nThis letter had to appear in the phrase: \"\(phrase)\""
    }
    return message
  }

  private func colorExplanation(for mark: String) -> String {
    switch mark {
    case "🟩":
      return "Green means this letter is in the goal word and is in the correct position."
    case "🟨":
      return "Orange means this letter is in the goal word, but not at this position."
    default:
      return "Gray means this letter is not in the goal word."
    }
  }

  private func displayText(for index: Int) -> String {
    guard let letters, index < letters.count else {
      return ""
    }
    return letters[index].uppercased()
  }

  private func background(for mark: String) -> Color {
    switch mark {
    case "🟩":
      return .green
    case "🟨":
      return .orange
    default:
      return .gray
    }
  }
}
