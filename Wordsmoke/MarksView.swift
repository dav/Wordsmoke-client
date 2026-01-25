import SwiftUI

struct MarksView: View {
  let marks: [String]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(marks.indices, id: \.self) { index in
        Text(symbol(for: marks[index]))
          .font(.caption)
          .bold()
          .frame(width: 18, height: 18)
          .background(background(for: marks[index]))
          .foregroundStyle(.white)
          .clipShape(.rect(cornerRadius: 4))
      }
    }
  }

  private func symbol(for mark: String) -> String {
    switch mark {
    case "correct":
      return "C"
    case "present":
      return "P"
    default:
      return "A"
    }
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
