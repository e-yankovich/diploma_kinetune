// Runs an async loader, tracks loading/error state and reports unexpected
// errors (500, 503, network) as a toast. 404 is left to the page.
import { useCallback, useEffect, useState } from 'react';
import { ApiError } from '../api/client';
import { useAppState } from '../state/appState';

export interface AsyncState<T> {
  data: T | null;
  error: ApiError | null;
  loading: boolean;
  reload: () => void;
}

export function useAsync<T>(loader: () => Promise<T>, deps: unknown[]): AsyncState<T> {
  const { notify } = useAppState();
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [loading, setLoading] = useState(true);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    loader()
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch((cause: unknown) => {
        if (cancelled) return;
        const apiError =
          cause instanceof ApiError ? cause : new ApiError(500, 'internal_error', String(cause));
        setError(apiError);
        if (apiError.status !== 404 && apiError.status !== 422) notify(apiError.userMessage);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
    // the caller passes the dependencies of its loader
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, attempt]);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);
  return { data, error, loading, reload };
}
