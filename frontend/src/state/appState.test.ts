import { describe, expect, it } from 'vitest';
import { appReducer, DEFAULT_FILTERS, INITIAL_STATE } from './appState';

describe('appReducer', () => {
  it('sets and resets the filters', () => {
    const filtered = appReducer(INITIAL_STATE, {
      type: 'setFilters',
      filters: { ...DEFAULT_FILTERS, familyId: 3, sort: 'difficulty' },
    });
    expect(filtered.filters).toMatchObject({ familyId: 3, sort: 'difficulty' });
    expect(appReducer(filtered, { type: 'resetFilters' }).filters).toEqual(DEFAULT_FILTERS);
  });

  it('adds and removes toasts without touching the filters', () => {
    const withToast = appReducer(INITIAL_STATE, {
      type: 'addToast',
      toast: { id: 7, kind: 'error', message: 'Server error' },
    });
    expect(withToast.toasts).toHaveLength(1);
    expect(withToast.filters).toBe(INITIAL_STATE.filters);
    expect(appReducer(withToast, { type: 'removeToast', id: 7 }).toasts).toEqual([]);
  });
});
