import { ContextValue } from './generated/coproduct_ffi_uniffi';

export type AttributeValue =
  | string
  | number
  | boolean
  | string[]
  | number[]
  | null;

export function attributeValueToContextValue(
  value: AttributeValue
): ContextValue {
  if (value === null) {
    return ContextValue.Null.new();
  }
  if (Array.isArray(value)) {
    // Element type is checked on the first element; a homogeneous list is
    // assumed. An empty list has no knowable element type, so it maps to
    // StringList by convention.
    if (value.length > 0 && typeof value[0] === 'number') {
      return ContextValue.NumberList.new({ values: value as number[] });
    }
    return ContextValue.StringList.new({ values: value as string[] });
  }
  if (typeof value === 'string') {
    return ContextValue.String.new({ value });
  }
  if (typeof value === 'number') {
    return ContextValue.Number.new({ value });
  }
  return ContextValue.Bool.new({ value });
}

export function attributesToContext(
  attributes: Record<string, AttributeValue>
): Map<string, ContextValue> {
  const context = new Map<string, ContextValue>();
  for (const [key, value] of Object.entries(attributes)) {
    context.set(key, attributeValueToContextValue(value));
  }
  return context;
}
