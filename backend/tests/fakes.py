"""Test doubles: in-memory objects shaped like the ORM models and a fake repository."""
from dataclasses import dataclass, field
from types import SimpleNamespace

from app.repositories.exercise_repository import ExerciseFilter, FamilyCount


def make_exercise(
    id: int,
    name: str,
    *,
    difficulty: int = 1,
    mode: str = "dynamic",
    pose: str = "seated",
    families: tuple[str, ...] = (),
    joints: tuple[tuple[str, bool, str], ...] = (),
    muscles: tuple[tuple[str, bool], ...] = (),
    compensations: tuple = (),
    active: bool = True,
    description: str | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=id,
        name=name,
        description=description,
        mode=mode,
        starting_pose=pose,
        is_symmetric=True,
        difficulty=difficulty,
        rep_duration_sec=4,
        is_active=active,
        families=[SimpleNamespace(name=f) for f in families],
        joints=[
            SimpleNamespace(joint=SimpleNamespace(name=j), is_primary=p, load_level=load) for j, p, load in joints
        ],
        muscles=[SimpleNamespace(muscle=SimpleNamespace(name=m), is_primary=p) for m, p in muscles],
        compensations=list(compensations),
    )


@dataclass
class FakeExerciseRepository:
    exercises: dict[int, SimpleNamespace] = field(default_factory=dict)
    variations: dict[int, list] = field(default_factory=dict)
    regressions: dict[int, list] = field(default_factory=dict)
    progressions: dict[int, list] = field(default_factory=dict)
    families: list[FamilyCount] = field(default_factory=list)
    last_filter: ExerciseFilter | None = None

    async def list_exercises(self, flt: ExerciseFilter) -> list:
        self.last_filter = flt
        return list(self.exercises.values())

    async def get_exercise(self, exercise_id: int):
        return self.exercises.get(exercise_id)

    async def list_variations(self, exercise_id: int) -> list:
        return self.variations.get(exercise_id, [])

    async def list_regressions(self, exercise_id: int) -> list:
        return self.regressions.get(exercise_id, [])

    async def list_progressions(self, exercise_id: int) -> list:
        return self.progressions.get(exercise_id, [])

    async def list_families(self) -> list[FamilyCount]:
        return self.families


def ankle_library() -> FakeExerciseRepository:
    """Small library taken from the real 'ankle mobility' family."""
    standing = make_exercise(
        1,
        "Ankle Circles – Standing",
        pose="balance",
        families=("ankle mobility",),
        joints=(("ankle", True, "medium"),),
        muscles=(("shin", True), ("calves", True), ("sole of foot", False)),
        description="Rotation of the foot, standing on one leg.",
    )
    seated = make_exercise(2, "Ankle Circles – Seated", families=("ankle mobility",), joints=(("ankle", True, "low"),))
    flexion = make_exercise(
        4,
        "Ankle Flexion and Extension – Standing",
        pose="standing",
        families=("toe mobility", "ankle mobility"),
        joints=(("foot", False, "medium"), ("ankle", True, "medium")),
    )
    child = make_exercise(90, "Child's Pose – Static", mode="static", families=("relaxation",))
    standing.compensations = [child]
    return FakeExerciseRepository(
        exercises={1: standing, 2: seated, 4: flexion},
        variations={1: [seated, flexion]},
        regressions={1: [seated]},
        progressions={2: [standing]},
        families=[FamilyCount(1, "ankle mobility", 13), FamilyCount(2, "toe mobility", 2)],
    )
