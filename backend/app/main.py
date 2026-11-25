"""FastAPI application factory."""

import os

from fastapi import FastAPI

from app.api import health
from app.api.v1 import exercises
from app.core.error_handlers import register_error_handlers
from app.core.logging import RequestLogMiddleware, configure_logging

API_PREFIX = "/api/v1"


def create_app() -> FastAPI:
    configure_logging(os.environ.get("LOG_LEVEL", "INFO"))
    app = FastAPI(
        title="Kinetune API",
        version="0.1.0",
        description="Hybrid recommendation system for adapting group training plans. "
        "Prototype slice: the exercise library (read-only).",
    )
    app.add_middleware(RequestLogMiddleware)
    register_error_handlers(app)
    app.include_router(health.router)
    app.include_router(exercises.router, prefix=API_PREFIX)
    return app


app = create_app()
