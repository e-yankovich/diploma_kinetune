# Reference: errors

## Structure

Every error response — whatever the endpoint — has the same JSON body and a matching HTTP status:

```json
{
  "error": {
    "code": "validation_error",
    "message": "Invalid request",
    "details": [
      {"location": "query.difficulty", "message": "Input should be less than or equal to 3"}
    ],
    "request_id": "61ecd5d3813c4f9e836c74afa28c7f23"
  }
}
```

| Field | Always | Description |
|---|---|---|
| `code` | yes | Stable machine-readable code (use this in clients) |
| `message` | yes | Human-readable text (may change) |
| `details` | only for `validation_error` | One entry per invalid field: `location` (`query.x`, `path.x`) and `message` |
| `request_id` | yes | Same value as the `X-Request-ID` response header; quote it when reporting a problem |

The API never returns `200` for an error, and never returns stack traces or SQL to the client; details are logged on the server.

## Codes

| HTTP | `code` | Cause | Recovery |
|---|---|---|---|
| 404 | `not_found` | The resource does not exist, or the URL is unknown | Check the id or path; reload lists |
| 405 | `http_error` | Method not allowed (e.g. `POST /api/v1/exercises`) | Use the documented method |
| 422 | `validation_error` | A path or query parameter is missing, of the wrong type or out of range | Fix the parameter named in `details[].location` |
| 500 | `internal_error` | Unexpected server error | Retry later; report with `request_id` |
| 503 | `service_unavailable` | The database is not available | Retry after a few seconds (safe: all endpoints are read-only) |

Planned with authentication: `401 unauthorized` (no or invalid token), `403 forbidden` (not the owner), `429 rate_limited` (per coach account).
