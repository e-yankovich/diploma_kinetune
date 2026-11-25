"""Error response model: every error of the API has this JSON body."""

from pydantic import BaseModel, Field


class ErrorDetail(BaseModel):
    location: str = Field(examples=["query.difficulty"])
    message: str = Field(examples=["Input should be less than or equal to 3"])


class ErrorBody(BaseModel):
    code: str = Field(description="Stable machine-readable code", examples=["not_found"])
    message: str = Field(description="Human-readable message", examples=["Exercise 9999 does not exist"])
    details: list[ErrorDetail] | None = Field(default=None, description="Only for validation_error")
    request_id: str | None = Field(
        default=None, description="Also sent in the X-Request-ID header; quote it when reporting a problem"
    )


class ErrorResponse(BaseModel):
    error: ErrorBody


# reusable "responses" blocks for the OpenAPI description of the routers
NOT_FOUND = {404: {"model": ErrorResponse, "description": "The resource does not exist"}}
VALIDATION = {422: {"model": ErrorResponse, "description": "Invalid path or query parameter"}}
UNAVAILABLE = {503: {"model": ErrorResponse, "description": "The database is not available"}}

# Prototype slice: no authentication yet. Operations are marked public
# explicitly in the specification; coach endpoints will require a bearer token.
PUBLIC = {"security": []}
