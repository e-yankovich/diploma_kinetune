// Small labelled values (difficulty, load level, variation level).
import type { LoadLevel, VariationLevel } from '../types/api';
import { DIFFICULTY_LABEL, LEVEL_LABEL, LOAD_LABEL } from '../utils/format';

export function DifficultyBadge({ value }: { value: number }) {
  return (
    <span className={`badge badge--difficulty-${value}`}>{DIFFICULTY_LABEL[value] ?? value}</span>
  );
}

export function LoadBadge({ value }: { value: LoadLevel }) {
  return <span className={`badge badge--load-${value}`}>{LOAD_LABEL[value]}</span>;
}

export function LevelBadge({ value }: { value: VariationLevel }) {
  return <span className={`badge badge--level-${value}`}>{LEVEL_LABEL[value]}</span>;
}
