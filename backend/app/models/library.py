"""ORM models of the exercise library (read by the API; written only by the library import)."""

from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, SmallInteger, String, Table, Text
from sqlalchemy.dialects.postgresql import ENUM
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import SCHEMA, Base

# PostgreSQL enum types created by migration 0001 (create_type=False: never created here)
EXERCISE_MODE = ENUM(
    "dynamic", "static", "stato_dynamic", name="exercise_mode", schema=SCHEMA, create_type=False
)
STARTING_POSE = ENUM(
    "seated",
    "standing",
    "balance",
    "quadruped",
    "downward_dog",
    "supine",
    "prone",
    "kneeling",
    "front_split",
    name="starting_pose",
    schema=SCHEMA,
    create_type=False,
)
LOAD_LEVEL = ENUM("low", "medium", "high", name="load_level", schema=SCHEMA, create_type=False)
RELATION_TYPE = ENUM("progression", name="relation_type", schema=SCHEMA, create_type=False)

exercise_family_member = Table(
    "exercise_family_member",
    Base.metadata,
    Column("exercise_id", Integer, ForeignKey(f"{SCHEMA}.exercise.id"), primary_key=True),
    Column("family_id", SmallInteger, ForeignKey(f"{SCHEMA}.exercise_family.id"), primary_key=True),
)

exercise_compensation = Table(
    "exercise_compensation",
    Base.metadata,
    Column("exercise_id", Integer, ForeignKey(f"{SCHEMA}.exercise.id"), primary_key=True),
    Column("compensation_exercise_id", Integer, ForeignKey(f"{SCHEMA}.exercise.id"), primary_key=True),
)


class Joint(Base):
    __tablename__ = "joint"

    id: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    name: Mapped[str] = mapped_column(String(64))


class Muscle(Base):
    __tablename__ = "muscle"

    id: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    name: Mapped[str] = mapped_column(String(64))


class ExerciseFamily(Base):
    __tablename__ = "exercise_family"

    id: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    name: Mapped[str] = mapped_column(String(64))


class ExerciseJoint(Base):
    __tablename__ = "exercise_joint"

    exercise_id: Mapped[int] = mapped_column(ForeignKey(f"{SCHEMA}.exercise.id"), primary_key=True)
    joint_id: Mapped[int] = mapped_column(ForeignKey(f"{SCHEMA}.joint.id"), primary_key=True)
    is_primary: Mapped[bool] = mapped_column(Boolean)
    load_level: Mapped[str] = mapped_column(LOAD_LEVEL)

    joint: Mapped[Joint] = relationship(lazy="joined")


class ExerciseMuscle(Base):
    __tablename__ = "exercise_muscle"

    exercise_id: Mapped[int] = mapped_column(ForeignKey(f"{SCHEMA}.exercise.id"), primary_key=True)
    muscle_id: Mapped[int] = mapped_column(ForeignKey(f"{SCHEMA}.muscle.id"), primary_key=True)
    is_primary: Mapped[bool] = mapped_column(Boolean)

    muscle: Mapped[Muscle] = relationship(lazy="joined")


class Exercise(Base):
    __tablename__ = "exercise"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text)
    mode: Mapped[str] = mapped_column(EXERCISE_MODE)
    starting_pose: Mapped[str] = mapped_column(STARTING_POSE)
    is_symmetric: Mapped[bool] = mapped_column(Boolean)
    difficulty: Mapped[int] = mapped_column(SmallInteger)
    rep_duration_sec: Mapped[int] = mapped_column(SmallInteger)
    is_active: Mapped[bool] = mapped_column(Boolean)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # loaded explicitly with selectinload() where needed (no lazy loading in async code)
    families: Mapped[list[ExerciseFamily]] = relationship(secondary=exercise_family_member, lazy="raise")
    joints: Mapped[list[ExerciseJoint]] = relationship(lazy="raise")
    muscles: Mapped[list[ExerciseMuscle]] = relationship(lazy="raise")
    compensations: Mapped[list["Exercise"]] = relationship(
        secondary=exercise_compensation,
        primaryjoin=lambda: Exercise.id == exercise_compensation.c.exercise_id,
        secondaryjoin=lambda: Exercise.id == exercise_compensation.c.compensation_exercise_id,
        lazy="raise",
    )


class ExerciseRelation(Base):
    """Progression graph: from = easier, to = harder (variations are family membership, not edges)."""

    __tablename__ = "exercise_relation"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    from_exercise_id: Mapped[int] = mapped_column(ForeignKey(f"{SCHEMA}.exercise.id"))
    to_exercise_id: Mapped[int] = mapped_column(ForeignKey(f"{SCHEMA}.exercise.id"))
    type: Mapped[str] = mapped_column(RELATION_TYPE)
    is_manual: Mapped[bool] = mapped_column(Boolean)
