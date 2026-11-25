// Controlled filter form with validation. Applies the filters on submit.
import { useState, type FormEvent } from 'react';
import { EXERCISE_MODES, type ExerciseFilters, type ExerciseMode, type Family } from '../types/api';
import { MODE_LABEL } from '../utils/format';
import { SEARCH_MAX, validateSearch } from '../utils/validation';

interface Props {
  value: ExerciseFilters;
  families: Family[];
  onApply: (filters: ExerciseFilters) => void;
  onReset: () => void;
}

export function ExerciseFiltersForm({ value, families, onApply, onReset }: Props) {
  const [draft, setDraft] = useState<ExerciseFilters>(value);
  const [touched, setTouched] = useState(false);
  const searchError = validateSearch(draft.q);

  function submit(event: FormEvent) {
    event.preventDefault();
    setTouched(true);
    if (searchError) return;
    onApply(draft);
  }

  function reset() {
    setTouched(false);
    onReset();
  }

  return (
    <form className="filters" onSubmit={submit} noValidate aria-label="Filter exercises">
      <div className="field">
        <label htmlFor="filter-q">Search by name</label>
        <input
          id="filter-q"
          type="search"
          value={draft.q}
          maxLength={SEARCH_MAX + 1}
          aria-invalid={touched && searchError ? true : undefined}
          aria-describedby={touched && searchError ? 'filter-q-error' : undefined}
          onChange={(e) => setDraft({ ...draft, q: e.target.value })}
        />
        {touched && searchError && (
          <span id="filter-q-error" className="field__error">
            {searchError}
          </span>
        )}
      </div>
      <div className="field">
        <label htmlFor="filter-mode">Mode</label>
        <select
          id="filter-mode"
          value={draft.mode}
          onChange={(e) => setDraft({ ...draft, mode: e.target.value as ExerciseMode | '' })}
        >
          <option value="">Any</option>
          {EXERCISE_MODES.map((mode) => (
            <option key={mode} value={mode}>
              {MODE_LABEL[mode]}
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label htmlFor="filter-difficulty">Difficulty</label>
        <select
          id="filter-difficulty"
          value={draft.difficulty}
          onChange={(e) =>
            setDraft({ ...draft, difficulty: e.target.value ? Number(e.target.value) : '' })
          }
        >
          <option value="">Any</option>
          <option value="1">1 – Easy</option>
          <option value="2">2 – Medium</option>
          <option value="3">3 – Hard</option>
        </select>
      </div>
      <div className="field">
        <label htmlFor="filter-family">Family</label>
        <select
          id="filter-family"
          value={draft.familyId}
          onChange={(e) =>
            setDraft({ ...draft, familyId: e.target.value ? Number(e.target.value) : '' })
          }
        >
          <option value="">Any</option>
          {families.map((family) => (
            <option key={family.id} value={family.id}>
              {family.name} ({family.exercise_count})
            </option>
          ))}
        </select>
      </div>
      <div className="filters__actions">
        <button type="submit" className="button">
          Apply
        </button>
        <button type="button" className="button button--secondary" onClick={reset}>
          Reset
        </button>
      </div>
    </form>
  );
}
