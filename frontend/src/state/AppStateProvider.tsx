// Provider of the global state (see appState.ts).
import { useCallback, useMemo, useReducer, type ReactNode } from 'react';
import type { ExerciseFilters } from '../types/api';
import { AppContext, appReducer, INITIAL_STATE, type ToastKind } from './appState';

const TOAST_LIFETIME_MS = 6000;
let nextToastId = 1;

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(appReducer, INITIAL_STATE);

  const dismiss = useCallback((id: number) => dispatch({ type: 'removeToast', id }), []);
  const notify = useCallback(
    (message: string, kind: ToastKind = 'error') => {
      const toast = { id: nextToastId++, kind, message };
      dispatch({ type: 'addToast', toast });
      window.setTimeout(() => dismiss(toast.id), TOAST_LIFETIME_MS);
    },
    [dismiss],
  );
  const setFilters = useCallback(
    (filters: ExerciseFilters) => dispatch({ type: 'setFilters', filters }),
    [],
  );
  const resetFilters = useCallback(() => dispatch({ type: 'resetFilters' }), []);

  const value = useMemo(
    () => ({ state, setFilters, resetFilters, notify, dismiss }),
    [state, setFilters, resetFilters, notify, dismiss],
  );
  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}
