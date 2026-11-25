"""Shared fixtures: the app wired to the fake repository (no database needed)."""
import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_exercise_service
from app.db.session import get_session
from app.main import create_app
from app.services.exercise_service import ExerciseService
from tests.fakes import FakeExerciseRepository, ankle_library


class FakeSession:
    """Stands in for AsyncSession in the health check."""

    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    async def execute(self, _statement):
        if self.error:
            raise self.error
        return None


@pytest.fixture
def repository() -> FakeExerciseRepository:
    return ankle_library()


@pytest.fixture
def app(repository):
    application = create_app()
    application.dependency_overrides[get_exercise_service] = lambda: ExerciseService(repository)
    application.dependency_overrides[get_session] = lambda: FakeSession()
    return application


@pytest.fixture
def client(app) -> TestClient:
    # raise_server_exceptions=False: unhandled errors are returned as 500 like in production
    return TestClient(app, raise_server_exceptions=False)
