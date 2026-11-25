// Data interfaces of the Kinetune API (docs/api/reference/data-models.md).

export type ExerciseMode = 'dynamic' | 'static' | 'stato_dynamic';
export type StartingPose =
  | 'seated'
  | 'standing'
  | 'balance'
  | 'quadruped'
  | 'downward_dog'
  | 'supine'
  | 'prone'
  | 'kneeling'
  | 'front_split';
export type LoadLevel = 'low' | 'medium' | 'high';
export type VariationLevel = 'same_level' | 'easier' | 'harder';
export type ExerciseSort = 'name' | 'difficulty';

export const EXERCISE_MODES: readonly ExerciseMode[] = ['dynamic', 'static', 'stato_dynamic'];
export const STARTING_POSES: readonly StartingPose[] = [
  'seated',
  'standing',
  'balance',
  'quadruped',
  'downward_dog',
  'supine',
  'prone',
  'kneeling',
  'front_split',
];

export interface ExerciseRef {
  id: number;
  name: string;
  difficulty: number;
}

export interface ExerciseSummary extends ExerciseRef {
  mode: ExerciseMode;
  starting_pose: StartingPose;
  is_symmetric: boolean;
  rep_duration_sec: number;
  is_active: boolean;
  families: string[];
}

export interface JointLoad {
  joint: string;
  is_primary: boolean;
  load_level: LoadLevel;
}

export interface MuscleRef {
  muscle: string;
  is_primary: boolean;
}

export interface Variation extends ExerciseRef {
  level: VariationLevel;
}

export interface ExerciseDetail extends ExerciseSummary {
  description: string | null;
  joints: JointLoad[];
  muscles: MuscleRef[];
  compensations: ExerciseRef[];
  variations: Variation[];
  regressions: ExerciseRef[];
  progressions: ExerciseRef[];
}

export interface Family {
  id: number;
  name: string;
  exercise_count: number;
}

export interface ExerciseFilters {
  q: string;
  mode: ExerciseMode | '';
  difficulty: number | '';
  familyId: number | '';
  sort: ExerciseSort;
}

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    details?: { location: string; message: string }[];
    request_id?: string | null;
  };
}
