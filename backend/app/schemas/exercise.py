"""API data models (Pydantic) of the exercise library. Enumerations are defined once, here."""

from enum import StrEnum

from pydantic import BaseModel, ConfigDict


class ExerciseMode(StrEnum):
    DYNAMIC = "dynamic"
    STATIC = "static"
    STATO_DYNAMIC = "stato_dynamic"


class StartingPose(StrEnum):
    SEATED = "seated"
    STANDING = "standing"
    BALANCE = "balance"
    QUADRUPED = "quadruped"
    DOWNWARD_DOG = "downward_dog"
    SUPINE = "supine"
    PRONE = "prone"
    KNEELING = "kneeling"
    FRONT_SPLIT = "front_split"


class LoadLevel(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class ExerciseSort(StrEnum):
    NAME = "name"
    DIFFICULTY = "difficulty"


class VariationLevel(StrEnum):
    """Level of a variation compared with the exercise (business rules v2, two graphs)."""

    SAME = "same_level"  # shares a family, no progression in either direction
    EASIER = "easier"  # shares a family and is also a regression ("a gentler version")
    HARDER = "harder"  # shares a family and is also a progression


class _Orm(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ExerciseRef(_Orm):
    id: int
    name: str
    difficulty: int


class ExerciseSummary(_Orm):
    id: int
    name: str
    mode: ExerciseMode
    starting_pose: StartingPose
    difficulty: int
    is_symmetric: bool
    rep_duration_sec: int
    is_active: bool
    families: list[str]


class JointLoad(BaseModel):
    joint: str
    is_primary: bool
    load_level: LoadLevel


class MuscleRef(BaseModel):
    muscle: str
    is_primary: bool


class Variation(ExerciseRef):
    level: VariationLevel


class ExerciseDetail(ExerciseSummary):
    description: str | None
    joints: list[JointLoad]
    muscles: list[MuscleRef]
    compensations: list[ExerciseRef]
    variations: list[Variation]
    regressions: list[ExerciseRef]
    progressions: list[ExerciseRef]


class FamilyOut(BaseModel):
    id: int
    name: str
    exercise_count: int
