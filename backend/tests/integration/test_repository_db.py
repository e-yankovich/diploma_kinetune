"""Repository tests against a real PostgreSQL database with the imported library.

Skipped unless TEST_DATABASE=1 and the DB_* variables point to a database
migrated to 0004 with the library imported (see docs/testing.md).
"""
import asyncio
import os

import pytest

from app.repositories.exercise_repository import ExerciseFilter, SqlAlchemyExerciseRepository
from app.schemas.exercise import ExerciseMode, ExerciseSort

pytestmark = pytest.mark.skipif(os.environ.get("TEST_DATABASE") != "1", reason="needs a database (TEST_DATABASE=1)")


def with_repository(test):
    async def runner():
        from app.db.session import get_engine, get_session_factory

        async with get_session_factory()() as session:
            result = await test(SqlAlchemyExerciseRepository(session))
        await get_engine().dispose()
        return result

    return asyncio.run(runner())


def test_filters_and_sorting():
    async def test(repo):
        static_hard = await repo.list_exercises(ExerciseFilter(mode=ExerciseMode.STATIC, difficulty=3))
        assert static_hard and all(e.mode == "static" and e.difficulty == 3 for e in static_hard)
        by_difficulty = await repo.list_exercises(ExerciseFilter(sort=ExerciseSort.DIFFICULTY))
        assert [e.difficulty for e in by_difficulty] == sorted(e.difficulty for e in by_difficulty)
        found = await repo.list_exercises(ExerciseFilter(q="ankle circles"))
        assert {e.name for e in found} >= {"Ankle Circles – Standing", "Ankle Circles – Seated"}

    with_repository(test)


def test_family_filter_and_counts():
    async def test(repo):
        families = await repo.list_families()
        ankle = next(f for f in families if f.name == "ankle mobility")
        members = await repo.list_exercises(ExerciseFilter(family_id=ankle.id, active_only=False))
        assert len(members) == ankle.exercise_count

    with_repository(test)


def test_graphs_of_ankle_circles_standing():
    async def test(repo):
        [standing] = await repo.list_exercises(ExerciseFilter(q="Ankle Circles – Standing"))
        detail = await repo.get_exercise(standing.id)
        assert {j.joint.name for j in detail.joints} == {"ankle"}
        variations = {e.name for e in await repo.list_variations(standing.id)}
        regressions = {e.name for e in await repo.list_regressions(standing.id)}
        assert "Ankle Circles – Seated" in variations & regressions      # in both graphs
        assert standing.name not in variations
        assert await repo.get_exercise(10**6) is None

    with_repository(test)
