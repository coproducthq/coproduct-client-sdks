const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * Allow imports from the repo's tests/ dir so
 * tests/bucketing_vectors.json is the single source of truth.
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const repoRoot = path.resolve(__dirname, '..', '..');

const config = {
  watchFolders: [path.join(repoRoot, 'tests')],
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
