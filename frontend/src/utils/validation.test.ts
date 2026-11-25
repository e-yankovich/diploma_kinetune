import { describe, expect, it } from 'vitest';
import { SEARCH_MAX, validateSearch } from './validation';

describe('validateSearch', () => {
  it('accepts an empty search', () => expect(validateSearch('   ')).toBeNull());
  it('rejects one character', () =>
    expect(validateSearch('a')).toBe('Enter at least 2 characters.'));
  it('accepts 2 to 100 characters', () => {
    expect(validateSearch('ab')).toBeNull();
    expect(validateSearch('x'.repeat(SEARCH_MAX))).toBeNull();
  });
  it('rejects more than 100 characters', () =>
    expect(validateSearch('x'.repeat(SEARCH_MAX + 1))).toBe('Use at most 100 characters.'));
});
