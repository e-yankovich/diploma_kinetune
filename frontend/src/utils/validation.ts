// Validation rules of the filter form (the API accepts 2–100 characters).
export const SEARCH_MIN = 2;
export const SEARCH_MAX = 100;

export function validateSearch(q: string): string | null {
  const text = q.trim();
  if (text.length === 0) return null;
  if (text.length < SEARCH_MIN) return `Enter at least ${SEARCH_MIN} characters.`;
  if (text.length > SEARCH_MAX) return `Use at most ${SEARCH_MAX} characters.`;
  return null;
}
