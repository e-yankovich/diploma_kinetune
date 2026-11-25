"""Unit tests of ExerciseService and the variation classification (no database)."""
import asyncio

import pytest

from app.core.errors import NotFoundError
from app.repositories.exercise_repository import ExerciseFilter
from app.schemas.exercise import ExerciseMode, VariationLevel
from app.services.exercise_service import ExerciseService, classify_variations
from tests.fakes import FakeExerciseRepository, ankle_library, make_exercise


def run(coro):
    return asyncio.run(coro)


class TestClassifyVariations:
    def test_variation_that_is_also_a_regression_is_easier(self):
        a = make_exercise(2, "A")
        assert classify_variations([a], regressions=[a], progressions=[])[0].level == VariationLevel.EASIER

    def test_variation_that_is_also_a_progression_is_harder(self):
        a = make_exercise(3, "A", difficulty=3)
        assert classify_variations([a], regressions=[], progressions=[a])[0].level == VariationLevel.HARDER

    def test_variation_without_progression_is_same_level(self):
        a = make_exercise(4, "A")
        assert classify_variations([a], [], [])[0].level == VariationLevel.SAME

    def test_no_variations_gives_empty_list(self):
        assert classify_variations([], [make_exercise(1, "X")], []) == []

    def test_keeps_the_order_and_fields_of_the_variations(self):
        a, b = make_exercise(5, "B", difficulty=2), make_exercise(6, "C")
        result = classify_variations([a, b], [], [])
        assert [(v.id, v.name, v.difficulty) for v in result] == [(5, "B", 2), (6, "C", 1)]


class TestGetExercise:
    def test_unknown_id_raises_not_found(self):
        service = ExerciseService(FakeExerciseRepository())
        with pytest.raises(NotFoundError, match="Exercise 99 does not exist"):
            run(service.get_exercise(99))

    def test_detail_contains_the_graphs(self):
        detail = run(ExerciseService(ankle_library()).get_exercise(1))
        assert [(v.name, v.level) for v in detail.variations] == [
            ("Ankle Circles – Seated", VariationLevel.EASIER),
            ("Ankle Flexion and Extension – Standing", VariationLevel.SAME),
        ]
        assert [r.id for r in detail.regressions] == [2]
        assert detail.progressions == []
        assert [c.name for c in detail.compensations] == ["Child's Pose – Static"]

    def test_main_joints_and_muscles_come_first_then_by_name(self):
        detail = run(ExerciseService(ankle_library()).get_exercise(4))
        assert [(j.joint, j.is_primary) for j in detail.joints] == [("ankle", True), ("foot", False)]
        standing = run(ExerciseService(ankle_library()).get_exercise(1))
        assert [m.muscle for m in standing.muscles] == ["calves", "shin", "sole of foot"]

    def test_families_are_sorted(self):
        detail = run(ExerciseService(ankle_library()).get_exercise(4))
        assert detail.families == ["ankle mobility", "toe mobility"]

    def test_exercise_without_joints_or_muscles(self):
        repo = FakeExerciseRepository(exercises={7: make_exercise(7, "Rest")})
        detail = run(ExerciseService(repo).get_exercise(7))
        assert detail.joints == [] and detail.muscles == [] and detail.variations == []


class TestListExercises:
    def test_passes_the_filter_to_the_repository(self):
        repo = ankle_library()
        flt = ExerciseFilter(q="ankle", mode=ExerciseMode.DYNAMIC, difficulty=1)
        run(ExerciseService(repo).list_exercises(flt))
        assert repo.last_filter == flt

    def test_maps_exercises_to_summaries(self):
        result = run(ExerciseService(ankle_library()).list_exercises(ExerciseFilter()))
        assert [e.id for e in result] == [1, 2, 4]
        assert result[0].starting_pose == "balance"
        assert result[2].families == ["ankle mobility", "toe mobility"]

    def test_empty_library(self):
        assert run(ExerciseService(FakeExerciseRepository()).list_exercises(ExerciseFilter())) == []


def test_list_families():
    families = run(ExerciseService(ankle_library()).list_families())
    assert [(f.name, f.exercise_count) for f in families] == [("ankle mobility", 13), ("toe mobility", 2)]
