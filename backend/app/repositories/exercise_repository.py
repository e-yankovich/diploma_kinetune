"""Data access for the exercise library.

The service depends on the ExerciseRepository protocol (dependency inversion);
SqlAlchemyExerciseRepository is the PostgreSQL implementation, and the unit
tests use an in-memory fake.
"""

from dataclasses import dataclass
from typing import Protocol

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.library import (
    Exercise,
    ExerciseFamily,
    ExerciseJoint,
    ExerciseMuscle,
    ExerciseRelation,
    exercise_family_member,
)
from app.schemas.exercise import ExerciseMode, ExerciseSort, StartingPose


@dataclass(frozen=True)
class ExerciseFilter:
    q: str | None = None
    mode: ExerciseMode | None = None
    starting_pose: StartingPose | None = None
    difficulty: int | None = None
    family_id: int | None = None
    active_only: bool = True
    sort: ExerciseSort = ExerciseSort.NAME


@dataclass(frozen=True)
class FamilyCount:
    id: int
    name: str
    exercise_count: int


class ExerciseRepository(Protocol):
    async def list_exercises(self, flt: ExerciseFilter) -> list[Exercise]: ...
    async def get_exercise(self, exercise_id: int) -> Exercise | None: ...
    async def list_variations(self, exercise_id: int) -> list[Exercise]: ...
    async def list_regressions(self, exercise_id: int) -> list[Exercise]: ...
    async def list_progressions(self, exercise_id: int) -> list[Exercise]: ...
    async def list_families(self) -> list[FamilyCount]: ...


class SqlAlchemyExerciseRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def list_exercises(self, flt: ExerciseFilter) -> list[Exercise]:
        stmt = select(Exercise).options(selectinload(Exercise.families))
        if flt.q:
            stmt = stmt.where(Exercise.name.ilike(f"%{flt.q}%"))  # bound parameter, no SQL injection
        if flt.mode:
            stmt = stmt.where(Exercise.mode == flt.mode.value)
        if flt.starting_pose:
            stmt = stmt.where(Exercise.starting_pose == flt.starting_pose.value)
        if flt.difficulty:
            stmt = stmt.where(Exercise.difficulty == flt.difficulty)
        if flt.family_id:
            stmt = stmt.where(
                Exercise.id.in_(
                    select(exercise_family_member.c.exercise_id).where(
                        exercise_family_member.c.family_id == flt.family_id
                    )
                )
            )
        if flt.active_only:
            stmt = stmt.where(Exercise.is_active)
        order = (
            (Exercise.difficulty, Exercise.name) if flt.sort == ExerciseSort.DIFFICULTY else (Exercise.name,)
        )
        result = await self._session.scalars(stmt.order_by(*order))
        return list(result)

    async def get_exercise(self, exercise_id: int) -> Exercise | None:
        stmt = (
            select(Exercise)
            .where(Exercise.id == exercise_id)
            .options(
                selectinload(Exercise.families),
                selectinload(Exercise.joints).joinedload(ExerciseJoint.joint),
                selectinload(Exercise.muscles).joinedload(ExerciseMuscle.muscle),
                selectinload(Exercise.compensations),
            )
        )
        return await self._session.scalar(stmt)

    async def list_variations(self, exercise_id: int) -> list[Exercise]:
        """Members of the exercise's families (one hop through the family; star storage)."""
        own = exercise_family_member.alias("own")
        other = exercise_family_member.alias("other")
        stmt = (
            select(Exercise)
            .join(other, other.c.exercise_id == Exercise.id)
            .join(own, own.c.family_id == other.c.family_id)
            .where(own.c.exercise_id == exercise_id, Exercise.id != exercise_id)
            .distinct()
            .order_by(Exercise.name)
        )
        return list(await self._session.scalars(stmt))

    async def list_regressions(self, exercise_id: int) -> list[Exercise]:
        """One step easier: progression edges followed backwards."""
        stmt = (
            select(Exercise)
            .join(ExerciseRelation, ExerciseRelation.from_exercise_id == Exercise.id)
            .where(ExerciseRelation.to_exercise_id == exercise_id)
            .order_by(Exercise.name)
        )
        return list(await self._session.scalars(stmt))

    async def list_progressions(self, exercise_id: int) -> list[Exercise]:
        """One step harder: progression edges followed forwards."""
        stmt = (
            select(Exercise)
            .join(ExerciseRelation, ExerciseRelation.to_exercise_id == Exercise.id)
            .where(ExerciseRelation.from_exercise_id == exercise_id)
            .order_by(Exercise.name)
        )
        return list(await self._session.scalars(stmt))

    async def list_families(self) -> list[FamilyCount]:
        stmt = (
            select(ExerciseFamily.id, ExerciseFamily.name, func.count(exercise_family_member.c.exercise_id))
            .join(
                exercise_family_member, exercise_family_member.c.family_id == ExerciseFamily.id, isouter=True
            )
            .group_by(ExerciseFamily.id, ExerciseFamily.name)
            .order_by(ExerciseFamily.name)
        )
        rows = await self._session.execute(stmt)
        return [FamilyCount(id=r[0], name=r[1], exercise_count=r[2]) for r in rows]
