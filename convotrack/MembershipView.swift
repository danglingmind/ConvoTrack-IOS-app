import SwiftUI
import StoreKit

enum MembershipPresentation {
    /// Presented as a sheet from Profile / CreateRide / EditRide.
    case sheet
    /// Shown inline once, at the end of first-run onboarding.
    case onboarding
}

struct MembershipView: View {
    @EnvironmentObject private var store: MembershipStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let presentation: MembershipPresentation
    private let source: PaywallSource
    private let onFinish: (() -> Void)?

    /// - Parameters:
    ///   - source: the surface that opened the paywall; picks its headline.
    ///   - onFinish: called instead of `dismiss()` when the host isn't a sheet.
    init(presentation: MembershipPresentation = .sheet,
         source: PaywallSource = .profile,
         onFinish: (() -> Void)? = nil) {
        self.presentation = presentation
        self.source = source
        self.onFinish = onFinish
    }

    private var isOnboarding: Bool { presentation == .onboarding }

    /// The free-trial introductory offer this account can actually redeem, if any. Nothing about a
    /// trial is shown unless this is non-nil — never advertise an offer the purchase sheet won't give.
    private var trialOffer: Product.SubscriptionOffer? {
        store.products
            .compactMap { store.introductoryOffer(for: $0) }
            .first { $0.paymentMode == .freeTrial }
    }

    /// "3 days" — derived from the offer, never hardcoded.
    private var trialLength: String? {
        trialOffer.map { PlanPeriod($0.period).longLabel }
    }
    private func close() {
        if !store.isPremium { PaywallAnalytics.log(.paywallDismissed, source: analyticsSource, access: store.access) }
        if let onFinish { onFinish() } else { dismiss() }
    }

    /// Onboarding has no presenter source of its own.
    private var analyticsSource: PaywallSource? { isOnboarding ? nil : source }

    /// Free-plan limits as the server reports them. nil until loaded, if the call failed, or for
    /// a rider who is already Pro.
    private var freePlan: MembershipPlanInfo? {
        store.plan.flatMap { $0.isPremium ? nil : $0 }
    }

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
                        VStack(spacing: DS.Space.p6) {
                            heroSection
                            benefitsGrid
                            plansSection
                            ctaStack
                        }
                        .padding(.horizontal, DS.Space.screenInset)
                        .padding(.top, DS.Space.p1)
                        .padding(.bottom, DS.Space.p7)
                        .frame(maxWidth: DS.Space.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { PaywallAnalytics.log(.paywallShown, source: analyticsSource, access: store.access) }
        .task {
            await store.loadProducts()
            // Catches a country change that happened while the app was suspended,
            // where Storefront.updates is not guaranteed to have been delivered.
            await store.refreshIfStorefrontChanged()
        }
        .task {
            // Usually already loaded at launch; refreshed here so the limits shown are current.
            if store.plan == nil { await store.refreshServerState() }
        }
    }

    // MARK: - Background

    private var atmosphericBackground: some View {
        ZStack(alignment: .top) {
            DSScreenBackground()
            if isOnboarding {
                // The product, not a crown: the same live-map artwork as the intro screens,
                // dimmed so the plan cards and legal text stay legible.
                RouteBackdrop(variant: .tracking,
                              isAnimating: OnboardingPlaybackPolicy.allowsMotion(reduceMotion: reduceMotion))
                    .blur(radius: 6)
                    .opacity(0.35)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            DS.Gradient.accentAura(endRadius: 340).ignoresSafeArea()
        }
    }

    // MARK: - Close

    private var closeRow: some View {
        HStack {
            Spacer()
            DSFloatingButton(systemImage: "xmark", label: "Close", variant: .onDark) { close() }
                .padding(.trailing, DS.Space.p4)
                .padding(.top, DS.Space.p2)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: DS.Space.p3) {
            Image(systemName: "rosette")
                .dsIcon(32, weight: .medium)
                .foregroundStyle(DS.Accent.base)
                .frame(width: 72, height: 72)
                .background(DS.Accent.tint, in: Circle())
                .accessibilityHidden(true)

            Text(heroTitle)
                .redacted(reason: isAwaitingPlan ? .placeholder : [])
                .dsText(.heroTitleCompact)
                .foregroundStyle(DS.Text.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(heroSubtitle)
                .redacted(reason: isAwaitingPlan ? .placeholder : [])
                .dsText(.body)
                .foregroundStyle(DS.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// First sign-in: `/users/me` hasn't answered yet, so the headline would read "ConvoTrack Pro"
    /// and then jump to the trial wording. Hold a placeholder until it lands instead.
    private var isAwaitingPlan: Bool { isOnboarding && store.plan == nil && !store.isPremium }

    /// The trial leads: while it runs the headline is the countdown, once it ends it's the wall.
    /// Monthly rides and the rider cap are secondary and only surface through the subtitle.
    private var heroTitle: LocalizedStringKey {
        switch store.access {
        case .trial:
            if isOnboarding { return "Your free trial has started" }
            guard let days = store.trialDaysLeft, days > 1 else { return "Your free trial ends today" }
            return "\(days) days left in your free trial"
        case .trialExpired:
            return "Your free trial has ended"
        case .pro, .free:
            return "ConvoTrack Pro"
        }
    }

    private var heroSubtitle: LocalizedStringKey {
        let cap = freePlan?.maxRidersPerRide ?? store.riderCap
        // A limit the rider just ran into explains itself better than the generic pitch.
        switch source {
        case .riderCap:
            return "Pro lifts the \(cap)-rider limit. Bring your whole crew."
        case .quotaExceeded:
            if let monthly = freePlan?.monthlyLimit {
                return "You've used your \(monthly) rides this month. Pro has no monthly limit."
            }
        default:
            break
        }
        switch store.access {
        case .trial:
            guard isOnboarding else { return "Go Pro to keep creating and joining rides after your trial." }
            if let days = store.trialDaysLeft, days > 1 {
                return "\(days) days of ConvoTrack, on us. Go Pro any time to keep riding after it ends."
            }
            return "ConvoTrack is free while it lasts. Go Pro any time to keep riding after it ends."
        case .trialExpired:
            return "Go Pro to keep creating and joining rides with your crew."
        case .pro, .free:
            break
        }
        // Only talks about the rider cap when the rider told us their pack is bigger than it.
        guard isOnboarding else { return "Your rides. No limits." }
        if let pack = OnboardingState.packSize, pack.exceedsFreeCap(cap) {
            return pack == .large ? "Up to \(store.proRiderCap) riders on one map." : "Your pack is bigger than \(cap)."
        }
        return "Ride bigger. Keep every ride."
    }

    // MARK: - Benefits Grid

    // LocalizedStringKey (not String) so the build-time extractor harvests these
    // into the String Catalog — Text(someString) would silently skip them.
    private let benefits: [(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("person.3",  "BIGGER PACKS", "Bring your whole crew along"),
        ("infinity",  "UNLIMITED",    "No monthly ride cap, ever"),
        ("chart.bar", "ANALYTICS",    "Live stats & sync scores"),
        ("calendar",  "365 DAYS",     "Full ride history archive"),
    ]

    private var benefitColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible())]
    }

    private var benefitsGrid: some View {
        LazyVGrid(columns: benefitColumns, spacing: 10) {
            ForEach(benefits, id: \.icon) { b in
                DSBenefitTile(systemImage: b.icon, title: b.title, detail: b.detail)
            }
        }
    }

    // MARK: - Free plan terms

    /// The rider is on (or past) the enforced app-level trial, so the free plan's terms are the
    /// trial's terms and nothing is free once it ends.
    private var isAppTrial: Bool {
        switch store.access {
        case .trial, .trialExpired: return true
        case .pro, .free: return false
        }
    }

    /// What the free plan includes, from the server — never hardcoded, never omitted. When a trial
    /// is on offer it is framed as what applies after the trial.
    @ViewBuilder private var freePlanTerms: some View {
        if !store.isPremium {
            Group {
                if case .trial = store.access {
                    // The trial is the app's, not the App Store's: buying now isn't deferred.
                    Text("Going Pro starts your subscription today — it doesn't wait for the trial to end.")
                }
                if store.access == .trialExpired {
                    Text("Creating and joining rides needs Pro now that your free trial has ended.")
                } else if isAppTrial, let plan = freePlan, let monthly = plan.monthlyLimit {
                    Text("The free trial includes up to \(monthly) rides and \(plan.maxRidersPerRide) riders per ride. Creating and joining rides needs Pro once it ends.")
                } else if isAppTrial {
                    Text("Creating and joining rides needs Pro once the free trial ends.")
                } else if let plan = freePlan, let monthly = plan.monthlyLimit {
                    if trialLength != nil {
                        Text("After the trial, the free plan includes \(monthly) rides a month and up to \(plan.maxRidersPerRide) riders per ride.")
                    } else {
                        Text("Free plan: \(monthly) rides a month, up to \(plan.maxRidersPerRide) riders per ride.")
                    }
                } else if let plan = freePlan {
                    Text("Free plan: up to \(plan.maxRidersPerRide) riders per ride.")
                } else if trialLength != nil {
                    Text("After the trial, the free plan has monthly ride and rider limits.")
                } else {
                    Text("The free plan has monthly ride and rider limits.")
                }
            }
            .dsText(.helper)
            .foregroundStyle(DS.Text.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: DS.Space.p2) {
            if store.productsLoadFailed {
                plansErrorState
            } else if store.products.isEmpty {
                loadingPlaceholders
            } else {
                ForEach(store.products, id: \.id) { product in
                    ZStack(alignment: .topTrailing) {
                        planCard(product)

                        if product.id == store.bestValuePlan?.id, let pct = savingsPct(for: product) {
                            Text("Save \(savingsText(pct))")
                                .dsText(.badge)
                                .foregroundStyle(DS.Text.onAccent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(DS.Accent.base, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
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
            DSHaptic.selection()
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                selectedPlan = product.id
            }
        } label: {
            HStack(alignment: .center, spacing: DS.Space.p3) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(isSelected ? DS.Accent.base : DS.Border.strong.base,
                                lineWidth: isSelected ? DS.BorderWidth.focus : DS.BorderWidth.emphasis)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(DS.Accent.base).frame(width: 11, height: 11)
                    }
                }
                .accessibilityHidden(true)

                // Label + subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(planTitle(for: period))
                        .dsText(.fieldLabel)
                        .foregroundStyle(isSelected ? DS.Text.primary.base : DS.Text.secondary.base)
                        .lineLimit(1)

                    if let period {
                        Text(period.billingCadenceLabel)
                            .dsText(.helper)
                            .foregroundStyle(DS.Text.muted)
                            .lineLimit(1)
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
                            .dsText(.micro)
                            .foregroundStyle(DS.Text.muted)
                            .lineLimit(1)
                    }
                }
                // Load-bearing: without it the HStack lets the two text columns fight
                // for width and the price loses as often as it wins.
                .layoutPriority(1)
            }
            .padding(DS.Space.p4 + 2)
            .background(isSelected ? DS.Accent.tint.opacity(isBestValue ? 1 : 0.6) : .clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .dsSurfaceCard(.card, radius: DS.Radius.lg, border: isSelected ? DS.Accent.border : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Price + period suffix. Falls back to a stacked layout before it ever shrinks
    /// the billed amount below the supporting text — long currencies such as
    /// "Rp 210.000,00" would otherwise wrap or clip.
    @ViewBuilder
    private func priceBlock(_ product: Product, period: PlanPeriod?, isSelected: Bool, isBestValue: Bool) -> some View {
        let color: Color = isSelected && isBestValue ? DS.Accent.base : DS.Text.primary.base
        let price = Text(product.displayPrice)

        Group {
            if let period {
                ViewThatFits(in: .horizontal) {
                    Text("\(price) / \(period.shortLabel)")
                        .dsText(.metricValue)

                    VStack(alignment: .trailing, spacing: 0) {
                        price.dsText(.metricValue)
                        Text("/ \(period.shortLabel)").dsText(.helper)
                    }

                    // Guaranteed-render fallback: the billed amount stays dominant.
                    Text("\(price) / \(period.shortLabel)")
                        .dsText(.metricValue)
                        .lineLimit(1)
                        .allowsTightening(true)
                }
            } else {
                // No subscription descriptor: show the price, never guess a period.
                price
                    .dsText(.metricValue)
                    .lineLimit(1)
                    .allowsTightening(true)
            }
        }
        .foregroundStyle(color)
    }

    // MARK: - CTA

    private var ctaStack: some View {
        VStack(spacing: 0) {
            if let error = purchaseError {
                DSInlineError(message: LocalizedStringKey(error))
                    .padding(.bottom, DS.Space.p3)
            }

            Button {
                DSHaptic.primary()
                Task { await doPurchase() }
            } label: {
                HStack(spacing: DS.Space.p2) {
                    if isPurchasing {
                        ProgressView().tint(DS.Text.onAccent)
                    } else {
                        Image(systemName: "rosette").dsIcon(DS.IconSize.sm, weight: .semibold)
                    }
                    // Drop the price before letting the label wrap: it is still shown dominantly
                    // on the card and in the disclosure.
                    ViewThatFits(in: .horizontal) {
                        ctaLabelWithPrice
                        ctaLabelShort
                        ctaLabelWithPrice
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .allowsTightening(true)
                    }
                    .dsText(.button)
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isPurchasing || store.products.isEmpty)

            if let line = trialLine {
                line
                    .dsText(.helper)
                    .foregroundStyle(DS.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DS.Space.p2)
            }

            if isOnboarding {
                DSTextButton(title: isAppTrial ? "Continue with free trial" : "Continue with Free",
                             role: .dismiss) { close() }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.p2)
            }

            freePlanTerms

            // Trust strip
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").dsIcon(DS.IconSize.sm)
                Text("Secured by the App Store · Cancel anytime")
            }
            .dsText(.helper)
            .foregroundStyle(DS.Text.muted)
            .padding(.top, DS.Space.p3)

            // Auto-renewal disclosure — required by App Store Guideline 3.1.2
            Text("""
            \(selectedPlanDisclosure) Payment is charged to your Apple Account at \
            confirmation of purchase. The subscription automatically renews unless \
            it is canceled at least 24 hours before the end of the current period, \
            and your account is charged for renewal within 24 hours prior to the end \
            of the period. Manage or cancel anytime in App Store account settings.
            """)
            .dsText(.helper)
            .foregroundStyle(DS.Text.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.p1)
            .padding(.top, 10)

            // Restore / legal — text buttons, at least 44 pt tall.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.p1) {
                    restoreButton
                    Text(verbatim: "·").foregroundStyle(DS.Text.subtle)
                    legalLink("Terms", AppURLs.termsOfService)
                    Text(verbatim: "·").foregroundStyle(DS.Text.subtle)
                    legalLink("Privacy", AppURLs.privacyPolicy)
                }
                VStack(spacing: 0) {
                    restoreButton
                    legalLink("Terms", AppURLs.termsOfService)
                    legalLink("Privacy", AppURLs.privacyPolicy)
                }
            }
            .dsText(.link)
            .foregroundStyle(DS.Text.secondary)
            .padding(.top, DS.Space.p1)
        }
    }

    private var restoreButton: some View {
        Button("Restore purchases") {
            Task {
                isPurchasing = true
                await store.restorePurchases()
                isPurchasing = false
                if store.isPremium { withAnimation { showSuccess = true } }
            }
        }
        .padding(.horizontal, DS.Space.p3)
        .frame(minHeight: DS.Target.minimum)
    }

    private func legalLink(_ title: LocalizedStringKey, _ url: String) -> some View {
        Link(title, destination: URL(string: url)!)
            .padding(.horizontal, DS.Space.p3)
            .frame(minHeight: DS.Target.minimum)
    }

    // MARK: - Loading / Error

    private var loadingPlaceholders: some View {
        // Never a placeholder price: just a quiet loading card.
        HStack(spacing: DS.Space.p3) {
            ProgressView().tint(DS.Accent.base)
            Text("Loading plans…").dsText(.body).foregroundStyle(DS.Text.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .dsSurfaceCard(.card, radius: DS.Radius.lg)
        .accessibilityElement(children: .combine)
    }

    private var plansErrorState: some View {
        DSErrorState(title: "Couldn't load plans") {
            Task { await store.loadProducts(force: true) }
        }
    }

    // MARK: - Success

    private var successOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark")
                .dsIcon(44, weight: .bold)
                .foregroundStyle(DS.Status.success)
                .frame(width: 88, height: 88)
                .background(DS.Status.successTint, in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: DS.Space.p2) {
                Text("You're in")
                    .dsText(.heroTitle)
                    .foregroundStyle(DS.Accent.base)
                    .padding(.top, DS.Space.p6)
                    .accessibilityAddTraits(.isHeader)

                Text("Welcome to ConvoTrack Pro.")
                    .dsText(.bodyStrong)
                    .foregroundStyle(DS.Text.primary)

                Text("Your rides, no limits.")
                    .dsText(.body)
                    .foregroundStyle(DS.Text.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer()

            DSPrimaryButton(title: "Let's ride") { close() }
                .padding(.horizontal, DS.Space.screenInset)
                .padding(.bottom, DS.Space.p10)
        }
        .frame(maxWidth: DS.Space.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Actions

    private func doPurchase() async {
        guard let product = selectedProduct else { return }
        PaywallAnalytics.log(.purchaseStarted, source: analyticsSource, access: store.access)
        isPurchasing = true
        purchaseError = nil
        do {
            try await store.purchase(product)
            if store.isPremium {
                PaywallAnalytics.log(.converted, source: analyticsSource)
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

    /// "3 days free trial, then $39.99 / yr" for the selected plan. nil unless that plan has a
    /// free-trial offer this account can redeem — fails closed, never implies a trial.
    private var trialLine: Text? {
        guard let product = selectedProduct,
              let offer = store.introductoryOffer(for: product),
              offer.paymentMode == .freeTrial else { return nil }
        let length = PlanPeriod(offer.period).longLabel
        let price = Text(product.displayPrice)
        guard let period = PlanPeriod(product) else {
            return Text("\(length) free trial, then \(price)")
        }
        return Text("\(length) free trial, then \(price) / \(period.shortLabel)")
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

    /// Empty unless an introductory offer is both configured and this account is eligible.
    /// No store offer is configured today — the free trial is app-level and server-side — so
    /// this normally stays empty. Must fail closed rather than imply a trial when no offer applies.
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
