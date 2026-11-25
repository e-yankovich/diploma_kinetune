// Empty and error states with an optional retry button.
interface Props {
  title: string;
  message?: string;
  onRetry?: () => void;
  kind?: 'empty' | 'error';
}

export function StateMessage({ title, message, onRetry, kind = 'empty' }: Props) {
  return (
    <div className={`state state--${kind}`} role={kind === 'error' ? 'alert' : undefined}>
      <h2>{title}</h2>
      {message && <p>{message}</p>}
      {onRetry && (
        <button type="button" className="button" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  );
}
