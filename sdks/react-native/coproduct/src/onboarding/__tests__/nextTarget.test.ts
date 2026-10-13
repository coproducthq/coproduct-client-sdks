import { parseNextTarget } from '../models/nextTarget';

describe('parseNextTarget', () => {
  it('parses a screen target', () => {
    const target = parseNextTarget({ type: 'screen', screenId: 's2' });
    expect(target).toEqual({ type: 'screen', screenId: 's2' });
  });

  it('parses dismiss and complete', () => {
    expect(parseNextTarget({ type: 'dismiss' })).toEqual({ type: 'dismiss' });
    expect(parseNextTarget({ type: 'complete' })).toEqual({ type: 'complete' });
  });

  it('throws on an unknown type', () => {
    expect(() => parseNextTarget({ type: 'explode' })).toThrow('Unknown NextTarget type: explode');
  });
});
