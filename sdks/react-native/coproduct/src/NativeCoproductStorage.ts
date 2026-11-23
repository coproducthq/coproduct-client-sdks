import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

// The app directories the SDK keeps its files in. A module separate from
// NativeCoproduct, which installs the Rust core: Android autolinks a C++
// implementation of that one, and C++ cannot reach the app's directories.
// This module is Objective-C on iOS and Kotlin on Android
export interface Spec extends TurboModule {
  // The app's caches directory: NSCachesDirectory on iOS, Context.getCacheDir()
  // on Android. The core keeps its flag snapshot there
  cachesDirectoryPath(): string;
  // Reads a file directly inside the app's documents directory
  // (NSDocumentDirectory on iOS, Context.getFilesDir() on Android), or null
  // when it does not exist. name is a bare file name, never a path
  readDocumentFile(name: string): string | null;
  // Writes a file directly inside the documents directory, replacing it
  // atomically. Returns whether the write succeeded
  writeDocumentFile(name: string, contents: string): boolean;
}

// get, not getEnforcing, for the same reason as NativeCoproduct
export default TurboModuleRegistry.get<Spec>('CoproductStorage');
