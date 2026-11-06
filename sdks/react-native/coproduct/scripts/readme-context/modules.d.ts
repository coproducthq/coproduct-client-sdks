// The README reads the SDK key with react-native-config, which belongs to the
// reader's app rather than to the SDK
declare module 'react-native-config' {
  const Config: Record<string, string | undefined>;
  export default Config;
}

// Expo apps read EXPO_PUBLIC_ variables through process.env, which Expo's own
// types declare
declare const process: { env: Record<string, string | undefined> };
