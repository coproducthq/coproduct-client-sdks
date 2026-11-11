import Foundation

/// StoreKit2's introductory-offer payment mode, narrowed to the three cases
/// the label composer handles. Kept separate from StoreKit's own type so this
/// file stays pure and unit-testable without importing StoreKit.
enum IntroOfferKind: Equatable {
    case freeTrial
    case payAsYouGo
    case payUpFront
}

/// Assembles the localized intro label from store-provided, already-localized
/// parts. The connective words ("free, then", "for", ...) are the only piece
/// not localized by the store. This is the spec's named localization risk,
/// isolated so a later locale pass changes only this function. `offerPrice` is
/// unused for a free trial.
func composeIntroLabel(kind: IntroOfferKind, offerPeriod: String, offerPrice: String, regularPrice: String) -> String {
    switch kind {
    case .freeTrial:
        return "\(offerPeriod) free, then \(regularPrice)"
    case .payAsYouGo, .payUpFront:
        return "\(offerPrice) for \(offerPeriod), then \(regularPrice)"
    }
}

/// Mirrors StoreKit2's `Product.SubscriptionPeriod.Unit`, narrowed to its four
/// cases. Kept separate from StoreKit's own type for the same reason as
/// `IntroOfferKind`: this file stays pure and unit-testable without importing
/// StoreKit.
enum SubscriptionPeriodUnit: Equatable {
    case day
    case week
    case month
    case year
}

/// Formats an offer's TOTAL duration -- one period of `value` `unit`s,
/// repeated `periodCount` times -- as a plural-aware phrase, e.g. "3 months",
/// "1 week". `offer.period` (StoreKit2's `Product.SubscriptionOffer.period`)
/// is the length of a single period; `periodCount` is how many times it
/// repeats, so a "$1.99/month for 3 months" pay-as-you-go offer reports
/// `value: 1, unit: .month, periodCount: 3` and must format as "3 months",
/// not "1 month". `Product.SubscriptionPeriod` has no public initializer a
/// caller can use to build a multiplied period and hand it to StoreKit's own
/// formatter, so the total is formatted here in English instead, matching
/// this composer's existing English-only connective words.
func formattedOfferPeriod(unit: SubscriptionPeriodUnit, value: Int, periodCount: Int) -> String {
    let total = value * max(periodCount, 1)
    let noun: String
    switch unit {
    case .day: noun = "day"
    case .week: noun = "week"
    case .month: noun = "month"
    case .year: noun = "year"
    }
    return "\(total) \(noun)\(total == 1 ? "" : "s")"
}

/// Appends a short trailing renewal suffix to an already-localized regular
/// price, e.g. "$39.99" + `.year` -> "$39.99/yr". Without this, a label reads
/// "then $39.99" with no indication of the billing period.
func appendingRenewalSuffix(to price: String, unit: SubscriptionPeriodUnit) -> String {
    let suffix: String
    switch unit {
    case .day: suffix = "/day"
    case .week: suffix = "/wk"
    case .month: suffix = "/mo"
    case .year: suffix = "/yr"
    }
    return "\(price)\(suffix)"
}
