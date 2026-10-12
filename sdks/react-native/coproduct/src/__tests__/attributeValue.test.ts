import { attributesToContext } from '../attributeValue';
import { ContextValue } from '../generated/coproduct_ffi_uniffi';

describe('attributesToContext', () => {
  it('converts a string value', () => {
    const result = attributesToContext({ plan: 'pro' });
    const value = result.get('plan')!;
    expect(ContextValue.String.instanceOf(value)).toBe(true);
    expect((value as InstanceType<typeof ContextValue.String>).inner.value).toBe('pro');
  });

  it('converts a number value', () => {
    const result = attributesToContext({ age: 42 });
    const value = result.get('age')!;
    expect(ContextValue.Number.instanceOf(value)).toBe(true);
    expect((value as InstanceType<typeof ContextValue.Number>).inner.value).toBe(42);
  });

  it('converts a boolean value', () => {
    const result = attributesToContext({ active: true });
    const value = result.get('active')!;
    expect(ContextValue.Bool.instanceOf(value)).toBe(true);
    expect((value as InstanceType<typeof ContextValue.Bool>).inner.value).toBe(true);
  });

  it('converts a string list value', () => {
    const result = attributesToContext({ tags: ['a', 'b'] });
    const value = result.get('tags')!;
    expect(ContextValue.StringList.instanceOf(value)).toBe(true);
    expect((value as InstanceType<typeof ContextValue.StringList>).inner.values).toEqual(['a', 'b']);
  });

  it('converts a null value', () => {
    const result = attributesToContext({ cleared: null });
    const value = result.get('cleared')!;
    expect(ContextValue.Null.instanceOf(value)).toBe(true);
  });

  it('converts multiple attributes into one map', () => {
    const result = attributesToContext({ plan: 'pro', age: 42 });
    expect(result.size).toBe(2);
  });
});
