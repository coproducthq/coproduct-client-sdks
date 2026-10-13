import { IdentitySerializer } from '../identitySerializer';

describe('IdentitySerializer', () => {
  it('runs enqueued operations in call order', async () => {
    const serializer = new IdentitySerializer();
    const order: number[] = [];

    serializer.enqueue(async () => {
      await new Promise((resolve) => setTimeout(resolve, 20));
      order.push(1);
    });
    serializer.enqueue(async () => {
      order.push(2);
    });
    serializer.enqueue(async () => {
      order.push(3);
    });

    await serializer.drain();
    expect(order).toEqual([1, 2, 3]);
  });

  it('continues running later operations after an earlier one is enqueued', async () => {
    const serializer = new IdentitySerializer();
    const order: number[] = [];

    serializer.enqueue(async () => {
      order.push(1);
    });
    await serializer.drain();

    serializer.enqueue(async () => {
      order.push(2);
    });
    await serializer.drain();

    expect(order).toEqual([1, 2]);
  });
});
