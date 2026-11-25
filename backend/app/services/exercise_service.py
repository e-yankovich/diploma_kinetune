"""Business logic of the exercise library (read side)."""

from app.core.errors import NotFoundError
from app.models.library import Exercise
from app.repositories.exercise_repository import ExerciseFilter, ExerciseRepository
from app.schemas.exercise import (
    ExerciseDetail,
    ExerciseRef,
    ExerciseSummary,
    FamilyOut,
    JointLoad,
    MuscleRef,
    Variation,
    VariationLevel,
)


def _summary_fields(ex: Exercise) -> dict:
    return {
        "id": ex.id,
        "name": ex.name,
        "mode": ex.mode,
        "starting_pose": ex.starting_pose,
        "difficulty": ex.difficulty,
        "is_symmetric": ex.is_symmetric,
        "rep_duration_sec": ex.rep_duration_sec,
        "is_active": ex.is_active,
        "families": sorted(f.name for f in ex.families),
    }


def classify_variations(
    variations: list[Exercise], regressions: list[Exercise], progressions: list[Exercise]
) -> list[Variation]:
    """Level of each variation: one pair can be in both graphs (shared family + progression).

    easier  = also a regression ("a gentler version of the same stretch")
    harder  = also a progression (a candidate search never offers these)
    same    = no progression in either direction
    """
    easier = {e.id for e in regressions}
    harder = {e.id for e in progressions}
    result = []
    for ex in variations:
        if ex.id in easier:
            level = VariationLevel.EASIER
        elif ex.id in harder:
            level = VariationLevel.HARDER
        else:
            level = VariationLevel.SAME
        result.append(Variation(id=ex.id, name=ex.name, difficulty=ex.difficulty, level=level))
    return result


class ExerciseService:
    def __init__(self, repository: ExerciseRepository) -> None:
        self._repo = repository

    async def list_exercises(self, flt: ExerciseFilter) -> list[ExerciseSummary]:
        exercises = await self._repo.list_exercises(flt)
        return [ExerciseSummary(**_summary_fields(ex)) for ex in exercises]

    async def get_exercise(self, exercise_id: int) -> ExerciseDetail:
        ex = await self._repo.get_exercise(exercise_id)
        if ex is None:
            raise NotFoundError(f"Exercise {exercise_id} does not exist")
        variations = await self._repo.list_variations(exercise_id)
        regressions = await self._repo.list_regressions(exercise_id)
        progressions = await self._repo.list_progressions(exercise_id)
        return ExerciseDetail(
            **_summary_fields(ex),
            description=ex.description,
            # main joints/muscles first, then by name
            joints=[
                JointLoad(joint=j.joint.name, is_primary=j.is_primary, load_level=j.load_level)
                for j in sorted(ex.joints, key=lambda j: (not j.is_primary, j.joint.name))
            ],
            muscles=[
                MuscleRef(muscle=m.muscle.name, is_primary=m.is_primary)
                for m in sorted(ex.muscles, key=lambda m: (not m.is_primary, m.muscle.name))
            ],
            compensations=[
                ExerciseRef.model_validate(c) for c in sorted(ex.compensations, key=lambda c: c.name)
            ],
            variations=classify_variations(variations, regressions, progressions),
            regressions=[ExerciseRef.model_validate(e) for e in regressions],
            progressions=[ExerciseRef.model_validate(e) for e in progressions],
        )

    async def list_families(self) -> list[FamilyOut]:
        return [
            FamilyOut(id=f.id, name=f.name, exercise_count=f.exercise_count)
            for f in await self._repo.list_families()
        ]
