"""Exercise library endpoints (US1.2). Read-only; the library is loaded by the import script."""

from typing import Annotated

from fastapi import APIRouter, Path, Query

from app.api.deps import ExerciseServiceDep
from app.repositories.exercise_repository import ExerciseFilter
from app.schemas.exercise import (
    ExerciseDetail,
    ExerciseMode,
    ExerciseSort,
    ExerciseSummary,
    FamilyOut,
    StartingPose,
)

router = APIRouter(tags=["Exercise library"])


@router.get("/exercises", response_model=list[ExerciseSummary], summary="List exercises")
async def list_exercises(
    service: ExerciseServiceDep,
    q: Annotated[str | None, Query(min_length=2, max_length=100, description="Part of the name")] = None,
    mode: ExerciseMode | None = None,
    starting_pose: StartingPose | None = None,
    difficulty: Annotated[int | None, Query(ge=1, le=3)] = None,
    family_id: Annotated[int | None, Query(gt=0)] = None,
    include_inactive: bool = False,
    sort: ExerciseSort = ExerciseSort.NAME,
) -> list[ExerciseSummary]:
    flt = ExerciseFilter(
        q=q,
        mode=mode,
        starting_pose=starting_pose,
        difficulty=difficulty,
        family_id=family_id,
        active_only=not include_inactive,
        sort=sort,
    )
    return await service.list_exercises(flt)


@router.get("/exercises/{exercise_id}", response_model=ExerciseDetail, summary="Get one exercise")
async def get_exercise(
    service: ExerciseServiceDep, exercise_id: Annotated[int, Path(gt=0)]
) -> ExerciseDetail:
    return await service.get_exercise(exercise_id)


@router.get("/families", response_model=list[FamilyOut], summary="List exercise families")
async def list_families(service: ExerciseServiceDep) -> list[FamilyOut]:
    return await service.list_families()
