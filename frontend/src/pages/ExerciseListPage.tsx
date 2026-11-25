// /exercises — the library list with filters and sorting.
import { ExerciseFiltersForm } from '../components/ExerciseFilters';
import { ExerciseTable } from '../components/ExerciseTable';
import { SkeletonRows } from '../components/Skeleton';
import { StateMessage } from '../components/StateMessage';
import { useExercises, useFamilies } from '../hooks/useLibrary';
import { useAppState } from '../state/appState';
import type { ExerciseSort } from '../types/api';

export function ExerciseListPage() {
  const { state, setFilters, resetFilters } = useAppState();
  const { filters } = state;
  const exercises = useExercises(filters);
  const families = useFamilies();

  function changeSort(sort: ExerciseSort) {
    setFilters({ ...filters, sort });
  }

  return (
    <>
      <h1>Exercise library</h1>
      <ExerciseFiltersForm
        key={JSON.stringify(filters)}
        value={filters}
        families={families.data ?? []}
        onApply={setFilters}
        onReset={resetFilters}
      />
      {exercises.loading && <SkeletonRows />}
      {!exercises.loading && exercises.error && (
        <StateMessage
          kind="error"
          title="The exercises could not be loaded"
          message={exercises.error.userMessage}
          onRetry={exercises.reload}
        />
      )}
      {!exercises.loading && exercises.data && exercises.data.length === 0 && (
        <StateMessage
          title="No exercises match the filters"
          message="Change or reset the filters."
        />
      )}
      {!exercises.loading && exercises.data && exercises.data.length > 0 && (
        <>
          <p className="muted" aria-live="polite">
            {exercises.data.length} exercise{exercises.data.length === 1 ? '' : 's'}
          </p>
          <ExerciseTable exercises={exercises.data} sort={filters.sort} onSort={changeSort} />
        </>
      )}
    </>
  );
}
