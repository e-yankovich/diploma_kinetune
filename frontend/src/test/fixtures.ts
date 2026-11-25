// API data taken from the real library (docs/api/reference/exercises.md).
import type { ExerciseDetail, ExerciseSummary, Family } from '../types/api';

export const exercises: ExerciseSummary[] = [
  {
    id: 2,
    name: 'Ankle Circles – Seated',
    mode: 'dynamic',
    starting_pose: 'seated',
    difficulty: 1,
    is_symmetric: true,
    rep_duration_sec: 2,
    is_active: true,
    families: ['ankle mobility'],
  },
  {
    id: 1,
    name: 'Ankle Circles – Standing',
    mode: 'dynamic',
    starting_pose: 'balance',
    difficulty: 1,
    is_symmetric: false,
    rep_duration_sec: 2,
    is_active: true,
    families: ['ankle mobility'],
  },
];

export const families: Family[] = [
  { id: 1, name: 'ankle mobility', exercise_count: 13 },
  { id: 2, name: 'hip mobility', exercise_count: 1 },
];

export const detail: ExerciseDetail = {
  ...exercises[1],
  description: 'Rotation of foot in circular motions from the ankle joint standing on one leg.',
  joints: [{ joint: 'ankle', is_primary: true, load_level: 'medium' }],
  muscles: [{ muscle: 'calves', is_primary: true }],
  compensations: [],
  variations: [
    { id: 2, name: 'Ankle Circles – Seated', difficulty: 1, level: 'easier' },
    { id: 4, name: 'Ankle Flexion and Extension – Standing', difficulty: 1, level: 'same_level' },
  ],
  regressions: [{ id: 2, name: 'Ankle Circles – Seated', difficulty: 1 }],
  progressions: [],
};
