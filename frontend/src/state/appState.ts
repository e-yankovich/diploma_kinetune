// Global state (React Context + useReducer): the library filters, kept when the
// coach opens an exercise and comes back, and the notification (toast) queue.
// A state library (Redux, Zustand) is not needed for two small slices; see
// docs/frontend/architecture.md.
import { createContext, useContext } from 'react';
import type { ExerciseFilters } from '../types/api';

export type ToastKind = 'error' | 'info';

export interface Toast {
  id: number;
  kind: ToastKind;
  message: string;
}

export interface AppState {
  filters: ExerciseFilters;
  toasts: Toast[];
}

export const DEFAULT_FILTERS: ExerciseFilters = {
  q: '',
  mode: '',
  difficulty: '',
  familyId: '',
  sort: 'name',
};

export const INITIAL_STATE: AppState = { filters: DEFAULT_FILTERS, toasts: [] };

export type AppAction =
  | { type: 'setFilters'; filters: ExerciseFilters }
  | { type: 'resetFilters' }
  | { type: 'addToast'; toast: Toast }
  | { type: 'removeToast'; id: number };

export function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'setFilters':
      return { ...state, filters: action.filters };
    case 'resetFilters':
      return { ...state, filters: DEFAULT_FILTERS };
    case 'addToast':
      return { ...state, toasts: [...state.toasts, action.toast] };
    case 'removeToast':
      return { ...state, toasts: state.toasts.filter((t) => t.id !== action.id) };
  }
}

export interface AppContextValue {
  state: AppState;
  setFilters: (filters: ExerciseFilters) => void;
  resetFilters: () => void;
  notify: (message: string, kind?: ToastKind) => void;
  dismiss: (id: number) => void;
}

export const AppContext = createContext<AppContextValue | null>(null);

export function useAppState(): AppContextValue {
  const context = useContext(AppContext);
  if (!context) throw new Error('useAppState must be used inside AppStateProvider');
  return context;
}
