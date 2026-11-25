// Data hooks of the exercise library pages.
import { getExercise, listExercises, listFamilies } from '../api/exercises';
import type { ExerciseDetail, ExerciseFilters, ExerciseSummary, Family } from '../types/api';
import { useAsync, type AsyncState } from './useAsync';

export function useExercises(filters: ExerciseFilters): AsyncState<ExerciseSummary[]> {
  return useAsync(() => listExercises(filters), [JSON.stringify(filters)]);
}

export function useExercise(id: number): AsyncState<ExerciseDetail> {
  return useAsync(() => getExercise(id), [id]);
}

export function useFamilies(): AsyncState<Family[]> {
  return useAsync(listFamilies, []);
}
