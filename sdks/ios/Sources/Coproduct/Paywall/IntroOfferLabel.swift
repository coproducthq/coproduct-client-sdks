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
