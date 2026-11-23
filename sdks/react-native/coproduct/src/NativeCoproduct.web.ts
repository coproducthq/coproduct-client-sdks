import type { Spec } from './NativeCoproduct';

// The SDK's core is a native library, so a web bundle has no module to load.
// Metro picks this file over NativeCoproduct.ts for web, where React Native
// for Web has no TurboModuleRegistry. The web is not a supported platform:
// this only keeps the native module lookup out of a web bundle
const NativeCoproduct: Spec | null = null;

export default NativeCoproduct;
