import {
  type CoproductClientLike,
  type CoproductSnapshot,
  type EvaluationHook,
  type EvaluationStage,
  type FlagEvaluationDetailsBool,
  type FlagEvaluationDetailsJson,
  type FlagEvaluationDetailsNumber,
  type FlagEvaluationDetailsString,
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

export class CoproductClient {
  private readonly identitySerializer = new IdentitySerializer();

  constructor(private readonly native: CoproductClientLike) {}

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
      }
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
