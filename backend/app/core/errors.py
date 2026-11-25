"""Application errors raised by the service layer."""


class AppError(Exception):
    """Base class: every subclass maps to one HTTP status and error code."""

    status_code = 500
    code = "internal_error"

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"
