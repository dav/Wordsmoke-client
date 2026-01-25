import SwiftUI

struct MarksView: View {
  let marks: [String]
  let letters: [String]?
  let size: CGFloat

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
      }
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
    case "correct":
      return .green
    case "present":
      return .orange
    default:
      return .gray
    }
  }
}
