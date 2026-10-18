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
                    Text("Your pack")
                        .dsText(.eyebrow)
                        .foregroundStyle(DS.Text.secondary)
                    Text("How big is your usual group?")
                        .dsText(.heroTitle)
                        .foregroundStyle(DS.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("So we can set up your first ride.")
                        .dsText(.heroSubtitle)
                        .foregroundStyle(DS.Text.secondary)

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

            DSPrimaryButton(title: "Continue") {
                OnboardingState.packSize = selection
                onContinue()
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
        return Button {
            DSHaptic.selection()
            selection = size
        } label: {
            HStack {
                Text(title(size))
                    .dsText(.bodyStrong)
                    .foregroundStyle(DS.Text.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsIcon(DS.IconSize.lg)
                    .foregroundStyle(selected ? DS.Accent.base : DS.Text.secondary.base)
            }
            .padding(.horizontal, DS.Space.p4)
            .frame(maxWidth: .infinity, minHeight: DS.Target.button, alignment: .leading)
            .dsSurfaceCard(.card, radius: DS.Radius.md, border: selected ? DS.Accent.border : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview { PackSizeQuestionView(onContinue: {}).background(DS.Background.base).preferredColorScheme(.dark) }
