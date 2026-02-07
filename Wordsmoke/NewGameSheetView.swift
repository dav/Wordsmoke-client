import SwiftUI

struct NewGameSheetView: View {
  let availableLengths: [Int]
  let onCreate: (Int) -> Void
  let onCancel: () -> Void

  @State private var selectedLength: Int

  init(availableLengths: [Int], defaultLength: Int, onCreate: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
    self.availableLengths = availableLengths
    self.onCreate = onCreate
    self.onCancel = onCancel
    self._selectedLength = State(initialValue: availableLengths.contains(defaultLength) ? defaultLength : availableLengths.first ?? 5)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Select Word Length") {
          VStack(alignment: .leading) {
            Picker("Letters", selection: $selectedLength) {
              ForEach(availableLengths, id: \.self) { length in
                Text("\(length) letters").tag(length)
              }
            }
            .pickerStyle(.segmented)
            Spacer()
            HStack(spacing: 6) {
              ForEach(0..<selectedLength, id: \.self) { _ in
                Text("?")
                  .font(.caption)
                  .bold()
                  .frame(width: 36, height: 36)
                  .background(Color.white)
                  .foregroundStyle(.black)
                  .clipShape(.rect(cornerRadius: 6))
                  .overlay(
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Color.black, lineWidth: 1)
                  )
              }
            }
            Text("Select number of letters for the goal word")
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { onCancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { onCreate(selectedLength) }
            .disabled(availableLengths.isEmpty)
            .accessibilityIdentifier("create-game-button")
        }
      }
    }
    .presentationDetents([.medium])
  }
}
