package app.coproduct.paywall

/**
 * Play Billing's / StoreKit2's introductory-offer payment mode, narrowed to
 * the three cases the label composer handles. Kept separate from either
 * store's own type so this file stays pure and unit-testable without
 * importing Play Billing. Mirrors iOS's IntroOfferKind
 * (sdks/ios/Sources/Coproduct/Paywall/IntroOfferLabel.swift) and Flutter's
 * IntroOfferKind (sdks/flutter/coproduct/lib/src/paywall/intro_offer_label.dart).
 */
enum class IntroOfferKind { FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT }

/**
 * Assembles the localized intro label from store-provided, already-localized
 * parts. The connective words ("free, then", "for", ...) are the only piece
 * not localized by the store. This is the spec's named localization risk,
 * isolated so a later locale pass changes only this function. [offerPrice]
 * is unused for a free trial.
 */
fun composeIntroLabel(
    kind: IntroOfferKind,
    offerPeriod: String,
    offerPrice: String,
    regularPrice: String,
): String = when (kind) {
    IntroOfferKind.FREE_TRIAL -> "$offerPeriod free, then $regularPrice"
    IntroOfferKind.PAY_AS_YOU_GO, IntroOfferKind.PAY_UP_FRONT -> "$offerPrice for $offerPeriod, then $regularPrice"
}
