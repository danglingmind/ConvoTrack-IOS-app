#if DEBUG
import SwiftUI

/// Debug-only component gallery. Launch with `-onboardingStage gallery` (add `-gallerySection N`
/// to open a section directly, `-galleryAX` for AX3 text).
struct DSGalleryView: View {
    @State private var largeText = UserDefaults.standard.bool(forKey: "galleryAX")
    @State private var path: [Int] = {
        let n = UserDefaults.standard.integer(forKey: "gallerySection")
        return n > 0 ? [n] : []
    }()

    private let sections: [(String, AnyView)] = [
        ("Chrome", AnyView(ChromeGallery())),
        ("Buttons", AnyView(ButtonsGallery())),
        ("Feedback", AnyView(FeedbackGallery())),
        ("Cards", AnyView(CardsGallery())),
        ("Inputs", AnyView(InputsGallery())),
        ("HUD", AnyView(HUDGallery())),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Toggle("Accessibility 3 text", isOn: $largeText)
                ForEach(sections.indices, id: \.self) { i in
                    NavigationLink(sections[i].0, value: i + 1)
                }
            }
            .navigationTitle("Design system")
            .navigationDestination(for: Int.self) { n in
                sections[n - 1].1
                    .navigationTitle(sections[n - 1].0)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .dynamicTypeSize(largeText ? .accessibility3 : .large)
        .preferredColorScheme(.dark)
    }
}
#endif
