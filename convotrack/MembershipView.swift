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
        .task {
            await store.loadProducts()
            // Catches a country change that happened while the app was suspended,
            // where Storefront.updates is not guaranteed to have been delivered.
            await store.refreshIfStorefrontChanged()
        }
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
            .accessibilityLabel(Text("Close"))
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

    // LocalizedStringKey (not String) so the build-time extractor harvests these
    // into the String Catalog — Text(someString) would silently skip them.
    private let benefits: [(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("person.3.fill",  "BIGGER PACKS", "Bring your whole crew along"),
        ("infinity",       "UNLIMITED",    "No monthly ride cap, ever"),
        ("chart.bar.fill", "ANALYTICS",    "Live stats & sync scores"),
        ("clock.fill",     "365 DAYS",     "Full ride history archive"),
    ]

    private var benefitsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(benefits, id: \.icon) { b in
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

                        if product.id == store.bestValuePlan?.id, let pct = savingsPct(for: product) {
                            Text("SAVE \(savingsText(pct))")
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
        let period     = PlanPeriod(product)
        let isSelected = selectedPlan == product.id
        let isBestValue = product.id == store.bestValuePlan?.id

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
                    Text(planTitle(for: period))
                        .font(.labelCaps)
                        .foregroundColor(isSelected ? Color.onSurface : Color.onSurfaceVariant)
                        .tracking(1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let period {
                        Text(period.billingCadenceLabel)
                            .font(.captionMd)
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                // minLength so the spacer yields width instead of hoarding it when
                // a long non-USD price needs room.
                Spacer(minLength: 8)

                // Price block — the billed amount is always the dominant element
                // (Guideline 3.1.2(c)); calculated per-month pricing stays subordinate.
                VStack(alignment: .trailing, spacing: 2) {
                    priceBlock(product, period: period, isSelected: isSelected, isBestValue: isBestValue)

                    if let period, period.isLongerThanAMonth, let perMonth = perMonthLabel(product, period) {
                        Text("≈ \(perMonth) / \(monthShortLabel)")
                            .font(.captionSm)
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                // Load-bearing: without it the HStack lets the two text columns fight
                // for width and the price loses as often as it wins.
                .layoutPriority(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                isSelected
                    ? Color.primaryFixed.opacity(isBestValue ? 0.1 : 0.06)
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

    /// Price + period suffix. Falls back to a stacked layout before it ever shrinks
    /// the billed amount below the supporting text — long currencies such as
    /// "Rp 210.000,00" would otherwise wrap or clip.
    @ViewBuilder
    private func priceBlock(_ product: Product, period: PlanPeriod?, isSelected: Bool, isBestValue: Bool) -> some View {
        let color: Color = isSelected
            ? (isBestValue ? Color.primaryFixed : Color.onSurface)
            : Color.onSurface
        let price = Text(product.displayPrice)

        Group {
            if let period {
                ViewThatFits(in: .horizontal) {
                    Text("\(price) / \(period.shortLabel)")
                        .font(.headlineMd)

                    VStack(alignment: .trailing, spacing: 0) {
                        price.font(.headlineMd)
                        Text("/ \(period.shortLabel)").font(.captionMd)
                    }

                    // Guaranteed-render fallback. 24pt x 0.6 = 14.4pt, still above the
                    // 12pt plan name, so the billed amount stays dominant.
                    Text("\(price) / \(period.shortLabel)")
                        .font(.headlineMd)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
            } else {
                // No subscription descriptor: show the price, never guess a period.
                price
                    .font(.headlineMd)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }
        }
        .foregroundColor(color)
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
                    // The button frame is a fixed 56pt, so a wrapped line is clipped
                    // rather than accommodated. Drop the price before letting that happen —
                    // it is still shown dominantly on the card and in the disclosure.
                    ViewThatFits(in: .horizontal) {
                        ctaLabelWithPrice
                        ctaLabelShort
                        ctaLabelWithPrice
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .allowsTightening(true)
                    }
                    .font(.bodyLg)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
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
            \(selectedPlanDisclosure) Payment is charged to your Apple Account at \
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
                Text(verbatim: "·")
                Link("Terms", destination: URL(string: AppURLs.termsOfService)!)
                Text(verbatim: "·")
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
                Task { await store.loadProducts(force: true) }
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
        guard let product = selectedProduct else { return }
        isPurchasing = true
        purchaseError = nil
        do {
            try await store.purchase(product)
            if store.isPremium {
                withAnimation(.spring(response: 0.4)) { showSuccess = true }
            }
        } catch {
            purchaseError = UserFacingError.purchaseFailed
        }
        isPurchasing = false
    }

    // MARK: - Helpers

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedPlan }
    }

    private var monthShortLabel: String {
        String(localized: "mo", comment: "Compact billing period: one month")
    }

    private func planTitle(for period: PlanPeriod?) -> String {
        guard let period else {
            return String(localized: "PLAN", comment: "Plan card title when the billing period is unknown")
        }
        switch period.unit {
        case .day:   return String(localized: "DAILY",   comment: "Plan card title")
        case .week:  return String(localized: "WEEKLY",  comment: "Plan card title")
        case .month: return String(localized: "MONTHLY", comment: "Plan card title")
        case .year:  return String(localized: "YEARLY",  comment: "Plan card title")
        @unknown default:
            return String(localized: "PLAN", comment: "Plan card title when the billing period is unknown")
        }
    }

    private var ctaLabelWithPrice: Text {
        guard let product = selectedProduct else {
            return Text("GET CONVOTRACK PRO")
        }
        let price = Text(product.displayPrice)
        guard let period = PlanPeriod(product) else {
            return Text("GET PRO  ·  \(price)")
        }
        return Text("GET PRO  ·  \(price) / \(period.shortLabel)")
    }

    private var ctaLabelShort: Text {
        selectedProduct == nil ? Text("GET CONVOTRACK PRO") : Text("GET PRO")
    }

    /// Price of a single month at this plan's rate, formatted in the product's own
    /// currency and locale via `priceFormatStyle`.
    private func perMonthLabel(_ product: Product, _ period: PlanPeriod) -> String? {
        guard let monthly = period.monthlyEquivalent(of: product.price) else { return nil }
        return monthly.formatted(product.priceFormatStyle)
    }

    /// Percent formatted per locale — some locales place the sign before the number
    /// or use a different glyph, and a bare "%" in a format string is malformed.
    private func savingsText(_ pct: Int) -> String {
        (Decimal(pct) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private func savingsPct(for product: Product) -> Int? {
        guard let baseline = store.baselinePlan, baseline.id != product.id else { return nil }
        return store.savingsPercent(of: product, versus: baseline)
    }

    // Title + length + price for the selected plan, per Guideline 3.1.2.
    private var selectedPlanDisclosure: String {
        guard let product = selectedProduct else {
            return String(localized: "ConvoTrack Pro is an auto-renewable subscription.",
                          comment: "Subscription disclosure when no plan is loaded")
        }

        let intro = introOfferSentence(for: product)

        guard let period = PlanPeriod(product) else {
            return intro + String(localized: "ConvoTrack Pro is a \(product.displayPrice) auto-renewable subscription.",
                                  comment: "Subscription disclosure; argument is a pre-formatted, locale-correct price string that must not be reformatted")
        }
        return intro + String(localized: "ConvoTrack Pro is a \(product.displayPrice)/\(period.longLabel) auto-renewable subscription.",
                              comment: "Subscription disclosure; first argument is a pre-formatted, locale-correct price string, second is a period noun such as 'year'")
    }

    /// Empty unless an introductory offer is both configured and this account is
    /// eligible. No offer exists today — the trial is the in-app free-ride allowance —
    /// so this is defensive and must fail closed rather than imply a trial.
    private func introOfferSentence(for product: Product) -> String {
        guard let offer = store.introductoryOffer(for: product) else { return "" }
        let length = PlanPeriod(offer.period).longLabel
        switch offer.paymentMode {
        case .freeTrial:
            return String(localized: "Includes a free \(length) trial, then ",
                          comment: "Introductory offer prefix; argument is a period such as '7 days'") 
        case .payUpFront:
            return String(localized: "Includes an introductory \(offer.displayPrice) for \(length), then ",
                          comment: "Introductory offer prefix; first argument is a pre-formatted price, second a period")
        case .payAsYouGo:
            return String(localized: "Includes an introductory \(offer.displayPrice) per period for \(length), then ",
                          comment: "Introductory offer prefix; first argument is a pre-formatted price, second a period")
        default:
            // Fail closed: an unrecognised payment mode must never imply a trial.
            return ""
        }
    }
}

#Preview {
    MembershipView()
        .environmentObject(MembershipStore())
        .preferredColorScheme(.dark)
}
