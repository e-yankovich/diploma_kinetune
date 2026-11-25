// Notification area (toasts) fed by the global state.
import { useAppState } from '../state/appState';

export function Toasts() {
  const { state, dismiss } = useAppState();
  return (
    <div className="toasts" aria-live="polite">
      {state.toasts.map((toast) => (
        <div key={toast.id} className={`toast toast--${toast.kind}`} role="status">
          <span>{toast.message}</span>
          <button
            type="button"
            className="toast__close"
            aria-label="Dismiss notification"
            onClick={() => dismiss(toast.id)}
          >
            ×
          </button>
        </div>
      ))}
    </div>
  );
}
