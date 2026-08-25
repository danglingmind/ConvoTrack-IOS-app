import Foundation
import StoreKit

/// Billing period derived from StoreKit's own subscription descriptor.
///
/// Replaces the previous `product.id.contains("yearly")` string matching and the
/// hardcoded `/ 12` divisor. Deriving from `subscriptionPeriod` means a weekly or
/// six-month plan added in App Store Connect renders correctly with no code change.
///
/// `init?` returns nil when the product is not auto-renewable (`subscription == nil`).
/// Callers must degrade — show the bare price with no period suffix — rather than
/// guessing a period, since stating a billing period you cannot prove is a
/// Guideline 3.1.2 misrepresentation.
struct PlanPeriod {

    let unit: Product.SubscriptionPeriod.Unit
    let value: Int

    init?(_ product: Product) {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        self.unit = period.unit
        self.value = period.value
    }

    init(_ period: Product.SubscriptionPeriod) {
        self.unit = period.unit
        self.value = period.value
    }

    // Mean Gregorian month: 365.25 / 12. Used so week/day plans normalise sensibly.
    private static let daysPerMonth = Decimal(string: "30.4375")!

    /// Length of one billing cycle expressed in months.
    var months: Decimal {
        switch unit {
        case .year:  Decimal(12 * value)
        case .month: Decimal(value)
        case .week:  Decimal(value) * 7 / Self.daysPerMonth
        case .day:   Decimal(value) / Self.daysPerMonth
        @unknown default: Decimal(value)
        }
    }

    /// True when a per-month breakdown is meaningful. A monthly plan's per-month
    /// figure is redundant; a weekly plan's is upsell noise.
    var isLongerThanAMonth: Bool { months > 1 }

    /// Price of one month at this plan's rate, for the "≈ X / mo" line and for
    /// comparing plans of different lengths.
    func monthlyEquivalent(of price: Decimal) -> Decimal? {
        let m = months
        guard m > 0 else { return nil }
        return price / m
    }

    /// Compact suffix for the plan card and CTA — "yr", "mo", "6 mo".
    /// Deliberately hand-rolled rather than using `subscriptionPeriodFormatStyle`,
    /// which spells out "one year" and overflows the narrow trailing column.
    var shortLabel: String {
        if value == 1 {
            switch unit {
            case .day:   return String(localized: "day", comment: "Compact billing period: one day")
            case .week:  return String(localized: "wk",  comment: "Compact billing period: one week")
            case .month: return String(localized: "mo",  comment: "Compact billing period: one month")
            case .year:  return String(localized: "yr",  comment: "Compact billing period: one year")
            @unknown default: return ""
            }
        }
        switch unit {
        case .day:   return String(localized: "\(value) days",   comment: "Compact billing period, plural days")
        case .week:  return String(localized: "\(value) wks",    comment: "Compact billing period, plural weeks")
        case .month: return String(localized: "\(value) mo",     comment: "Compact billing period, plural months")
        case .year:  return String(localized: "\(value) yrs",    comment: "Compact billing period, plural years")
        @unknown default: return ""
        }
    }

    /// Spelled-out period for the Guideline 3.1.2 disclosure, where clarity beats brevity.
    var longLabel: String {
        if value == 1 {
            switch unit {
            case .day:   return String(localized: "day",   comment: "Billing period noun, singular")
            case .week:  return String(localized: "week",  comment: "Billing period noun, singular")
            case .month: return String(localized: "month", comment: "Billing period noun, singular")
            case .year:  return String(localized: "year",  comment: "Billing period noun, singular")
            @unknown default: return ""
            }
        }
        switch unit {
        case .day:   return String(localized: "\(value) days",   comment: "Billing period noun, plural")
        case .week:  return String(localized: "\(value) weeks",  comment: "Billing period noun, plural")
        case .month: return String(localized: "\(value) months", comment: "Billing period noun, plural")
        case .year:  return String(localized: "\(value) years",  comment: "Billing period noun, plural")
        @unknown default: return ""
        }
    }

    /// "Billed every month" / "Billed every 12 months" — the plan card subtitle.
    var billingCadenceLabel: String {
        String(localized: "Billed every \(longLabel)", comment: "Plan card subtitle; argument is a period such as 'month' or '6 months'")
    }
}
