# Getting started

This guide starts the Kinetune stack locally and makes the first API calls. Time: about 10 minutes.

## 1. Requirements

- Docker with Docker Compose v2
- `curl` (or any HTTP client)

## 2. Start the stack

From the repository root:

```bash
cp .env.example .env                       # set real passwords
docker compose up -d --build               # database, migrations, backend, frontend
docker compose --profile import run --rm import-library    # load the exercise library
```

Check that the backend is up:

```bash
curl -s http://localhost:8000/health
```

```json
{"status": "ok"}
```

If you get `503` with `"code": "service_unavailable"`, the database is not ready yet: wait a few seconds and try again (`docker compose ps` shows the state of each service).

## 3. First request: list exercises

```bash
curl -s "http://localhost:8000/api/v1/exercises?difficulty=1&sort=name"
```

```json
[
  {
    "id": 2,
    "name": "Ankle Circles – Seated",
    "mode": "dynamic",
    "starting_pose": "seated",
    "difficulty": 1,
    "is_symmetric": true,
    "rep_duration_sec": 2,
    "is_active": true,
    "families": ["ankle mobility"]
  }
]
```

(The response is shortened; the real list has every matching exercise.)

## 4. Open one exercise

```bash
curl -s http://localhost:8000/api/v1/exercises/1
```

The response contains the joints with their load level, the muscles, the compensating exercises and the two exercise graphs: `variations` (exercises of the same family, each with a `level`), `regressions` (one step easier) and `progressions` (one step harder). Full example: [reference](../reference/exercises.md#get-apiv1exercisesexercise_id).

## 5. Handle errors

Every error has the same JSON body:

```bash
curl -s "http://localhost:8000/api/v1/exercises?mode=yoga"
```

```json
{
  "error": {
    "code": "validation_error",
    "message": "Invalid request",
    "details": [
      {"location": "query.mode", "message": "Input should be 'dynamic', 'static' or 'stato_dynamic'"}
    ],
    "request_id": "9fabc97b5ec041278a3007b83b8490a9"
  }
}
```

Read `error.code` in your client, not the message text. All codes: [errors](../reference/errors.md).

## Security note

- The prototype slice has **no authentication**: the exercise library is reference data with no personal data. The specification marks these operations as public (`security: []`).
- **Do not expose the prototype on a public network.** The Compose stack binds the ports to `127.0.0.1` only.
- Planned: coach endpoints will require a bearer token (`Authorization: Bearer <JWT>`), obtained by logging in; passwords are stored only as argon2id hashes. Participant check-ins stay anonymous: no account, no IP address stored or logged.
- Never put tokens or passwords into URLs, logs or the repository.

## Next steps

- [Tutorial: find a gentler exercise](tutorial-find-a-gentler-exercise.md)
- [Endpoint reference](../reference/exercises.md)
