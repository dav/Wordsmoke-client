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
        Section("Word Length") {
          Picker("Letters", selection: $selectedLength) {
            ForEach(availableLengths, id: \.self) { length in
              Text("\(length) letters").tag(length)
            }
          }
          .pickerStyle(.segmented)
        }
      }
      .navigationTitle("New Game")
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
