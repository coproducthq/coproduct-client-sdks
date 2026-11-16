import {
  type CoproductClientLike,
  type CoproductSnapshot,
  type EvaluationEvent,
  type EvaluationHook,
  type EvaluationListener,
  type EvaluationStage,
  type FlagEvaluationDetailsBool,
  type FlagEvaluationDetailsJson,
  type FlagEvaluationDetailsNumber,
  type FlagEvaluationDetailsNumberList,
  type FlagEvaluationDetailsString,
  type FlagEvaluationDetailsStringList,
  type HookContext,
  type LifecycleEvent,
  type LifecycleHandler,
  type ProviderState,
  BoolDelivery,
  IntDelivery,
  JsonDelivery,
  NumberDelivery,
  StringDelivery,
} from './generated/coproduct_ffi_uniffi';
import { attributesToContext, type AttributeValue } from './attributeValue';
import { IdentitySerializer } from './identitySerializer';
import { HttpPaywallClient } from './paywall/httpPaywallClient';
import { observeDrain, type Cancellable } from './observation';
import { captureUtm } from './utmStore';

// Int flag values travel as bigint over FFI (Rust's Int64). RN callers use
// plain numbers, matching every other typed getter's ergonomics and avoiding
// BigInt's JSON.stringify/arithmetic friction in ordinary app code.
export type FlagEvaluationDetailsInt = {
  value: number;
  variant?: string;
  reason: string;
  errorCode?: string;
  errorMessage?: string;
  flagKey: string;
};

/**
 * What a CoproductClient needs to know this install's anonymous id and to
 * tell the server when identify links it to a user id. Supplied by
 * Coproduct.initialize. A client built without it has no anonymousId and
 * sends nothing on identify.
 */
export type CoproductClientIdentityLink = {
  /** Reads the install's current anonymous id, undefined until known. */
  anonymousId: () => string | undefined;
  /** The SDK key, sent as the Bearer token of the identify request. */
  sdkKey: string;
  /** API base URL. Defaults to https://api.coproduct.app. */
  apiBaseUrl?: string;
};

// Anonymous id and user id pairs already sent to the server by this process,
// so a repeated identify for the same user does not repeat the request. A
// failed request removes its pair so a later identify can try again.
const linkedPairs = new Set<string>();

export class CoproductClient {
  private readonly identitySerializer = new IdentitySerializer();

  constructor(
    private readonly native: CoproductClientLike,
    private readonly identityLink?: CoproductClientIdentityLink
  ) {}

  // MARK: Typed getters (never throw; the native client always returns the
  // caller's default when a flag is missing, the wrong type, or not ready)

  getBool(key: string, defaultValue: boolean): boolean {
    return this.native.getBool(key, defaultValue);
  }

  getBoolDetails(
    key: string,
    defaultValue: boolean
  ): FlagEvaluationDetailsBool {
    return this.native.getBoolDetails(key, defaultValue);
  }

  getString(key: string, defaultValue: string): string {
    return this.native.getString(key, defaultValue);
  }

  getStringDetails(
    key: string,
    defaultValue: string
  ): FlagEvaluationDetailsString {
    return this.native.getStringDetails(key, defaultValue);
  }

  getInt(key: string, defaultValue: number): number {
    return Number(this.native.getInt(key, BigInt(defaultValue)));
  }

  getIntDetails(key: string, defaultValue: number): FlagEvaluationDetailsInt {
    const details = this.native.getIntDetails(key, BigInt(defaultValue));
    return { ...details, value: Number(details.value) };
  }

  getNumber(key: string, defaultValue: number): number {
    return this.native.getNumber(key, defaultValue);
  }

  getNumberDetails(
    key: string,
    defaultValue: number
  ): FlagEvaluationDetailsNumber {
    return this.native.getNumberDetails(key, defaultValue);
  }

  getStringList(key: string, defaultValue: string[]): string[] {
    return this.native.getStringList(key, defaultValue);
  }

  getStringListDetails(
    key: string,
    defaultValue: string[]
  ): FlagEvaluationDetailsStringList {
    return this.native.getStringListDetails(key, defaultValue);
  }

  getNumberList(key: string, defaultValue: number[]): number[] {
    return this.native.getNumberList(key, defaultValue);
  }

  getNumberListDetails(
    key: string,
    defaultValue: number[]
  ): FlagEvaluationDetailsNumberList {
    return this.native.getNumberListDetails(key, defaultValue);
  }

  getJson(key: string, defaultValueJson: string): string {
    return this.native.getJson(key, defaultValueJson);
  }

  getJsonDetails(
    key: string,
    defaultValueJson: string
  ): FlagEvaluationDetailsJson {
    return this.native.getJsonDetails(key, defaultValueJson);
  }

  // MARK: Identity (fire-and-forget; applies in call order via
  // identitySerializer; a rejection is logged, never thrown to the caller)

  /**
   * Signs the user in locally, then, unless linkAnonymous is false, tells the
   * server that this install's anonymous id now belongs to userId so purchases
   * and entitlements recorded under the anonymous id follow the user. The
   * server request is best-effort: it never delays or fails identify, a
   * failure is only logged, and it is skipped when the anonymous id is
   * unknown or equal to userId.
   */
  identify(
    userId: string,
    attributes: Record<string, AttributeValue> = {},
    linkAnonymous = true
  ): void {
    const context = attributesToContext(attributes);
    this.identitySerializer.enqueue(async () => {
      try {
        await this.native.identify(userId, context, linkAnonymous);
      } catch (error) {
        console.error('[coproduct] identify failed', error);
        return;
      }
      if (linkAnonymous) this.linkAnonymousId(userId);
    });
  }

  // POST /v1/identify with this install's anonymous id and the user id.
  // Deliberately not awaited by the caller: the request must never delay or
  // fail the identity queue.
  private linkAnonymousId(userId: string): void {
    const link = this.identityLink;
    if (link == null) return;
    const anonymousId = link.anonymousId();
    if (anonymousId == null || anonymousId === userId) return;
    const pair = JSON.stringify([anonymousId, userId]);
    if (linkedPairs.has(pair)) return;
    linkedPairs.add(pair);
    new HttpPaywallClient({ sdkKey: link.sdkKey, apiBaseUrl: link.apiBaseUrl })
      .identify({ appUserId: anonymousId, targetingKey: userId })
      .catch((error: unknown) => {
        linkedPairs.delete(pair);
        console.error('[coproduct] identify link failed', error);
      });
  }

  signOut(): void {
    this.identitySerializer.enqueue(async () => {
      await this.native.signOut();
    });
  }

  setContext(
    targetingKey: string,
    attributes: Record<string, AttributeValue> = {}
  ): void {
    const context = attributesToContext(attributes);
    this.identitySerializer.enqueue(async () => {
      try {
        await this.native.setContext(targetingKey, context);
      } catch (error) {
        console.error('[coproduct] setContext failed', error);
      }
    });
  }

  updateAttributes(attributes: Record<string, AttributeValue>): void {
    const context = attributesToContext(attributes);
    this.identitySerializer.enqueue(async () => {
      await this.native.updateAttributes(context);
    });
  }

  removeAttributes(keys: string[]): void {
    this.identitySerializer.enqueue(async () => {
      await this.native.removeAttributes(keys);
    });
  }

  /**
   * This install's anonymous id: the id purchases and entitlements are keyed
   * by until the app supplies its own. Undefined until the SDK has read or
   * generated it, and for a client not created by Coproduct.initialize.
   */
  get anonymousId(): string | undefined {
    return this.identityLink?.anonymousId();
  }

  get previousAnonymousId(): string | undefined {
    return this.native.previousAnonymousId();
  }

  /**
   * Captures UTM parameters from a URL (install link, deep link, or web
   * referrer) into first-touch and last-touch attribution attributes, then
   * publishes them as auto-populated attributes. First-touch is captured
   * once and frozen thereafter, while last-touch is overwritten on every
   * call. A no-op when the URL carries no UTM parameters
   */
  async captureAttribution(url: string): Promise<void> {
    const attrs = await captureUtm(url);
    if (Object.keys(attrs).length) {
      await this.setAutoPopulatedAttributes(attrs);
    }
  }

  // MARK: Observation (returns a Cancellable; seeds with the current value,
  // then delivers later values in order via the generic drain loop)

  observeBool(
    key: string,
    defaultValue: boolean,
    onChange: (value: boolean) => void | Promise<void>
  ): Cancellable {
    return observeDrain(
      this.native.observeBool(key),
      defaultValue,
      (delivery) =>
        BoolDelivery.Value.instanceOf(delivery)
          ? { kind: 'value', value: delivery.inner.value }
          : { kind: 'closed' },
      onChange
    );
  }

  observeString(
    key: string,
    defaultValue: string,
    onChange: (value: string) => void | Promise<void>
  ): Cancellable {
    return observeDrain(
      this.native.observeString(key),
      defaultValue,
      (delivery) =>
        StringDelivery.Value.instanceOf(delivery)
          ? { kind: 'value', value: delivery.inner.value }
          : { kind: 'closed' },
      onChange
    );
  }

  observeInt(
    key: string,
    defaultValue: number,
    onChange: (value: number) => void | Promise<void>
  ): Cancellable {
    return observeDrain(
      this.native.observeInt(key),
      BigInt(defaultValue),
      (delivery) =>
        IntDelivery.Value.instanceOf(delivery)
          ? { kind: 'value', value: delivery.inner.value }
          : { kind: 'closed' },
      (value) => onChange(Number(value))
    );
  }

  observeNumber(
    key: string,
    defaultValue: number,
    onChange: (value: number) => void | Promise<void>
  ): Cancellable {
    return observeDrain(
      this.native.observeNumber(key),
      defaultValue,
      (delivery) =>
        NumberDelivery.Value.instanceOf(delivery)
          ? { kind: 'value', value: delivery.inner.value }
          : { kind: 'closed' },
      onChange
    );
  }

  observeJson(
    key: string,
    defaultValueJson: string,
    onChange: (valueJson: string) => void | Promise<void>
  ): Cancellable {
    return observeDrain(
      this.native.observeJson(key),
      defaultValueJson,
      (delivery) =>
        JsonDelivery.Value.instanceOf(delivery)
          ? { kind: 'value', value: delivery.inner.value }
          : { kind: 'closed' },
      onChange
    );
  }

  // MARK: Handlers/hooks

  /**
   * Register a lifecycle handler. Keep the returned handle for as long as the
   * handler should stay active. Calling cancel, or letting the handle be
   * garbage collected, removes the handler, so a discarded handle can stop
   * the handler from ever firing.
   */
  addHandler(
    event: LifecycleEvent,
    handler: (event: LifecycleEvent) => void
  ): Cancellable {
    const wrapped: LifecycleHandler = {
      onEvent: async (firedEvent) => {
        handler(firedEvent);
      },
    };
    const handle = this.native.addHandler(event, wrapped);
    return { cancel: () => handle.cancel() };
  }

  addEvaluationHook(
    stage: EvaluationStage,
    handler: (ctx: HookContext) => void
  ): Cancellable {
    const wrapped: EvaluationHook = {
      onStage: (firedStage, ctx) => {
        if (firedStage !== stage) return;
        handler(ctx);
      },
    };
    const handle = this.native.addEvaluationHook(wrapped);
    return { cancel: () => handle.cancel() };
  }

  // Fires synchronously on every evaluation, so keep onEvaluation cheap and
  // non-blocking -- do not do expensive or blocking work directly in it.
  setEvaluationListener(onEvaluation: (event: EvaluationEvent) => void): void {
    const wrapped: EvaluationListener = {
      onEvaluation: (event) => {
        onEvaluation(event);
      },
    };
    this.native.setEvaluationListener(wrapped);
  }

  // MARK: State / snapshot / shutdown

  get state(): ProviderState {
    return this.native.state();
  }

  get snapshot(): CoproductSnapshot {
    return this.native.snapshotView();
  }

  async shutdown(): Promise<void> {
    await this.native.shutdown();
  }

  // Internal: used by index.tsx's host timer and network monitor wiring.
  setAutoPopulatedAttributes(
    attributes: Record<string, AttributeValue>
  ): Promise<void> {
    return this.native.setAutoPopulatedAttributes(
      attributesToContext(attributes)
    );
  }

  pollNow(): ReturnType<CoproductClientLike['pollNow']> {
    return this.native.pollNow();
  }
}
