module.exports = {
  preset: 'react-native',
  testPathIgnorePatterns: ['/node_modules/', '/lib/', '/example/', '/example-expo/'],
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?|@react-native-async-storage|react-native-permissions|react-native-webview|react-native-iap|react-native-nitro-modules)/)',
  ],
};
