/// StoreKit2's / Play Billing's introductory-offer payment mode, narrowed to
/// the three cases the label composer handles. Kept separate from either
/// store's own type so this file stays pure and unit-testable without
/// importing StoreKit or Play Billing. Mirrors iOS's IntroOfferKind
/// (sdks/ios/Sources/Coproduct/Paywall/IntroOfferLabel.swift) and React
/// Native's IntroOfferKind
/// (sdks/react-native/coproduct/src/paywall/introOfferLabel.ts).
enum IntroOfferKind { freeTrial, payAsYouGo, payUpFront }

/// Assembles the localized intro label from store-provided, already-localized
/// parts. The connective words ("free, then", "for", ...) are the only piece
/// not localized by the store. This is the spec's named localization risk,
/// isolated so a later locale pass changes only this function. [offerPrice]
/// is unused for a free trial.
String composeIntroLabel({
  required IntroOfferKind kind,
  required String offerPeriod,
  required String offerPrice,
  required String regularPrice,
}) {
  switch (kind) {
    case IntroOfferKind.freeTrial:
      return '$offerPeriod free, then $regularPrice';
    case IntroOfferKind.payAsYouGo:
    case IntroOfferKind.payUpFront:
      return '$offerPrice for $offerPeriod, then $regularPrice';
  }
}
