// StoreKit2 / Play Billing introductory-offer payment mode, narrowed to the
// three cases the label composer handles. Kept separate from the store SDKs'
// own types so this stays a pure, unit-testable function.
export type IntroOfferKind = 'free_trial' | 'pay_as_you_go' | 'pay_up_front';

// Assembles the localized intro label from store-provided, already-localized
// parts. The connective words ("free, then", "for", ...) are the only piece
// not localized by the store. This is the spec's named localization risk,
// isolated so a later locale pass changes only this function. offerPrice is
// unused for a free trial.
export function composeIntroLabel(args: {
  kind: IntroOfferKind;
  offerPeriod: string;
  offerPrice: string;
  regularPrice: string;
}): string {
  const { kind, offerPeriod, offerPrice, regularPrice } = args;
  if (kind === 'free_trial') return `${offerPeriod} free, then ${regularPrice}`;
  return `${offerPrice} for ${offerPeriod}, then ${regularPrice}`;
}
