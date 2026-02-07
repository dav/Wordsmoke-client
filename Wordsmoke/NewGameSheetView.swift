import SwiftUI

struct NewGameSheetView: View {
  let availableLengths: [Int]
  let onCreate: (Int, Int) -> Void
  let onCancel: () -> Void

  @State private var selectedLength: Int
  @State private var selectedPlayerCount: Int
  private let availablePlayerCounts = [2, 3, 4]

  init(
    availableLengths: [Int],
    defaultLength: Int,
    defaultPlayerCount: Int,
    onCreate: @escaping (Int, Int) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.availableLengths = availableLengths
    self.onCreate = onCreate
    self.onCancel = onCancel
    self._selectedLength = State(initialValue: availableLengths.contains(defaultLength) ? defaultLength : availableLengths.first ?? 5)
    if availablePlayerCounts.contains(defaultPlayerCount) {
      self._selectedPlayerCount = State(initialValue: defaultPlayerCount)
    } else {
      self._selectedPlayerCount = State(initialValue: availablePlayerCounts.first ?? 2)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Players") {
          Picker("Players", selection: $selectedPlayerCount) {
            ForEach(availablePlayerCounts, id: \.self) { count in
              Text("\(count) players").tag(count)
            }
          }
          .pickerStyle(.segmented)
          Text("All players must be invited before starting.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
          Button("Create") { onCreate(selectedLength, selectedPlayerCount) }
            .disabled(availableLengths.isEmpty)
            .accessibilityIdentifier("create-game-button")
        }
      }
    }
    .presentationDetents([.medium])
  }
}
