// Names the README's fragment examples take from its earlier examples, and
// the placeholder screens its hook example renders
import type { CoproductClient as Client } from '@coproduct/react-native-sdk';

declare global {
  type CoproductClient = Client;
  const client: Client;
  function useFlag(client: Client | null, key: string, defaultValue: boolean): boolean;
  function NewCheckoutFlow(): null;
  function LegacyCheckoutFlow(): null;
}
