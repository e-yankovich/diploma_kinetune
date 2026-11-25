// Exercise list as a table (cards on small screens) with sortable columns.
import { Link } from 'react-router-dom';
import type { ExerciseSort, ExerciseSummary } from '../types/api';
import { MODE_LABEL, poseLabel } from '../utils/format';
import { DifficultyBadge } from './Badge';

interface Props {
  exercises: ExerciseSummary[];
  sort: ExerciseSort;
  onSort: (sort: ExerciseSort) => void;
}

function SortButton({
  column,
  label,
  sort,
  onSort,
}: { column: ExerciseSort; label: string } & Omit<Props, 'exercises'>) {
  const active = sort === column;
  return (
    <button
      type="button"
      className={active ? 'sort sort--active' : 'sort'}
      aria-pressed={active}
      onClick={() => onSort(column)}
    >
      {label}
      {active && <span aria-hidden="true"> ▲</span>}
    </button>
  );
}

export function ExerciseTable({ exercises, sort, onSort }: Props) {
  return (
    <div className="table-wrap">
      <table className="table">
        <caption className="visually-hidden">Exercises, sorted by {sort}</caption>
        <thead>
          <tr>
            <th scope="col" aria-sort={sort === 'name' ? 'ascending' : 'none'}>
              <SortButton column="name" label="Name" sort={sort} onSort={onSort} />
            </th>
            <th scope="col">Mode</th>
            <th scope="col">Starting pose</th>
            <th scope="col" aria-sort={sort === 'difficulty' ? 'ascending' : 'none'}>
              <SortButton column="difficulty" label="Difficulty" sort={sort} onSort={onSort} />
            </th>
            <th scope="col">Families</th>
          </tr>
        </thead>
        <tbody>
          {exercises.map((ex) => (
            <tr key={ex.id}>
              <td data-label="Name">
                <Link to={`/exercises/${ex.id}`} className="table__link">
                  {ex.name}
                </Link>
              </td>
              <td data-label="Mode">{MODE_LABEL[ex.mode]}</td>
              <td data-label="Starting pose">{poseLabel(ex.starting_pose)}</td>
              <td data-label="Difficulty">
                <DifficultyBadge value={ex.difficulty} />
              </td>
              <td data-label="Families">{ex.families.join(', ') || '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
