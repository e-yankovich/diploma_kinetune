// Centralised HTTP client: every request goes through apiGet(), which turns
// non-2xx responses into ApiError with the API's error code and message.
import type { ApiErrorBody } from '../types/api';
import { logger } from '../utils/logger';

export const API_BASE = '/api/v1';

const STATUS_MESSAGE: Record<number, string> = {
  401: 'Please sign in to continue.',
  403: 'You do not have access to this resource.',
  404: 'The requested item was not found.',
  422: 'The request is not valid.',
  500: 'Something went wrong on the server. Please try again.',
  503: 'The service is temporarily unavailable. Please try again in a moment.',
};

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly requestId: string | null;

  constructor(status: number, code: string, message: string, requestId: string | null = null) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.requestId = requestId;
  }

  /** Message for the user: the API message for 404/422, a generic one otherwise. */
  get userMessage(): string {
    if (this.status === 404 || this.status === 422) return this.message;
    return STATUS_MESSAGE[this.status] ?? STATUS_MESSAGE[500];
  }
}

export type QueryParams = Record<string, string | number | boolean | undefined | null | ''>;

export function buildQuery(params: QueryParams): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') search.set(key, String(value));
  }
  const text = search.toString();
  return text ? `?${text}` : '';
}

export async function apiGet<T>(path: string, params: QueryParams = {}): Promise<T> {
  const url = `${API_BASE}${path}${buildQuery(params)}`;
  let response: Response;
  try {
    response = await fetch(url, { headers: { Accept: 'application/json' } });
  } catch (cause) {
    logger.error('network error', { url, cause: String(cause) });
    throw new ApiError(0, 'network_error', 'Cannot reach the server. Check your connection.');
  }
  if (!response.ok) {
    let body: ApiErrorBody | null = null;
    try {
      body = (await response.json()) as ApiErrorBody;
    } catch {
      body = null;
    }
    const error = new ApiError(
      response.status,
      body?.error.code ?? 'http_error',
      body?.error.message ?? STATUS_MESSAGE[response.status] ?? response.statusText,
      body?.error.request_id ?? response.headers.get('X-Request-ID'),
    );
    logger.error('api error', {
      url,
      status: error.status,
      code: error.code,
      requestId: error.requestId,
    });
    throw error;
  }
  return (await response.json()) as T;
}
