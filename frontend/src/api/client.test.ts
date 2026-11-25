import { describe, expect, it, vi } from 'vitest';
import { jsonResponse, mockFetch } from '../test/utils';
import { ApiError, apiGet, buildQuery } from './client';

describe('buildQuery', () => {
  it('skips empty, null and undefined values', () => {
    expect(
      buildQuery({ q: 'ankle', mode: '', difficulty: undefined, family_id: null, sort: 'name' }),
    ).toBe('?q=ankle&sort=name');
  });

  it('returns an empty string without parameters', () => {
    expect(buildQuery({})).toBe('');
  });

  it('encodes special characters', () => {
    expect(buildQuery({ q: 'a&b c' })).toBe('?q=a%26b+c');
  });
});

describe('apiGet', () => {
  it('returns the JSON body on success', async () => {
    const fetchMock = mockFetch([[/\/api\/v1\/families$/, () => jsonResponse([{ id: 1 }])]]);
    await expect(apiGet('/families')).resolves.toEqual([{ id: 1 }]);
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/families', expect.anything());
  });

  it('turns an API error body into ApiError', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mockFetch([
      [
        /exercises\/9999/,
        () =>
          jsonResponse(
            {
              error: {
                code: 'not_found',
                message: 'Exercise 9999 does not exist',
                request_id: 'r1',
              },
            },
            404,
          ),
      ],
    ]);
    const error = await apiGet('/exercises/9999').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 404, code: 'not_found', requestId: 'r1' });
    expect((error as ApiError).userMessage).toBe('Exercise 9999 does not exist');
  });

  it('uses a generic message for server errors without a JSON body', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mockFetch([[/health|exercises/, () => new Response('oops', { status: 500 })]]);
    const error = (await apiGet('/exercises').catch((e: unknown) => e)) as ApiError;
    expect(error.code).toBe('http_error');
    expect(error.userMessage).toBe('Something went wrong on the server. Please try again.');
  });

  it('reports network failures', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    const error = (await apiGet('/exercises').catch((e: unknown) => e)) as ApiError;
    expect(error).toMatchObject({ status: 0, code: 'network_error' });
  });

  it.each([
    [401, 'Please sign in to continue.'],
    [403, 'You do not have access to this resource.'],
    [503, 'The service is temporarily unavailable. Please try again in a moment.'],
  ])('maps status %i to a user message', (status, message) => {
    expect(new ApiError(status, 'x', 'raw').userMessage).toBe(message);
  });
});
