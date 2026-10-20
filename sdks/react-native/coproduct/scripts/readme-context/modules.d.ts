// The README reads the SDK key with react-native-config, which belongs to the
// reader's app rather than to the SDK
declare module 'react-native-config' {
  const Config: Record<string, string | undefined>;
  export default Config;
}
