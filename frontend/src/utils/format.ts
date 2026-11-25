// Display labels for API codes (one place, no magic strings in components).
import type { ExerciseMode, LoadLevel, StartingPose, VariationLevel } from '../types/api';

export function humanize(code: string): string {
  const text = code.replace(/_/g, ' ');
  return text.charAt(0).toUpperCase() + text.slice(1);
}

export const MODE_LABEL: Record<ExerciseMode, string> = {
  dynamic: 'Dynamic',
  static: 'Static',
  stato_dynamic: 'Stato-dynamic',
};

export function poseLabel(pose: StartingPose): string {
  return humanize(pose);
}

export const LOAD_LABEL: Record<LoadLevel, string> = { low: 'Low', medium: 'Medium', high: 'High' };

export const LEVEL_LABEL: Record<VariationLevel, string> = {
  same_level: 'Same level',
  easier: 'Easier',
  harder: 'Harder',
};

export const DIFFICULTY_LABEL: Record<number, string> = { 1: 'Easy', 2: 'Medium', 3: 'Hard' };
