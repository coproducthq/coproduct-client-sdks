import type * as ReactNativeIap from 'react-native-iap';
import type {
  Purchase,
  PurchaseError,
  PurchaseIOS,
  SubscriptionOffer,
} from 'react-native-iap';
import { composeIntroLabel, type IntroOfferKind } from './introOfferLabel';
import type {
  NativePaywallBridge,
  PaywallIntroOffer,
  PackageKind,
  PaywallPackageRuntime,
  PurchaseResult,
  RestoredTransaction,
} from './nativePaywallBridge';

/** What a paywall reports when the app has not installed react-native-iap */
export const MISSING_IAP_MESSAGE =
  'Paywalls need react-native-iap and react-native-nitro-modules, which the ' +
  'Coproduct SDK lists as optional peer dependencies. Install them with ' +
  '"npm install react-native-iap react-native-nitro-modules", then run ' +
  '"pod install" in ios/ and rebuild the app.';

// Loaded on first use rather than imported, so an app that never shows a
// paywall need not install react-native-iap, which also adds Google Play's
// billing permission to every Android app that links it. Metro treats a
// require inside try as an optional dependency, so a missing package reaches
// the catch below instead of failing the bundle
let iapModule: typeof ReactNativeIap | undefined;
function iap(): typeof ReactNativeIap {
  if (iapModule == null) {
    try {
      iapModule = require('react-native-iap') as typeof ReactNativeIap;
    } catch {
      throw new Error(MISSING_IAP_MESSAGE);
    }
  }
  return iapModule;
}

// react-native-iap's own request/fetch type: 'subs' for a subscription,
// 'in-app' for every one-time product (consumable or lifetime) -- there is
// no third store-side type for "lifetime", StoreKit2 only distinguishes
// subscription vs. one-time purchase.
function storeTypeFor(kind: PackageKind): 'subs' | 'in-app' {
  return kind === 'subscription' ? 'subs' : 'in-app';
}

// A billing period this module can describe, independent of platform. iOS's
// SubscriptionPeriodIOS and the cross-platform SubscriptionPeriodUnit both
// carry an extra placeholder case ('empty' / 'unknown') that normalizeUnit
// filters out below, so this type never needs one.
type PeriodUnit = 'day' | 'week' | 'month' | 'year';

function normalizeUnit(unit: string | null | undefined): PeriodUnit | null {
  return unit === 'day' ||
    unit === 'week' ||
    unit === 'month' ||
    unit === 'year'
    ? unit
    : null;
}

// Parses the simple single-designator ISO 8601 durations Play Billing uses
// for a pricing phase's billingPeriod ("P1W", "P1M", "P3M", "P1Y", ...).
// Returns null for any other form rather than guessing.
function parseIsoPeriod(
  iso: string | undefined
): { unit: PeriodUnit; count: number } | null {
  if (iso == null) return null;
  const match = /^P(\d+)([DWMY])$/.exec(iso);
  if (match == null) return null;
  const count = Number.parseInt(match[1] ?? '', 10);
  if (!Number.isFinite(count) || count <= 0) return null;
  const unitByDesignator: Record<'D' | 'W' | 'M' | 'Y', PeriodUnit> = {
    D: 'day',
    W: 'week',
    M: 'month',
    Y: 'year',
  };
  const unit = unitByDesignator[match[2] as 'D' | 'W' | 'M' | 'Y'];
  return { unit, count };
}

function pluralizeUnit(unit: PeriodUnit, count: number): string {
  return count === 1 ? `1 ${unit}` : `${count} ${unit}s`;
}

// Billing-period suffix for a regular, already-localized price, e.g.
// "$39.99" + {year, 1} -> "$39.99/yr". A multi-cycle base period (billed
// every 3 months) has no standard single-letter abbreviation, so that case
// spells out the cycle count instead of guessing one.
function periodSuffix(period: { unit: PeriodUnit; count: number }): string {
  const abbreviation: Record<PeriodUnit, string> = {
    day: 'day',
    week: 'wk',
    month: 'mo',
    year: 'yr',
  };
  const suffix = abbreviation[period.unit];
  return period.count === 1 ? `/${suffix}` : `/${period.count}${suffix}`;
}

function subscriptionOffersOf(
  product: unknown
): SubscriptionOffer[] | undefined {
  if (typeof product !== 'object' || product == null) return undefined;
  const offers = (product as { subscriptionOffers?: unknown })
    .subscriptionOffers;
  return Array.isArray(offers) ? (offers as SubscriptionOffer[]) : undefined;
}

// The product's regular recurring billing period, used to append e.g. "/yr"
// to its displayed price. iOS carries this directly on the product
// (subscriptionPeriodUnitIOS/subscriptionPeriodNumberIOS). react-native-iap's
// Android product carries no equivalent top-level field, so it is read off
// any returned offer's native pricing-phase list: Play Billing always lists
// an offer's phases in billing order, so the last phase is the indefinitely
// recurring base price even when earlier phases are a trial or discount.
// Returns null -- leaving the price unsuffixed -- whenever neither source is
// present, rather than guessing a period.
function regularPeriodFor(
  product: unknown
): { unit: PeriodUnit; count: number } | null {
  const iosUnit = normalizeUnit(
    (product as { subscriptionPeriodUnitIOS?: string | null })
      .subscriptionPeriodUnitIOS
  );
  if (iosUnit != null) {
    const iosNumber = (
      product as { subscriptionPeriodNumberIOS?: string | null }
    ).subscriptionPeriodNumberIOS;
    const count =
      typeof iosNumber === 'string' ? Number.parseInt(iosNumber, 10) : NaN;
    if (Number.isFinite(count) && count > 0) return { unit: iosUnit, count };
  }

  const offers = subscriptionOffersOf(product);
  if (offers == null) return null;
  for (const offer of offers) {
    const phases = offer.pricingPhasesAndroid?.pricingPhaseList;
    if (phases == null || phases.length === 0) continue;
    const basePhase = phases[phases.length - 1];
    const parsed =
      basePhase != null ? parseIsoPeriod(basePhase.billingPeriod) : null;
    if (parsed != null) return parsed;
  }
  return null;
}

// Appends the regular billing period to an already-localized price when it
// can be determined, otherwise returns the price unchanged (fail-safe: a
// one-time product, or a subscription whose period cannot be read, is shown
// with its bare localized price rather than a guessed period).
function priceWithPeriod(product: unknown, price: string): string {
  const period = regularPeriodFor(product);
  return period == null ? price : `${price}${periodSuffix(period)}`;
}

function mapPaymentMode(
  mode: ReactNativeIap.PaymentMode | null | undefined
): IntroOfferKind | null {
  switch (mode) {
    case 'free-trial':
      return 'free_trial';
    case 'pay-as-you-go':
      return 'pay_as_you_go';
    case 'pay-up-front':
      return 'pay_up_front';
    default:
      // 'unknown', missing, or any future mode this SDK does not yet map:
      // fail safe rather than show trial copy for an offer it cannot describe.
      return null;
  }
}

// The introductory offer's own period, counting repeated cycles -- a
// "$1.99/month for 3 months" offer reports period.value === 1 and
// periodCount === 3, which must multiply out to "3 months", not "1 month".
// Falls back to the offer's native Android pricing-phase list when the
// cross-platform period/periodCount fields are absent: the first phase in
// Play Billing's phase list is the intro/discount phase that precedes the
// indefinitely recurring base phase, and its billingCycleCount is the same
// repeat count as iOS's periodCount.
function offerPeriodFor(
  offer: SubscriptionOffer
): { unit: PeriodUnit; count: number } | null {
  const unit = normalizeUnit(offer.period?.unit);
  if (
    unit != null &&
    typeof offer.period?.value === 'number' &&
    offer.period.value > 0
  ) {
    const cycles =
      typeof offer.periodCount === 'number' && offer.periodCount > 0
        ? offer.periodCount
        : 1;
    return { unit, count: offer.period.value * cycles };
  }

  const introPhase = offer.pricingPhasesAndroid?.pricingPhaseList?.[0];
  if (introPhase == null) return null;
  const parsed = parseIsoPeriod(introPhase.billingPeriod);
  if (parsed == null) return null;
  const cycles =
    introPhase.billingCycleCount > 0 ? introPhase.billingCycleCount : 1;
  return { unit: parsed.unit, count: parsed.count * cycles };
}

// Returns a normalized eligible intro offer, or null. react-native-iap
// reports every subscription offer -- introductory, promotional, or a plain
// Android base-plan offer with no discount -- in one cross-platform
// `subscriptionOffers` array; only an entry typed 'introductory' is this
// product's intro offer. Eligibility is the library's own concern: it omits
// an ineligible offer from the array rather than including one with a
// won't-apply flag, so finding one here already means this user qualifies.
// Returns null whenever the shape is anything other than that -- no offer,
// an unmapped payment mode, an unreadable period, or a discounted offer with
// no displayed price -- so no trial copy is ever shown on a guess.
function readEligibleIntroOffer(
  product: unknown
): { kind: IntroOfferKind; period: string; price: string } | null {
  const offers = subscriptionOffersOf(product);
  if (offers == null) return null;
  const introOffer = offers.find((offer) => offer.type === 'introductory');
  if (introOffer == null) return null;

  const kind = mapPaymentMode(introOffer.paymentMode);
  if (kind == null) return null;

  const period = offerPeriodFor(introOffer);
  if (period == null) return null;

  // offerPrice is unused by composeIntroLabel for a free trial, but a
  // discounted offer with no displayed price cannot be shown honestly.
  if (kind !== 'free_trial' && !introOffer.displayPrice) return null;

  return {
    kind,
    period: pluralizeUnit(period.unit, period.count),
    price: introOffer.displayPrice ?? '',
  };
}

function introFor(
  product: unknown,
  regularPrice: string
): PaywallIntroOffer | null {
  const offer = readEligibleIntroOffer(product);
  if (offer == null) return null;
  const label = composeIntroLabel({
    kind: offer.kind,
    offerPeriod: offer.period,
    offerPrice: offer.price,
    regularPrice,
  });
  return { eligible: true, label };
}

// react-native-iap-backed NativePaywallBridge. Owns the one genuinely new
// piece of logic this port needs beyond a straight line-for-line Flutter
// port: react-native-iap's requestPurchase() is fire-and-forget -- its own
// resolved value is never the purchase outcome, confirmed against the
// library's own native spec doc comment
// (node_modules/react-native-iap/src/specs/RnIap.nitro.ts): "returns the
// dispatched purchase payload; the outcome arrives through the listeners."
// This class correlates one requestPurchase() call with whichever
// purchaseUpdatedListener/purchaseErrorListener event answers it, finishes
// the transaction as part of settling success (react-native-iap does not
// auto-finish by default), and resolves a single Promise<PurchaseResult> --
// restoring the simple awaited shape every other file in this feature (and
// Flutter) expects.
// Purchase = PurchaseAndroid | PurchaseIOS; expirationDateIOS only exists on
// the iOS variant. An Android purchase therefore always resolves
// expirationDate as undefined here -- subscription expiry on Android is
// computed server-side from the recorded transaction, not carried on the
// purchase object itself.
function expirationDateFor(purchase: Purchase): Date | undefined {
  const expirationDateIOS = (purchase as PurchaseIOS).expirationDateIOS;
  return expirationDateIOS != null ? new Date(expirationDateIOS) : undefined;
}

// react-native-iap requires initConnection() before any other call in this
// module (fetchProducts, requestPurchase, getAvailablePurchases all reject
// with a native "not prepared" error otherwise). The connection is a
// process-wide native resource meant to stay open for the app's lifetime
// (react-native-iap's own docs: "keeps the native connection open across
// screens"), so this is memoized once per JS runtime rather than
// opened/closed per paywall session.
let connectionReady: Promise<boolean> | undefined;
function ensureConnection(): Promise<boolean> {
  if (connectionReady == null) connectionReady = iap().initConnection();
  return connectionReady;
}

// Also owns the two Android-specific problems with no iOS equivalent: a
// subscription purchase must name an explicit offer token (resolved via an
// extra fetchProducts call before the purchase flow starts), and a pending
// Android purchase arrives through this same purchaseUpdatedListener rather
// than through purchaseErrorListener the way iOS pending does.
export class IapPaywallBridge implements NativePaywallBridge {
  // Loads react-native-iap when a paywall mounts, so a missing install fails
  // with an actionable message before any purchase is attempted
  constructor() {
    iap();
  }

  // The single product-fetch path: priceFor delegates here rather than
  // duplicating it, since a caller that only needs the price still needs
  // every check packageFor already does (the product lookup, and the
  // not-found error) to produce it.
  async packageFor(
    productId: string,
    kind: PackageKind
  ): Promise<PaywallPackageRuntime> {
    await ensureConnection();
    const products =
      (await iap().fetchProducts({
        skus: [productId],
        type: storeTypeFor(kind),
      })) ?? [];
    const product = products[0];
    if (product?.displayPrice == null)
      throw new Error(`No product found for id "${productId}"`);
    const price = priceWithPeriod(product, product.displayPrice);
    const intro = introFor(product, price);
    return { price, intro };
  }

  async priceFor(productId: string, kind: PackageKind): Promise<string> {
    return (await this.packageFor(productId, kind)).price;
  }

  purchase(productId: string, kind: PackageKind): Promise<PurchaseResult> {
    const isConsumable = kind === 'consumable';
    const isSubscription = kind === 'subscription';

    // Listener registration below must stay synchronous with this call (no
    // await ahead of it): requestPurchase is fire-and-forget and its outcome
    // only ever arrives through these listeners, so if a caller's purchase
    // event could in principle fire before they're attached, it would be
    // missed. Connection readiness is therefore awaited further down, just
    // ahead of the native requestPurchase call, not here.
    return new Promise<PurchaseResult>((resolve, reject) => {
      const updatedSubscription = iap().purchaseUpdatedListener(
        (purchase: Purchase) => {
          if (purchase.productId !== productId) return;
          // Android reports a pending purchase (e.g. a cash-based payment
          // method awaiting confirmation) through this same listener,
          // unlike iOS's "Ask to Buy" pending, which purchaseErrorListener
          // carries. A pending purchase isn't charged yet, so it must not
          // be finished.
          if (purchase.purchaseState === 'pending') {
            cleanup();
            resolve({ outcome: 'pending' });
            return;
          }
          cleanup();
          // Deliberately not awaited: this listener callback itself isn't
          // awaited by its caller, so there's nothing to block on besides
          // the .finally() below, which resolves the outer Promise either way.
          // eslint-disable-next-line no-void
          void iap()
            .finishTransaction({ purchase, isConsumable })
            .catch(() => {
              // Finishing an already-finished transaction, or a transient
              // native failure to finish, must not block reporting the
              // purchase itself -- the charge already happened
            })
            .finally(() => {
              resolve({
                outcome: 'success',
                transactionId: purchase.transactionId ?? undefined,
                productId: purchase.productId,
                purchaseDate: new Date(purchase.transactionDate),
                expirationDate: expirationDateFor(purchase),
              });
            });
        }
      );

      const errorSubscription = iap().purchaseErrorListener(
        (error: PurchaseError) => {
          if (error.productId != null && error.productId !== productId) return;
          cleanup();
          if (error.code === iap().ErrorCode.UserCancelled) {
            resolve({ outcome: 'cancelled' });
          } else if (error.code === iap().ErrorCode.Pending) {
            resolve({ outcome: 'pending' });
          } else {
            reject(new Error(error.message));
          }
        }
      );

      function cleanup(): void {
        updatedSubscription.remove();
        errorSubscription.remove();
      }

      // Play Billing has no bare "buy this subscription" call -- every
      // subscription purchase must name a specific offer (its offerToken),
      // which StoreKit2 has no equivalent of. A one-time purchase carries no
      // such requirement on this library's Android surface, so this is skipped
      // entirely outside the subscription case.
      ensureConnection()
        .then(async () => {
          if (!isSubscription) {
            return iap().requestPurchase({
              request: {
                apple: { sku: productId },
                google: { skus: [productId] },
              },
              type: storeTypeFor(kind),
            });
          }

          // Falls back to an empty offer list if the product lookup returns
          // nothing, so a transient fetchProducts failure degrades to a
          // plain subscription request rather than throwing.
          const products =
            (await iap().fetchProducts({ skus: [productId], type: 'subs' })) ??
            [];
          const offers = products[0]?.subscriptionOffers ?? [];
          const subscriptionOffers = offers
            .map((offer) => offer.offerTokenAndroid)
            .filter((offerToken): offerToken is string => offerToken != null)
            .map((offerToken) => ({ sku: productId, offerToken }));

          return iap().requestPurchase({
            request: {
              apple: { sku: productId },
              google: {
                skus: [productId],
                ...(subscriptionOffers.length > 0 && {
                  subscriptionOffers,
                }),
              },
            },
            type: storeTypeFor(kind),
          });
        })
        .catch((error: unknown) => {
          cleanup();
          reject(error instanceof Error ? error : new Error(String(error)));
        });
    });
  }

  async restore(): Promise<RestoredTransaction[]> {
    await ensureConnection();
    const purchases = await iap().getAvailablePurchases();
    const restored: RestoredTransaction[] = [];
    for (const purchase of purchases) {
      try {
        await iap().finishTransaction({ purchase, isConsumable: false });
      } catch {
        // Already-finished or a transient native failure to finish must
        // not drop this transaction from the restored set
      }
      if (purchase.transactionId == null) continue;
      restored.push({
        transactionId: purchase.transactionId,
        productId: purchase.productId,
        purchaseDate: new Date(purchase.transactionDate),
        expirationDate: expirationDateFor(purchase),
      });
    }
    return restored;
  }
}
