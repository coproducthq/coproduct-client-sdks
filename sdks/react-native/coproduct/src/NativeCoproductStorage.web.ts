import type { Spec } from './NativeCoproductStorage';

// Metro picks this file over NativeCoproductStorage.ts for web, where React
// Native for Web has no TurboModuleRegistry. The web is not a supported
// platform: this only keeps the native module lookup out of a web bundle
const NativeCoproductStorage: Spec | null = null;

export default NativeCoproductStorage;
