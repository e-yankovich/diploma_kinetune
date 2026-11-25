"""API integration tests: router + validation + service + error handlers (fake repository)."""
from sqlalchemy.exc import OperationalError

from app.db.session import get_session
from tests.conftest import FakeSession


class TestListExercises:
    def test_returns_exercises(self, client):
        response = client.get("/api/v1/exercises")
        assert response.status_code == 200
        assert [e["name"] for e in response.json()][:2] == ["Ankle Circles – Standing", "Ankle Circles – Seated"]

    def test_query_parameters_reach_the_service(self, client, repository):
        client.get("/api/v1/exercises?q=ankle&mode=static&difficulty=2&family_id=1&sort=difficulty&include_inactive=true")
        flt = repository.last_filter
        assert (flt.q, flt.mode, flt.difficulty, flt.family_id, flt.sort, flt.active_only) == (
            "ankle", "static", 2, 1, "difficulty", False,
        )

    def test_defaults(self, client, repository):
        client.get("/api/v1/exercises")
        assert repository.last_filter.active_only is True and repository.last_filter.sort == "name"

    def test_invalid_difficulty_gives_422_with_details(self, client):
        response = client.get("/api/v1/exercises?difficulty=7")
        assert response.status_code == 422
        error = response.json()["error"]
        assert error["code"] == "validation_error"
        assert error["details"][0]["location"] == "query.difficulty"

    def test_unknown_mode_gives_422(self, client):
        assert client.get("/api/v1/exercises?mode=yoga").status_code == 422

    def test_too_short_search_gives_422(self, client):
        assert client.get("/api/v1/exercises?q=a").json()["error"]["details"][0]["location"] == "query.q"


class TestGetExercise:
    def test_returns_the_detail(self, client):
        body = client.get("/api/v1/exercises/1").json()
        assert body["name"] == "Ankle Circles – Standing"
        assert body["variations"][0]["level"] == "easier"
        assert body["joints"] == [{"joint": "ankle", "is_primary": True, "load_level": "medium"}]

    def test_unknown_id_gives_404_error_body(self, client):
        response = client.get("/api/v1/exercises/9999")
        assert response.status_code == 404
        assert response.json()["error"] == {
            "code": "not_found",
            "message": "Exercise 9999 does not exist",
            "request_id": response.headers["X-Request-ID"],
        }

    def test_non_positive_id_gives_422(self, client):
        assert client.get("/api/v1/exercises/0").status_code == 422

    def test_non_numeric_id_gives_422(self, client):
        assert client.get("/api/v1/exercises/abc").status_code == 422


def test_families(client):
    response = client.get("/api/v1/families")
    assert response.status_code == 200
    assert response.json()[0] == {"id": 1, "name": "ankle mobility", "exercise_count": 13}


class TestHealth:
    def test_ok(self, client):
        assert client.get("/health").json() == {"status": "ok"}

    def test_database_down_gives_503(self, app, client):
        app.dependency_overrides[get_session] = lambda: FakeSession(OperationalError("SELECT 1", {}, Exception("down")))
        response = client.get("/health")
        assert response.status_code == 503
        assert response.json()["error"]["code"] == "service_unavailable"


class TestErrorHandling:
    def test_unhandled_error_gives_generic_500(self, app, client):
        app.dependency_overrides[get_session] = lambda: FakeSession(RuntimeError("secret detail"))
        response = client.get("/health")
        assert response.status_code == 500
        assert response.json()["error"]["message"] == "Internal server error"
        assert "secret" not in response.text

    def test_unknown_route_gives_404_json(self, client):
        response = client.get("/api/v1/nothing")
        assert response.status_code == 404 and response.json()["error"]["code"] == "not_found"

    def test_wrong_method_gives_405(self, client):
        assert client.post("/api/v1/exercises").status_code == 405

    def test_request_id_is_echoed(self, client):
        response = client.get("/health", headers={"X-Request-ID": "abc-123"})
        assert response.headers["X-Request-ID"] == "abc-123"

    def test_request_id_is_generated(self, client):
        assert len(client.get("/health").headers["X-Request-ID"]) == 32


def test_openapi_documents_the_error_model(client):
    spec = client.get("/openapi.json").json()
    responses = spec["paths"]["/api/v1/exercises/{exercise_id}"]["get"]["responses"]
    assert {"200", "404", "422", "503"} <= set(responses)
    assert "ErrorResponse" in spec["components"]["schemas"]
