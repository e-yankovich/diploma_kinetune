# Reference: health

## GET /health

Checks that the service runs and can reach the database. Used by the Docker healthcheck. Not versioned (outside `/api/v1`).

```bash
curl -s -i http://localhost:8000/health
```

| Code | Body | Meaning |
|---|---|---|
| 200 | `{"status": "ok"}` | Service and database are up |
| 503 | `{"error": {"code": "service_unavailable", ...}}` | The database cannot be reached |
