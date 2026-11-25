"""Unit tests of settings, JSON logging and error classes."""
import json
import logging

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import AppError, NotFoundError
from app.core.logging import JsonFormatter


class TestSettings:
    def test_reads_environment_and_escapes_the_password(self, monkeypatch):
        monkeypatch.setenv("DB_HOST", "db")
        monkeypatch.setenv("DB_NAME", "kinetune")
        monkeypatch.setenv("DB_USER", "kinetune_api")
        monkeypatch.setenv("DB_PASSWORD", "p@ss/word")
        url = Settings().database_url
        assert url.host == "db" and url.port == 5432 and url.password == "p@ss/word"
        assert "p%40ss%2Fword" in url.render_as_string(hide_password=False)

    def test_missing_database_settings_fail_fast(self, monkeypatch):
        for name in ("DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"):
            monkeypatch.delenv(name, raising=False)
        with pytest.raises(ValidationError):
            Settings()


class TestJsonFormatter:
    def make_record(self, **extra) -> logging.LogRecord:
        record = logging.makeLogRecord({"name": "kinetune.test", "levelname": "INFO", "msg": "request"})
        for key, value in extra.items():
            setattr(record, key, value)
        return record

    def test_outputs_one_json_object_with_extra_fields(self):
        line = JsonFormatter().format(self.make_record(status=200, path="/health"))
        entry = json.loads(line)
        assert entry["message"] == "request" and entry["level"] == "INFO"
        assert entry["status"] == 200 and entry["path"] == "/health"
        assert "time" in entry

    def test_includes_the_exception(self):
        try:
            raise ValueError("boom")
        except ValueError:
            import sys

            record = self.make_record()
            record.exc_info = sys.exc_info()
        entry = json.loads(JsonFormatter().format(record))
        assert "ValueError: boom" in entry["exception"]


def test_error_classes_carry_status_and_code():
    assert (NotFoundError("x").status_code, NotFoundError("x").code) == (404, "not_found")
    assert (AppError("x").status_code, AppError("x").message) == (500, "x")
