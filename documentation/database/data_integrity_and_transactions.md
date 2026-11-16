# Kinetune — Data Integrity and Transactions

DBMS: PostgreSQL 18 · Backend: FastAPI + SQLAlchemy · Migrations: Alembic

Rule IDs (DQ01–DQ27) refer to §6 of the data dictionary.

---

## 1. Principles

1. **The database protects its own data.** Every rule that can be written as a constraint or trigger lives in the database, not only in the API. Bad data is then rejected even if it comes from a bug, a manual SQL session or a seed script.
2. **Defence in depth.** The same rule is often checked twice: in the API first (to give the user a clear message) and in the database (as the final guarantee).
3. **Short transactions.** A transaction contains only database work. Slow external calls (the LLM) are never made while a transaction is open.
4. **All or nothing.** A business operation that touches several rows (e.g. a check-in with its discomfort areas) is one transaction: either all rows are saved or none.

---

## 2. Data integrity

### 2.1 Levels and mechanisms

| Integrity type | What it guarantees | Mechanism in Kinetune | Examples |
|---|---|---|---|
| **Entity** | Every row is uniquely identifiable | `PRIMARY KEY` on every table: identity surrogate keys, or composite keys in junction tables | `exercise.id`; (`exercise_id`, `muscle_id`) in `exercise_muscle` |
| **Domain** | Each value is of the right type and in the allowed range | Data types, `NOT NULL`, `CHECK`, PostgreSQL `ENUM` types | `energy BETWEEN 1 AND 5`; `phase` enum; `email = lower(email)` |
| **Uniqueness** | No duplicates where the business forbids them | `UNIQUE` constraints and unique indexes | `exercise.name`; `session.checkin_token`; (`plan_id`, `phase`, `position`) |
| **Referential** | No reference points to a missing row | `FOREIGN KEY` with an explicit `ON DELETE` rule (`RESTRICT`, `CASCADE`, `SET NULL`) | A check-in cannot reference a non-existent session; deleting a session cascades to its check-ins |
| **Row-level business rules** | Columns of one row agree with each other | Multi-column `CHECK` | `is_warning = (candidate_exercise_id IS NULL)`; `(status = 'open') = (checkin_closed_at IS NULL)` |
| **Cross-table business rules** | Rows in different tables agree | Triggers (`BEFORE INSERT/UPDATE`), which raise an error and roll back the statement | A recommendation's plan item belongs to the session's plan (DQ01) |
| **Library / seed quality** | Reference data is complete and sensible | Check queries run after every import and in tests; the import fails if any returns rows | Every body area has a muscle or joint (DQ10); no progression cycles (DQ12) |

### 2.2 Constraints (declarative)

Declared in `db/01_schema.sql` (later the first Alembic migration); the full list per column is in the data dictionary (§4). Every constraint has an explicit name (`pk_`, `fk_`, `uq_`, `ck_` prefix), so error messages say which rule was broken. Summary (counted in the database catalog after applying the DDL):

| Constraint type | Count (approx.) | Notes |
|---|---|---|
| PRIMARY KEY | 21 | One per table |
| FOREIGN KEY | 28 | Every FK has `ON DELETE` set explicitly (dictionary §5). No FK is left with the implicit default. |
| UNIQUE | 10 | Names, codes, e-mail, check-in token, plan item position, relation edge |
| CHECK | 29 | Ranges (1–5, 1–3, `> 0`), formats (regex on codes), cross-column rules |
| NOT NULL | most columns | NULL is allowed only where "unknown / not applicable" is a real state (e.g. `reps_count` for holds, `participants_present` before class) |

**Deferrable uniqueness.** The constraint UQ (`plan_id`, `phase`, `position`) is declared `DEFERRABLE INITIALLY DEFERRED`. Reordering exercises (swapping positions 2 and 3) would otherwise violate it in the middle of the transaction. With a deferred constraint, uniqueness is checked once, at `COMMIT`.

**Soft delete instead of delete.** Exercises and users are deactivated (`is_active = false`), not deleted, because plans, sessions and recommendations refer to them. `ON DELETE RESTRICT` makes this the only option: an attempt to delete a referenced exercise fails.

### 2.3 Triggers (procedural)

Rules that need data from another table, or from the row's previous state, cannot be written as `CHECK`. They are triggers written in PL/pgSQL (`db/02_triggers.sql`: 14 triggers, plus the helper function `has_role(user_id, role_code)`). Every trigger raises an exception with a clear message and SQLSTATE `P0001` (or `23514` for check-like violations), so the API can map it to an HTTP 409/422 answer.

| Trigger (table, timing) | Rule | DQ |
|---|---|---|
| `trg_checkin_session_open`, `trg_checkin_discomfort_session_open` (BEFORE INSERT) | Accept only while the session is `open`. Takes a `FOR SHARE` lock on the session row (see §3.4). | DQ03 |
| `trg_feedback_session_closed` (`feedback`; BEFORE INSERT) | Accept only when the session is `closed` or `done` | — |
| `trg_session_status` (`session`; BEFORE INSERT/UPDATE) | A new session starts as `open`; only forward transitions open → closed → done. Sets `checkin_closed_at` when the session is closed. | DQ04 |
| `trg_session_owner` (`session`; BEFORE INSERT/UPDATE) | The session's coach owns the plan and holds the `coach` role | DQ08, DQ21 |
| `trg_plan_owner` (`plan`; BEFORE INSERT/UPDATE) | The plan's owner holds the `coach` role | DQ21 |
| `trg_plan_item_side` (`plan_item`; BEFORE INSERT/UPDATE) | A symmetric exercise has `side = 'both'` | DQ25 |
| `trg_plan_set_updated_at` (`plan`; BEFORE UPDATE), `trg_plan_touch_from_item` (`plan_item`; AFTER INSERT/UPDATE/DELETE) | Keep `plan.updated_at` current | — |
| `trg_recommendation_consistency` (`recommendation`; BEFORE INSERT) | The plan item belongs to the session's plan; the candidate differs from the original exercise | DQ01, DQ02 |
| `trg_decision_time` (`recommendation_decision`; BEFORE INSERT) | `decided_at` ≥ the recommendation's `created_at` | DQ07 |
| `trg_last_admin_role` (`user_role`; BEFORE DELETE), `trg_last_admin_deactivate` (`app_user`; BEFORE UPDATE of `is_active`) | The last active admin cannot lose the role or be deactivated | DQ22 |
| `trg_granted_by_admin` (`user_role`; BEFORE INSERT) | `granted_by` (if set) holds the `admin` role | DQ23 |

### 2.4 Application-level validation

The API (Pydantic models) validates every request before it reaches the database: types, ranges, e-mail format, required fields. This gives the user a clear message early. The rules that exist **only** in the application are the ones that depend on a workflow, not on stored data:

- New plan items and candidates use active exercises only (DQ16).
- Recommendations are created only after the check-in is closed (DQ06). This is guaranteed by the order of steps in one transaction (§3.3).
- Positions in a phase are kept continuous (DQ13). The API renumbers them when an item is removed.
- The plan checks BR1–BR8 produce **warnings** for the coach, not errors (thesis 2.5: the coach decides). They are therefore not database constraints.

### 2.5 Check queries

The rules that concern the library as a whole (DQ09–DQ12, DQ14, DQ17, DQ24, DQ26, DQ27) are SQL queries stored in `db/checks/`. Each query returns the rows that **violate** the rule, so an empty result means the rule holds. They run:

- at the end of every library/seed import, **inside the import transaction**: if any error-level check returns rows, the whole import is rolled back (§3.6);
- in the automated tests (CI);
- before the pilot, as part of the release checklist.

Warning-level checks (DQ11, DQ13, DQ15, DQ17) are reported but do not fail the import.

### 2.6 Integrity of personal data

- Passwords are stored only as argon2id hashes (`app_user.password_hash`).
- Participants are anonymous: no table has a column for their name, contact, IP address or device id (DQ20). A test scans column names in `information_schema` for forbidden patterns (`ip`, `phone`, `device`, …).
- Deleting a session deletes all participant data collected for it in one statement (cascade to `checkin`, `checkin_discomfort`, `feedback`, `recommendation`, `recommendation_decision`).

---

## 3. Transactions

### 3.1 General settings

| Setting | Value | Reason |
|---|---|---|
| Isolation level | `READ COMMITTED` (PostgreSQL default) | Enough for this workload. The few places where two users can conflict are protected by explicit row locks or by constraints (§3.4). `SERIALIZABLE` would add retry handling to every request with no benefit at this scale. |
| Transaction scope | One transaction per API request (unit of work). The request handler opens it with `async with db.begin():`. It commits at the end, or rolls back on any exception. | A request is one business operation, so it is atomic |
| Autocommit | Off in the application | Prevents half-finished multi-row writes |
| `statement_timeout` | 5 s for the application role | No runaway query can hold locks for long |
| `idle_in_transaction_session_timeout` | 10 s | A forgotten open transaction cannot block others |
| `lock_timeout` | 2 s | A request waiting for a lock fails fast with a clear error instead of hanging |
| Durability | `synchronous_commit = on` (default) | A committed check-in or decision survives a server crash (WAL) |
| Retries | The API retries a transaction up to 3 times on `40001` (serialization failure) or `40P01` (deadlock) | These errors are safe to retry; any other error is returned to the user |

**Lock order.** Every transaction that locks several rows locks them in the same order: `session` → `plan` → `plan_item` → `recommendation`. This prevents deadlocks.

### 3.2 Key transactions

Each operation below is one transaction (`BEGIN … COMMIT`). If any statement fails, everything is rolled back.

#### T1 — Participant submits a check-in (US3.3)

```sql
BEGIN;
  -- trigger trg_checkin_session_open:
  --   SELECT status FROM session WHERE id = :sid FOR SHARE;  -- must be 'open'
  INSERT INTO checkin (session_id, energy, poor_sleep, language)
  VALUES (:sid, :energy, :poor_sleep, :lang)
  RETURNING id;
  INSERT INTO checkin_discomfort (checkin_id, body_area_id)
  VALUES (:cid, :area1), (:cid, :area2);
COMMIT;
```

- Atomicity: a check-in is never saved without its discomfort areas, or the other way round.
- The session is found by `checkin_token`. An unknown token returns 404 before the transaction starts.

#### T2 — Coach closes the check-in and recommendations are generated (US3.2, US4.1)

```sql
BEGIN;
  UPDATE session
     SET status = 'closed'                 -- trigger sets checkin_closed_at
   WHERE id = :sid AND status = 'open'
  RETURNING id;                            -- 0 rows -> already closed: stop, return current state
  -- read check-in aggregates (now stable: no new check-ins can arrive, §3.4)
  -- run rules BR9–BR11 in the backend, candidate search via WITH RECURSIVE
  INSERT INTO recommendation (...) VALUES (...), (...);  -- template explanations
COMMIT;
```

- **Idempotent.** The `WHERE status = 'open'` condition makes a second click (or a second browser tab) a no-op: it updates 0 rows and the API returns the existing recommendations.
- **Consistent snapshot.** Recommendations are calculated from exactly the set of check-ins that existed when the status changed.
- **The LLM is not called here.** Every recommendation is first saved with its template explanation (`explanation_source = 'template'`), so the coach always gets a complete, rule-based result (NFR9).

#### T3 — LLM enrichment (after T2, optional)

After T2 commits, the backend asks the LLM for better explanations, with a 5 s timeout. For each successful answer:

```sql
BEGIN;
  UPDATE recommendation
     SET explanation = :llm_text, explanation_source = 'llm'
   WHERE id = :rid
     AND NOT EXISTS (SELECT 1 FROM recommendation_decision d WHERE d.recommendation_id = :rid);
COMMIT;
```

- The LLM call (up to 5 s) happens **outside** any transaction, so it never holds locks.
- If the LLM fails or times out, nothing is written and the template explanation stays. Failure needs no rollback, because nothing was started.
- The explanation is not changed after the coach has decided, so the decision always refers to the text the coach saw.

#### T4 — Coach accepts or declines a recommendation (US5.1)

```sql
BEGIN;
  INSERT INTO recommendation_decision (recommendation_id, decision)
  VALUES (:rid, :decision)
  ON CONFLICT (recommendation_id) DO NOTHING
  RETURNING recommendation_id;             -- 0 rows -> already decided: return 409
COMMIT;
```

- The primary key on `recommendation_id` guarantees at most one decision, even if two requests arrive at the same moment.
- Once a session-level plan copy exists (open decision in the dictionary, §7), accepting a replacement will also update that copy **in the same transaction**. Then the decision and the plan change are always saved together.

#### T5 — Coach saves a plan (US2.1, US2.2)

```sql
BEGIN;
  UPDATE plan SET title = :title, notes = :notes
   WHERE id = :pid AND updated_at = :version     -- optimistic lock
  RETURNING id;                                  -- 0 rows -> 409 "plan changed elsewhere"
  DELETE FROM plan_item WHERE plan_id = :pid AND id <> ALL(:kept_ids);
  UPDATE plan_item SET position = ..., ... WHERE id = ...;   -- deferred UNIQUE allows swaps
  INSERT INTO plan_item (...) VALUES (...);
COMMIT;   -- deferred UNIQUE (plan_id, phase, position) checked here
```

- **Optimistic locking.** The client sends the `updated_at` value it loaded. If the plan was saved meanwhile (e.g. in another tab), the update matches 0 rows and the coach is asked to reload, so no change is silently overwritten.
- The BR1–BR8 check runs in the API before `COMMIT` and returns warnings with the saved plan.
- Deleting a plan item that is referenced by a past recommendation fails (`RESTRICT`), and the whole save is rolled back. This limitation is listed in the dictionary, §7.

#### T6 — Coach enters attendance after class (US3.5)

```sql
UPDATE session SET participants_present = :n, status = 'done'
 WHERE id = :sid AND status = 'closed';
```

This is a single statement and therefore atomic by itself. The CHECK constraint ensures `participants_present` is not NULL when the status becomes `done` (DQ05).

#### T7 — Admin revokes a role or deactivates a user

```sql
BEGIN;
  -- trg_last_admin_role:
  --   SELECT ... FROM user_role ur JOIN role r ON r.id = ur.role_id
  --    WHERE r.code = 'admin' FOR UPDATE;       -- lock all admin assignments
  --   if this is the last active admin -> RAISE EXCEPTION
  DELETE FROM user_role WHERE user_id = :uid AND role_id = :admin_role;
COMMIT;
```

The trigger also fires on cascaded deletes, so deleting the last admin's account is blocked as well. The `FOR UPDATE` lock on all admin rows makes two simultaneous revocations wait for each other. Without the lock, two admins could each remove the other and leave no admin (DQ22).

### 3.3 Order of operations inside T2

DQ06 ("recommendations only after the check-in is closed") is not a trigger, because the guarantee comes from the order of steps inside T2. The status change is the first statement, and recommendations are inserted after it, in the same transaction. If inserting a recommendation fails, the status change is rolled back too, and the session stays `open`.

### 3.4 Concurrency scenarios

| Scenario | Risk | How it is prevented |
|---|---|---|
| A participant submits a check-in at the moment the coach closes it | Under READ COMMITTED, the check-in trigger could read `open` just before T2 commits. The check-in would then be saved but missed by the recommendations. | The trigger reads the session with `FOR SHARE`, and T2's `UPDATE` needs an exclusive row lock, so the two wait for each other. If the check-in comes first, T2 waits and then sees it. If T2 comes first, the trigger waits, then reads `closed` and rejects the check-in. |
| The coach clicks "Close check-in" twice | Duplicate recommendations | `UPDATE … WHERE status = 'open'` changes the row only once (T2) |
| Two decisions for one recommendation | Conflicting decisions; wrong K3 | Primary key on `recommendation_decision.recommendation_id` + `ON CONFLICT DO NOTHING` (T4) |
| The plan is edited in two tabs | Lost update | Optimistic lock on `plan.updated_at` (T5) |
| Two admins revoke each other's admin role | No admin left | `FOR UPDATE` on admin rows in `trg_last_admin_role` (T7) |
| An LLM answer arrives after the coach has decided | The explanation changes under a decision | `NOT EXISTS` decision condition in T3 |
| The KPI report is read while check-ins are being written | Inconsistent numbers | Each report query is a single statement, and PostgreSQL gives every statement a consistent snapshot (MVCC). Readers never block writers. |

### 3.5 Error handling

| SQLSTATE | Cause | API response |
|---|---|---|
| `23505` unique_violation | Duplicate name, e-mail, position | 409 Conflict, naming the field |
| `23503` foreign_key_violation | Deleting a referenced row (`RESTRICT`) or referencing a missing one | 409 Conflict ("in use") / 422 |
| `23514` check_violation, `23502` not_null_violation | Invalid value | 422 Unprocessable Entity |
| `P0001` raised by a trigger | Business rule broken (e.g. check-in after close) | 409 Conflict with the trigger's message |
| `40001`, `40P01` | Serialization failure, deadlock | Retried automatically (up to 3 times), then 503 |
| `55P03` lock_not_available | `lock_timeout` reached | 503, "please try again" |
| `57014` query_canceled | `statement_timeout` reached | 503 |

In every case the transaction is rolled back completely; the API never commits a partial result.

### 3.6 Bulk operations: library import and migrations

**Library import** (seed CSV → `exercise`, `exercise_muscle`, `exercise_joint`, `exercise_relation`):

```text
BEGIN;
  load CSV rows (COPY)  ->  insert into library tables
  run error-level check queries (DQ09, DQ10, DQ12, DQ14, DQ26, DQ27)
  any violation -> ROLLBACK (the library stays as it was) and print the failing rows
COMMIT;
```

The import is all or nothing, so a half-loaded library can never be used by the recommendation engine.

**Schema migrations.** PostgreSQL supports transactional DDL, so Alembic runs each migration in a transaction. A migration that fails halfway (e.g. a new CHECK that existing data violates) is rolled back completely, and the schema stays at the previous version. The current version is stored in `alembic_version`.

---
