// /exercises/:id — one exercise: joints with load, muscles, compensations, graphs.
import { Link, useParams } from 'react-router-dom';
import { DifficultyBadge, LevelBadge, LoadBadge } from '../components/Badge';
import { ExerciseRefList } from '../components/ExerciseRefList';
import { SkeletonCard } from '../components/Skeleton';
import { StateMessage } from '../components/StateMessage';
import { useExercise } from '../hooks/useLibrary';
import { MODE_LABEL, poseLabel } from '../utils/format';

export function ExerciseDetailPage() {
  const { id } = useParams();
  const exerciseId = Number(id);
  const valid = Number.isInteger(exerciseId) && exerciseId > 0;
  // invalid ids are not sent to the API (it would answer 422)
  const { data, error, loading, reload } = useExercise(valid ? exerciseId : -1);

  if (!valid || error?.status === 404 || error?.status === 422) {
    return (
      <StateMessage title="Exercise not found" message={`There is no exercise with id "${id}".`} />
    );
  }
  if (loading) return <SkeletonCard />;
  if (error || !data) {
    return (
      <StateMessage
        kind="error"
        title="The exercise could not be loaded"
        message={error?.userMessage}
        onRetry={reload}
      />
    );
  }

  return (
    <article className="detail">
      <p>
        <Link to="/exercises" className="back-link">
          ← Back to the library
        </Link>
      </p>
      <h1>{data.name}</h1>
      {!data.is_active && (
        <p className="notice">This exercise is inactive: it is not offered as a candidate.</p>
      )}
      <dl className="facts">
        <div>
          <dt>Mode</dt>
          <dd>{MODE_LABEL[data.mode]}</dd>
        </div>
        <div>
          <dt>Starting pose</dt>
          <dd>{poseLabel(data.starting_pose)}</dd>
        </div>
        <div>
          <dt>Difficulty</dt>
          <dd>
            <DifficultyBadge value={data.difficulty} />
          </dd>
        </div>
        <div>
          <dt>Sides</dt>
          <dd>{data.is_symmetric ? 'Both at once' : 'One side, then the other'}</dd>
        </div>
        <div>
          <dt>One repetition</dt>
          <dd>{data.rep_duration_sec} s</dd>
        </div>
        <div>
          <dt>Families</dt>
          <dd>{data.families.join(', ') || '—'}</dd>
        </div>
      </dl>
      {data.description && <p className="description">{data.description}</p>}

      <div className="grid">
        <section className="card">
          <h2 className="card__title">Joints</h2>
          <ul className="ref-list">
            {data.joints.map((j) => (
              <li key={j.joint} className="ref-list__item">
                <span>
                  {j.joint}
                  {j.is_primary && <span className="tag">main</span>}
                </span>
                <LoadBadge value={j.load_level} />
              </li>
            ))}
          </ul>
        </section>
        <section className="card">
          <h2 className="card__title">Muscles</h2>
          {data.muscles.length === 0 ? (
            <p className="muted">No muscles (relaxation exercise).</p>
          ) : (
            <ul className="ref-list">
              {data.muscles.map((m) => (
                <li key={m.muscle} className="ref-list__item">
                  <span>
                    {m.muscle}
                    {m.is_primary && <span className="tag">stretched</span>}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
        <ExerciseRefList
          title="Variations"
          items={data.variations}
          emptyText="No other exercise shares a family with this one."
          extra={(v) => <LevelBadge value={v.level} />}
        />
        <ExerciseRefList
          title="Regressions (easier)"
          items={data.regressions}
          emptyText="No easier version."
        />
        <ExerciseRefList
          title="Progressions (harder)"
          items={data.progressions}
          emptyText="No harder version."
        />
        <ExerciseRefList
          title="Compensating exercises"
          items={data.compensations}
          emptyText="No compensation needed."
        />
      </div>
    </article>
  );
}
