"""Global error handling: every error is returned as JSON with a proper HTTP status.

Body: {"error": {"code": "...", "message": "...", "details": [...]?, "request_id": "..."}}
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import OperationalError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.errors import AppError

logger = logging.getLogger("kinetune.errors")


def _body(request: Request, code: str, message: str, details: list | None = None) -> dict:
    error: dict = {"code": code, "message": message}
    if details:
        error["details"] = details
    error["request_id"] = getattr(request.state, "request_id", None)
    return {"error": error}


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content=_body(request, exc.code, exc.message))


async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    details = [
        {"location": ".".join(str(p) for p in err["loc"]), "message": err["msg"]} for err in exc.errors()
    ]
    return JSONResponse(
        status_code=422, content=_body(request, "validation_error", "Invalid request", details)
    )


async def http_error_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = "not_found" if exc.status_code == 404 else "http_error"
    return JSONResponse(status_code=exc.status_code, content=_body(request, code, str(exc.detail)))


async def database_unavailable_handler(request: Request, exc: OperationalError) -> JSONResponse:
    logger.error("database unavailable", exc_info=exc)
    return JSONResponse(
        status_code=503, content=_body(request, "service_unavailable", "The database is not available")
    )


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    # details go to the log only; the client gets a generic message
    logger.error("unhandled error", exc_info=exc)
    return JSONResponse(status_code=500, content=_body(request, "internal_error", "Internal server error"))


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(RequestValidationError, validation_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_error_handler)
    app.add_exception_handler(OperationalError, database_unavailable_handler)
    app.add_exception_handler(Exception, unhandled_error_handler)
