// Exercise library service: one function per API endpoint.
import type { ExerciseDetail, ExerciseFilters, ExerciseSummary, Family } from '../types/api';
import { apiGet } from './client';

export function listExercises(filters: ExerciseFilters): Promise<ExerciseSummary[]> {
  return apiGet<ExerciseSummary[]>('/exercises', {
    q: filters.q.trim(),
    mode: filters.mode,
    difficulty: filters.difficulty,
    family_id: filters.familyId,
    sort: filters.sort,
  });
}

export function getExercise(id: number): Promise<ExerciseDetail> {
  return apiGet<ExerciseDetail>(`/exercises/${id}`);
}

export function listFamilies(): Promise<Family[]> {
  return apiGet<Family[]>('/families');
}
