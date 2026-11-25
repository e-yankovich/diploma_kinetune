// List of linked exercises (compensations, regressions, progressions, variations).
import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import type { ExerciseRef } from '../types/api';

interface Props<T extends ExerciseRef> {
  title: string;
  items: T[];
  emptyText: string;
  extra?: (item: T) => ReactNode;
}

export function ExerciseRefList<T extends ExerciseRef>({
  title,
  items,
  emptyText,
  extra,
}: Props<T>) {
  return (
    <section className="card">
      <h2 className="card__title">
        {title} <span className="count">({items.length})</span>
      </h2>
      {items.length === 0 ? (
        <p className="muted">{emptyText}</p>
      ) : (
        <ul className="ref-list">
          {items.map((item) => (
            <li key={item.id} className="ref-list__item">
              <Link to={`/exercises/${item.id}`}>{item.name}</Link>
              {extra?.(item)}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
