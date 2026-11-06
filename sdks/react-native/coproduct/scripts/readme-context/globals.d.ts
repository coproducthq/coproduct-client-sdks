// Names the README's fragment examples take from its earlier examples
import type { CoproductClient as Client } from '@coproduct/react-native-sdk';

declare global {
  type CoproductClient = Client;
  const client: Client;
}
