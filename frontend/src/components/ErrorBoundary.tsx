// Global error boundary: a rendering error shows a fallback instead of a blank page.
import { Component, type ErrorInfo, type ReactNode } from 'react';
import { logger } from '../utils/logger';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    logger.error('render error', { message: error.message, stack: info.componentStack });
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="state state--error" role="alert">
          <h1>Something went wrong</h1>
          <p>The page could not be displayed. Reload the page to try again.</p>
          <button type="button" className="button" onClick={() => window.location.reload()}>
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
