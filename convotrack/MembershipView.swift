import SwiftUI
import StoreKit

struct MembershipView: View {
    @EnvironmentObject private var store: MembershipStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: String = "danglingmind.convotrack.membership.yearly"
    @State private var showSuccess = false
    @State private var purchaseError: String? = nil
    @State private var isPurchasing = false

    var body: some View {
        ZStack {
            atmosphericBackground

            if showSuccess {
                successOverlay
            } else {
                VStack(spacing: 0) {
                    closeRow
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 22) {
                            heroSection
                            benefitsGrid
                            plansSection
                            ctaStack
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .task { await store.loadProducts() }
    }

    // MARK: - Background

    private var atmosphericBackground: some View {
        ZStack {
            Color.surfaceDim.ignoresSafeArea()
            RadialGradient(
                colors: [Color.primaryFixed.opacity(0.16), Color.clear],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 340
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Close

    private var closeRow: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.iconXS)
                    .foregroundColor(Color.onSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(Color.surfaceContainerHigh.opacity(0.8))
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primaryFixed.opacity(0.18))
                    .frame(width: 110, height: 110)
                    .blur(radius: 22)
                Circle()
                    .fill(Color.primaryFixed.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "crown.fill")
                    .font(.iconXL)
                    .foregroundColor(Color.primaryFixed)
                    .shadow(color: Color.primaryFixed.opacity(0.7), radius: 10)
            }
            .padding(.top, 2)

            Text("CONVOTRACK PRO")
                .font(.headlineLg)
                .foregroundColor(Color.onSurface)
                .tracking(3)

            Text("Your rides. No limits.")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant)
        }
    }

    // MARK: - Benefits Grid

    private let benefits: [(icon: String, title: String, detail: String)] = [
        ("person.3.fill",  "25 RIDERS",   "Fill every seat in the pack"),
        ("infinity",       "UNLIMITED",   "No monthly ride cap, ever"),
        ("chart.bar.fill", "ANALYTICS",   "Live stats & sync scores"),
        ("clock.fill",     "365 DAYS",    "Full ride history archive"),
    ]

    private var benefitsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(benefits, id: \.title) { b in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: b.icon)
                        .font(.iconMd)
                        .foregroundColor(Color.primaryFixed)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title)
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurface)
                            .tracking(1)
                        Text(b.detail)
                            .font(.captionMd)
                            .foregroundColor(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.surfaceContainerHigh.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
            }
        }
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 8) {
            if store.productsLoadFailed {
                plansErrorState
            } else if store.products.isEmpty {
                loadingPlaceholders
            } else {
                ForEach(store.products, id: \.id) { product in
                    ZStack(alignment: .topTrailing) {
                        planCard(product)

                        if product.id.contains("yearly"), let pct = savingsPct() {
                            Text("SAVE \(pct)%")
                                .font(.labelCaps)
                                .foregroundColor(Color.onPrimaryFixed)
                                .tracking(0.5)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.primaryFixed)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .offset(x: -14, y: -10)
                        }
                    }
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isYearly   = product.id.contains("yearly")
        let isSelected = selectedPlan == product.id

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedPlan = product.id
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.primaryFixed : Color.outlineVariant.opacity(0.4),
                                lineWidth: isSelected ? 2 : 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.primaryFixed).frame(width: 11, height: 11)
                    }
                }

                // Label + subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(isYearly ? "YEARLY" : "MONTHLY")
                        .font(.labelCaps)
                        .foregroundColor(isSelected ? Color.onSurface : Color.onSurfaceVariant)
                        .tracking(1.5)

                    Text(isYearly
                         ? "\(perMonthLabel(product)) / mo · billed annually"
                         : "Billed every month")
                        .font(.captionMd)
                        .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
                }

                Spacer()

                // Price block
                VStack(alignment: .trailing, spacing: 2) {
                    if isYearly {
                        Text(perMonthLabel(product))
                            .font(.headlineMd)
                            .foregroundColor(isSelected ? Color.primaryFixed : Color.onSurface)

                        if let monthly = store.monthlyProduct {
                            Text(monthly.displayPrice)
                                .font(.captionMd)
                                .strikethrough(true, color: Color.onSurfaceVariant.opacity(0.5))
                                .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
                        }
                    } else {
                        Text(product.displayPrice)
                            .font(.headlineMd)
                            .foregroundColor(isSelected ? Color.onSurface : Color.onSurfaceVariant)

                        Text("/ mo")
                            .font(.captionMd)
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                isSelected
                    ? Color.primaryFixed.opacity(isYearly ? 0.1 : 0.06)
                    : Color.surfaceContainerHigh.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.primaryFixed.opacity(0.7) : Color.outlineVariant.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var ctaStack: some View {
        VStack(spacing: 0) {
            if let error = purchaseError {
                Text(error)
                    .font(.captionMd)
                    .foregroundColor(Color.errorColor)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
            }

            Button {
                Task { await doPurchase() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView().tint(Color.onPrimaryFixed).scaleEffect(0.85)
                    } else {
                        Image(systemName: "crown.fill").font(.iconSm)
                    }
                    Text(ctaLabel).font(.bodyLg)
                }
            }
            .disabled(isPurchasing || store.products.isEmpty)
            .modifier(LimePrimaryButton())
            .opacity(isPurchasing || store.products.isEmpty ? 0.6 : 1)

            // Trust strip
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.iconXS)
                Text("Secured by Apple  ·  Cancel anytime")
            }
            .font(.captionMd)
            .foregroundColor(Color.onSurfaceVariant.opacity(0.45))
            .padding(.top, 12)

            // Auto-renewal disclosure — required by App Store Guideline 3.1.2
            Text("""
            \(selectedPlanDisclosure) Payment is charged to your Apple ID at \
            confirmation of purchase. The subscription automatically renews unless \
            it is canceled at least 24 hours before the end of the current period, \
            and your account is charged for renewal within 24 hours prior to the end \
            of the period. Manage or cancel anytime in App Store account settings.
            """)
            .font(.captionMd)
            .foregroundColor(Color.onSurfaceVariant.opacity(0.42))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 10)

            // Restore / legal
            HStack(spacing: 14) {
                Button("Restore purchases") {
                    Task {
                        isPurchasing = true
                        await store.restorePurchases()
                        isPurchasing = false
                        if store.isPremium { withAnimation { showSuccess = true } }
                    }
                }
                Text("·")
                Link("Terms", destination: URL(string: AppURLs.termsOfService)!)
                Text("·")
                Link("Privacy", destination: URL(string: AppURLs.privacyPolicy)!)
            }
            .font(.captionMd)
            .foregroundColor(Color.onSurfaceVariant.opacity(0.38))
            .padding(.top, 8)
        }
    }

    // MARK: - Loading / Error

    private var loadingPlaceholders: some View {
        ForEach(0..<2, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfaceContainerHigh.opacity(0.5))
                .frame(height: 84)
                .overlay(ProgressView().tint(Color.primaryFixed))
        }
    }

    private var plansErrorState: some View {
        VStack(spacing: 10) {
            Text("Couldn't load plans")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant)
            Button("Retry") {
                Task {
                    store.productsLoadFailed = false
                    store.products = []
                    await store.loadProducts()
                }
            }
            .font(.labelCaps)
            .foregroundColor(Color.primaryFixed)
            .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Success

    private var successOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.primaryFixed.opacity(0.14))
                    .frame(width: 130, height: 130)
                    .blur(radius: 24)
                Circle()
                    .fill(Color.primaryFixed.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(.iconHero)
                    .foregroundColor(Color.primaryFixed)
                    .shadow(color: Color.primaryFixed.opacity(0.6), radius: 12)
            }

            VStack(spacing: 6) {
                Text("YOU'RE IN")
                    .font(.headlineLg)
                    .foregroundColor(Color.primaryFixed)
                    .tracking(4)
                    .padding(.top, 24)

                Text("Welcome to ConvoTrack Pro.")
                    .font(.bodyLg)
                    .foregroundColor(Color.onSurface)

                Text("Your rides, no limits.")
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
                    .padding(.top, 2)
            }

            Spacer()

            Button("LET'S RIDE") { dismiss() }
                .font(.bodyLg)
                .modifier(LimePrimaryButton())
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Actions

    private func doPurchase() async {
        guard let product = store.products.first(where: { $0.id == selectedPlan }) else { return }
        isPurchasing = true
        purchaseError = nil
        do {
            try await store.purchase(product)
            if store.isPremium {
                withAnimation(.spring(response: 0.4)) { showSuccess = true }
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
        isPurchasing = false
    }

    // MARK: - Helpers

    private var ctaLabel: String {
        guard let product = store.products.first(where: { $0.id == selectedPlan }) else {
            return "GET CONVOTRACK PRO"
        }
        return selectedPlan.contains("yearly")
            ? "GET PRO  ·  \(product.displayPrice)/yr"
            : "GET PRO  ·  \(product.displayPrice)/mo"
    }

    private func perMonthLabel(_ product: Product) -> String {
        (product.price / 12).formatted(product.priceFormatStyle)
    }

    // Title + length + price for the selected plan, per Guideline 3.1.2.
    private var selectedPlanDisclosure: String {
        guard let product = store.products.first(where: { $0.id == selectedPlan }) else {
            return "ConvoTrack Pro is an auto-renewable subscription."
        }
        let period = selectedPlan.contains("yearly") ? "year" : "month"
        return "ConvoTrack Pro is a \(product.displayPrice)/\(period) auto-renewable subscription."
    }

    private func savingsPct() -> Int? {
        guard let monthly = store.monthlyProduct,
              let yearly  = store.products.first(where: { $0.id.contains("yearly") }) else { return nil }
        let pct = store.savingsPercent(monthly: monthly, yearly: yearly)
        return pct > 0 ? pct : nil
    }
}

#Preview {
    MembershipView()
        .environmentObject(MembershipStore())
        .preferredColorScheme(.dark)
}
