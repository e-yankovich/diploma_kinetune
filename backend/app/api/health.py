"""Health check used by Docker and the deployment (checks the database connection)."""

from fastapi import APIRouter
from sqlalchemy import text

from app.api.deps import SessionDep
from app.schemas.errors import PUBLIC, UNAVAILABLE

router = APIRouter(tags=["Health"], responses=UNAVAILABLE)


@router.get("/health", summary="Service and database status", openapi_extra=PUBLIC)
async def health(session: SessionDep) -> dict[str, str]:
    await session.execute(text("SELECT 1"))
    return {"status": "ok"}
