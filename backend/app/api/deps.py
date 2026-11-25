"""Dependency wiring: router -> service -> repository -> session."""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_session
from app.repositories.exercise_repository import SqlAlchemyExerciseRepository
from app.services.exercise_service import ExerciseService

SessionDep = Annotated[AsyncSession, Depends(get_session)]


def get_exercise_service(session: SessionDep) -> ExerciseService:
    return ExerciseService(SqlAlchemyExerciseRepository(session))


ExerciseServiceDep = Annotated[ExerciseService, Depends(get_exercise_service)]
