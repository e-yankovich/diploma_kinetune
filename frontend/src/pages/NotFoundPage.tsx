// Fallback route for unknown URLs.
import { Link } from 'react-router-dom';

export function NotFoundPage() {
  return (
    <div className="state state--empty">
      <h1>Page not found</h1>
      <p>The address does not exist.</p>
      <Link to="/exercises" className="button">
        Open the exercise library
      </Link>
    </div>
  );
}
