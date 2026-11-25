// /families — the movement families; a click opens the filtered library.
import { useNavigate } from 'react-router-dom';
import { SkeletonRows } from '../components/Skeleton';
import { StateMessage } from '../components/StateMessage';
import { useFamilies } from '../hooks/useLibrary';
import { DEFAULT_FILTERS, useAppState } from '../state/appState';

export function FamiliesPage() {
  const { data, error, loading, reload } = useFamilies();
  const { setFilters } = useAppState();
  const navigate = useNavigate();

  function openFamily(familyId: number) {
    setFilters({ ...DEFAULT_FILTERS, familyId });
    navigate('/exercises');
  }

  return (
    <>
      <h1>Exercise families</h1>
      <p className="muted">
        Exercises of one family are variations of each other: another execution of the same
        movement.
      </p>
      {loading && <SkeletonRows rows={8} />}
      {!loading && error && (
        <StateMessage
          kind="error"
          title="The families could not be loaded"
          message={error.userMessage}
          onRetry={reload}
        />
      )}
      {!loading && data && (
        <ul className="family-grid">
          {data.map((family) => (
            <li key={family.id}>
              <button type="button" className="family-card" onClick={() => openFamily(family.id)}>
                <span className="family-card__name">{family.name}</span>
                <span className="family-card__count">
                  {family.exercise_count} exercise{family.exercise_count === 1 ? '' : 's'}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
