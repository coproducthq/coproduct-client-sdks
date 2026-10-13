// Serializes fire-and-forget identity mutations so they apply in call order.
// Each enqueued operation must catch its own errors: a rejection here would
// otherwise poison every later operation chained onto the same tail promise.
export class IdentitySerializer {
  private tail: Promise<void> = Promise.resolve();

  enqueue(operation: () => Promise<void>): void {
    this.tail = this.tail.then(operation);
  }

  drain(): Promise<void> {
    return this.tail;
  }
}
