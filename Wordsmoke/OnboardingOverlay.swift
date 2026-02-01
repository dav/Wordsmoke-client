import SwiftUI

struct OnboardingOverlay: View {
  let step: OnboardingStep
  let anchors: [OnboardingTarget: Anchor<CGRect>]
  let onNext: () -> Void
  let onSkip: () -> Void

  @Environment(\.appTheme) private var theme

  var body: some View {
    GeometryReader { proxy in
      let targetFrame = step.target.flatMap { target in
        anchors[target].map { proxy[$0] }
      }
      let showAboveTarget = targetFrame.map { $0.midY > proxy.size.height * 0.6 } ?? false

      if step.requiresTarget && targetFrame == nil {
        EmptyView()
      } else {
        ZStack {
          ZStack {
            Color.black.opacity(0.55)
              .ignoresSafeArea()

            if let targetFrame {
              RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .frame(
                  width: targetFrame.width + theme.cellPadding,
                  height: targetFrame.height + theme.cellPadding
                )
                .position(x: targetFrame.midX, y: targetFrame.midY)
                .blendMode(.destinationOut)
            }
          }
          .compositingGroup()

          if let targetFrame {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
              .stroke(theme.accent, lineWidth: theme.borderWidth)
              .frame(
                width: targetFrame.width + theme.cellPadding,
                height: targetFrame.height + theme.cellPadding
              )
              .position(x: targetFrame.midX, y: targetFrame.midY)
          }

          VStack {
            if showAboveTarget {
              OnboardingCard(step: step, onNext: onNext, onSkip: onSkip)
                .padding(theme.cellPadding)
              Spacer()
            } else {
              Spacer()
              OnboardingCard(step: step, onNext: onNext, onSkip: onSkip)
                .padding(theme.cellPadding)
            }
          }
        }
      }
    }
  }
}

private struct OnboardingCard: View {
  let step: OnboardingStep
  let onNext: () -> Void
  let onSkip: () -> Void

  @Environment(\.appTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
      VStack(alignment: .leading, spacing: theme.cellPadding) {
        Text(step.title)
          .font(.headline)
          .foregroundStyle(theme.textPrimary)
        Text(step.message)
          .foregroundStyle(theme.textSecondary)
      }

      HStack {
        Button(step.primaryActionTitle) {
          onNext()
        }
        .buttonStyle(.borderedProminent)

        Spacer()

        Button("Skip Tour") {
          onSkip()
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(theme.cellPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.cardBackground)
    .overlay(
      RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        .stroke(theme.border, lineWidth: theme.borderWidth)
    )
    .clipShape(.rect(cornerRadius: theme.cornerRadius))
  }
}
