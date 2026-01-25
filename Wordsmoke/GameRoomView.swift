import SwiftUI

struct GameRoomView: View {
  @Bindable var model: GameRoomModel

  var body: some View {
    Form {
      Section("Round") {
        Text("Status: \(model.game.status)")
        if let round = model.round {
          Text("Round \(round.number) — \(round.status)")
          Text("Votes: \(round.phraseVotesCount)")
        } else {
          Text("No round loaded")
            .foregroundStyle(.secondary)
        }
        Button("Refresh Round") {
          Task {
            await model.refreshRound()
          }
        }
        .buttonStyle(.bordered)
      }

      Section("Submit Guess") {
        TextField("Guess word", text: $model.guessWord)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("Phrase", text: $model.phrase)
          .textInputAutocapitalization(.sentences)
        Button("Submit Guess") {
          Task {
            await model.submitGuess()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy)

        if let errorMessage = model.errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
        }
      }

      Section("Submissions") {
        if let submissions = model.round?.submissions, !submissions.isEmpty {
          ForEach(submissions) { submission in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(submission.playerName)
                  .bold()
                if submission.correctGuess == true {
                  Text("Correct")
                    .foregroundStyle(.green)
                }
              }
              Text("\(submission.guessWord): \(submission.phrase)")
              MarksView(marks: submission.marks)
            }
          }
        } else {
          Text("No submissions yet.")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Game")
    .task {
      if model.round == nil {
        await model.refreshRound()
      }
    }
  }
}
