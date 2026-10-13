jest.mock('@react-native-async-storage/async-storage', () =>
  // factory runs before this file's own imports (Babel hoists jest.mock calls
  // above import statements), so it must use a runtime require, not an import.
  // The installed 2.2.0 package has no bare `/jest` subpath or
  // `clearAllMockStorages` export (unlike some docs/newer versions) -- it
  // ships only `jest/async-storage-mock.js`, verified by inspecting the
  // installed package directly.
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);

import AsyncStorage from '@react-native-async-storage/async-storage';
import { LocalProgressStore } from '../localProgressStore';

beforeEach(async () => {
  await AsyncStorage.clear();
});

describe('LocalProgressStore', () => {
  it('round-trips saved progress for a flowId', async () => {
    const store = new LocalProgressStore();
    await store.save({
      flowId: 'f-1',
      version: 2,
      screenId: 'goal',
      answers: { goal: ['lose_weight'] },
    });

    const loaded = await store.load({ flowId: 'f-1' });
    expect(loaded).toEqual({
      version: 2,
      screenId: 'goal',
      answers: { goal: ['lose_weight'] },
    });
  });

  it('returns undefined for a flowId with no saved progress', async () => {
    const store = new LocalProgressStore();
    expect(await store.load({ flowId: 'never-started' })).toBeUndefined();
  });

  it('keeps two flowIds independent', async () => {
    const store = new LocalProgressStore();
    await store.save({ flowId: 'f-1', version: 1, screenId: 'a', answers: {} });
    await store.save({ flowId: 'f-2', version: 1, screenId: 'b', answers: {} });

    expect((await store.load({ flowId: 'f-1' }))?.screenId).toBe('a');
    expect((await store.load({ flowId: 'f-2' }))?.screenId).toBe('b');
  });

  it('clear removes saved progress', async () => {
    const store = new LocalProgressStore();
    await store.save({ flowId: 'f-1', version: 1, screenId: 'a', answers: {} });
    await store.clear({ flowId: 'f-1' });
    expect(await store.load({ flowId: 'f-1' })).toBeUndefined();
  });
});
