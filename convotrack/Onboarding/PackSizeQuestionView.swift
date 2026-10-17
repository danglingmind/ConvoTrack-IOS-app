import SwiftUI

/// One optional question. The answer prefills the rider count on the first ride they create
/// and lets the paywall speak about the free-plan cap only when it is relevant to them.
struct PackSizeQuestionView: View {
    let onContinue: () -> Void

    @State private var selection: PackSize? = OnboardingState.packSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR PACK")
                        .font(.caption.weight(.bold).monospaced())
                        .tracking(2)
                        .foregroundStyle(Color.onSurfaceVariant)
                    Text("How big is your usual group?")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("So we can set up your first ride.")
                        .font(.body)
                        .foregroundStyle(Color.onSurfaceVariant)

                    VStack(spacing: 10) {
                        ForEach(PackSize.allCases) { size in
                            optionRow(size)
                        }
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 88)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(action: {
                OnboardingState.packSize = selection
                onContinue()
            }) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.primaryFixed, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.onPrimaryFixed)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func title(_ size: PackSize) -> LocalizedStringKey {
        switch size {
        case .duo:    "Just me and one other"
        case .small:  "3–5 riders"
        case .medium: "6–12 riders"
        case .large:  "13 or more riders"
        case .unsure: "Not sure yet"
        }
    }

    private func optionRow(_ size: PackSize) -> some View {
        let selected = selection == size
        return Button { selection = size } label: {
            HStack {
                Text(title(size))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.primaryFixed : Color.onSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? Color.primaryFixed.opacity(0.10) : Color.surfaceContainerHigh.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Color.primaryFixed.opacity(0.8) : Color.outlineVariant.opacity(0.3),
                        lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview { PackSizeQuestionView(onContinue: {}).background(Color.surfaceDim).preferredColorScheme(.dark) }
