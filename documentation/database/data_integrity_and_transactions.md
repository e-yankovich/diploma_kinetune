# Kinetune — Data Integrity and Transactions

DBMS: PostgreSQL 18 · Backend: FastAPI + SQLAlchemy · Migrations: Alembic

Rule IDs (DQ01–DQ33) refer to §6 of the data dictionary.

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

Declared in `db/01_schema.sql` (migration 0001) and changed by later migrations (`05_password_policy.sql`, `06_plan_and_session_model.sql`); the full list per column is in the data dictionary (§4). Every constraint has an explicit name (`pk_`, `fk_`, `uq_`, `ck_` prefix), so error messages say which rule was broken. Summary (counted in the database catalog at migration 0005):

| Constraint type | Count (approx.) | Notes |
|---|---|---|
| PRIMARY KEY | 21 | One per table |
| FOREIGN KEY | 28 | Every FK has `ON DELETE` set explicitly (dictionary §5). No FK is left with the implicit default. |
| UNIQUE | 10 | Names, codes, e-mail, check-in token, plan item position, relation edge |
| CHECK | 31 | Ranges (1–5, 1–3, `> 0`, 15–120 min), formats (regex on codes, argon2id hash), cross-column rules |
| NOT NULL | most columns | NULL is allowed only where "unknown / not applicable" is a real state (e.g. `participants_present` before class, `target_duration_min` of a draft plan) |

**Deferrable uniqueness.** The constraint UQ (`plan_id`, `phase`, `position`) is declared `DEFERRABLE INITIALLY DEFERRED`. Reordering exercises (swapping positions 2 and 3) would otherwise violate it in the middle of the transaction. With a deferred constraint, uniqueness is checked once, at `COMMIT`.

**Soft delete instead of delete.** Exercises and users are deactivated (`is_active = false`), not deleted, because plans, sessions and recommendations refer to them. `ON DELETE RESTRICT` makes this the only option: an attempt to delete a referenced exercise fails.

### 2.3 Triggers (procedural)

Rules that need data from another table, or from the row's previous state, cannot be written as `CHECK`. They are triggers written in PL/pgSQL (`db/02_triggers.sql`: 14 triggers, plus the helper function `has_role(user_id, role_code)`; `db/06_plan_and_session_model.sql`: 4 more triggers and a new version of `fn_session_status`; 18 triggers in total). Every trigger raises an exception with a clear message and SQLSTATE `P0001` (or `23514` for check-like violations), so the API can map it to an HTTP 409/422 answer.

| Trigger (table, timing) | Rule | DQ |
|---|---|---|
| `trg_checkin_session_open`, `trg_checkin_discomfort_session_open` (BEFORE INSERT) | Accept only while the session is `open`. Takes a `FOR SHARE` lock on the session row (see §3.4). | DQ03 |
| `trg_feedback_session_closed` (`feedback`; BEFORE INSERT) | Accept only when the session is `closed` or `done` | — |
| `trg_session_status` (`session`; BEFORE INSERT/UPDATE) | A new session starts as `open`; only forward transitions open → closed → reviewed → done. `reviewed` only when every recommendation of the session has a decision. Sets `checkin_closed_at` when the session is closed. | DQ04, DQ32 |
| `trg_session_plan_reviewed` (`session`; BEFORE INSERT/UPDATE of `plan_id`) | A session is created only from a `reviewed` plan. Locks the plan row `FOR SHARE` (§3.4). | DQ30 |
| `trg_session_owner` (`session`; BEFORE INSERT/UPDATE) | The session's coach owns the plan and holds the `coach` role | DQ08, DQ21 |
| `trg_plan_owner` (`plan`; BEFORE INSERT/UPDATE) | The plan's owner holds the `coach` role | DQ21 |
| `trg_plan_status` (`plan`; BEFORE INSERT/UPDATE of `status`, `target_duration_min`) | A new plan starts as `draft`; draft → completed → reviewed, or back to `draft`; a changed target moves a completed/reviewed plan back to `draft`; a locked plan keeps its status and target | DQ29, DQ31 |
| `trg_plan_item_guard` (`plan_item`; BEFORE INSERT/UPDATE/DELETE) | Rejects any item change of a locked plan; otherwise moves a completed/reviewed plan back to `draft`. Locks the plan row `FOR UPDATE` (§3.4). | DQ29, DQ31 |
| `trg_plan_item_side` (`plan_item`; BEFORE INSERT/UPDATE) | A symmetric exercise has `side = 'both'` | DQ25 |
| `trg_plan_set_updated_at` (`plan`; BEFORE UPDATE), `trg_plan_touch_from_item` (`plan_item`; AFTER INSERT/UPDATE/DELETE) | Keep `plan.updated_at` current | — |
| `trg_recommendation_consistency` (`recommendation`; BEFORE INSERT) | The plan item belongs to the session's plan; the candidate differs from the original exercise | DQ01, DQ02 |
| `trg_decision_time` (`recommendation_decision`; BEFORE INSERT) | `decided_at` ≥ the recommendation's `created_at` | DQ07 |
| `trg_decision_single_replacement` (`recommendation_decision`; BEFORE INSERT/UPDATE) | At most one accepted replacement per plan item and session. Locks the plan item row (§3.4). | DQ33 |
| `trg_last_admin_role` (`user_role`; BEFORE DELETE), `trg_last_admin_deactivate` (`app_user`; BEFORE UPDATE of `is_active`) | The last active admin cannot lose the role or be deactivated | DQ22 |
| `trg_granted_by_admin` (`user_role`; BEFORE INSERT) | `granted_by` (if set) holds the `admin` role | DQ23 |

### 2.4 Application-level validation

The API (Pydantic models) validates every request before it reaches the database: types, ranges, e-mail format, required fields. This gives the user a clear message early. The rules that exist **only** in the application are the ones that depend on a workflow, not on stored data:

- New plan items and candidates use active exercises only (DQ16).
- Recommendations are created only after the check-in is closed (DQ06). This is guaranteed by the order of steps in one transaction (§3.3).
- Positions in a phase are kept continuous (DQ13). The API renumbers them when an item is removed.
- The plan checks BR1–BR8 produce **warnings** for the coach, not errors (thesis 2.5: the coach decides). They are therefore not database constraints. The database only enforces that the check happens in the right order (plan status, session status; §2.7).
- The BR1–BR8 check is one backend function over a list of items. It runs on the blueprint (`v_plan_item`) before the plan becomes `reviewed`, and on the concrete plan of a session (`v_session_plan`) before the session becomes `reviewed`.

### 2.5 Check queries

The rules that concern the library or the data as a whole (DQ09–DQ12, DQ14, DQ17, DQ24, DQ26–DQ28, and the data checks of DQ30 and DQ32) are SQL queries stored in `db/checks/`. Each query returns the rows that **violate** the rule, so an empty result means the rule holds. They run:

- at the end of every library/seed import, **inside the import transaction**: if any error-level check returns rows, the whole import is rolled back (§3.6);
- in the automated tests (CI);
- before the pilot, as part of the release checklist.

Warning-level checks (DQ11, DQ13, DQ15, DQ17, DQ28, DQ32) are reported but do not fail the import.

### 2.6 Integrity of personal data

- Passwords are stored only as argon2id hashes (`app_user.password_hash`).
- Participants are anonymous: no table has a column for their name, contact, IP address or device id (DQ20). A test scans column names in `information_schema` for forbidden patterns (`ip`, `phone`, `device`, …).
- Deleting a session deletes all participant data collected for it in one statement (cascade to `checkin`, `checkin_discomfort`, `feedback`, `recommendation`, `recommendation_decision`).

### 2.7 Plan and session model

**Blueprint and concrete plan.** A *plan* is a blueprint built by the coach. A *session* is the concrete plan of one class: the blueprint, plus the coach's decisions on this session's recommendations, plus metadata (time, group, check-ins, attendance). Nothing from the plan is copied into the session. The concrete plan is calculated by the view `v_session_plan`:

| Recommendation (accepted) | Effect on the concrete plan |
|---|---|
| Replacement (BR10) | The item's exercise is swapped for the candidate |
| Alternative (BR9) | Shown next to the original; the item keeps its exercise |
| Warning (BR11) | No change (general advice only) |

Declined and undecided recommendations change nothing. At most one replacement per item and session can be accepted (DQ33), so every item has exactly one effective exercise. Durations come from one function, `item_duration_sec()`, for both lists.

**The same check runs twice.** The BR1–BR8 check is run on the blueprint (plan review) and again on the concrete plan after the decisions (session review). The statuses record these two reviews:

```text
plan:     draft ──► completed ──► reviewed           (any change ──► draft)
                                     │
                                     ▼  session created (plan is now locked)
session:  open ──► closed ──► reviewed ──► done
                    │            ▲
                    │            └ every recommendation decided (DQ32)
                    └ recommendations generated (T2)
```

**Protection of past sessions (plan lock).** If a session's plan could still change, the concrete plan of that session would change afterwards: its items, durations and the targets of its recommendations. Therefore:

1. A session can be created only from a `reviewed` plan (DQ30).
2. From that moment the plan is **locked** (DQ31), whatever the session's status: no item can be inserted, changed or deleted, and `target_duration_min` and `status` cannot change. Title and notes can still be edited.
3. To change a locked plan, the coach duplicates it (`duplicate_plan()`, T9) and edits the copy, which starts as a new `draft`. Later sessions use the copy; earlier sessions keep the original.

The lock is calculated (`plan_is_locked()` = a session exists), not stored, so it cannot get out of step with the sessions.

**What is not protected (by design).** The concrete plan reads exercise data (`rep_duration_sec`, `is_symmetric`, `mode`) from the current library. If the author edits an exercise, the calculated values of old plans and sessions follow. The library is the single source of exercise data.

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
- **Nothing else is written.** There is no session copy of the plan: the concrete plan (`v_session_plan`) is calculated from the decisions, so the decision and the change of the concrete plan can never get out of step.
- Accepting a replacement: the trigger `trg_decision_single_replacement` locks the plan item row and rejects a second accepted replacement for the same item and session (DQ33). Two concurrent accepts for the same item wait for each other; the second one fails with `P0001` → 409.
- Warnings are decided in the same way (`accepted` = the coach applies the advice).

#### T5 — Coach saves a plan (US2.1, US2.2)

```sql
BEGIN;
  UPDATE plan SET title = :title, notes = :notes, target_duration_min = :target
   WHERE id = :pid AND updated_at = :version     -- optimistic lock
  RETURNING id;                                  -- 0 rows -> 409 "plan changed elsewhere"
  DELETE FROM plan_item WHERE plan_id = :pid AND id <> ALL(:kept_ids);
  UPDATE plan_item SET position = ..., ... WHERE id = ...;   -- deferred UNIQUE allows swaps
  INSERT INTO plan_item (...) VALUES (...);
  -- triggers: locked plan -> P0001 (DQ31), whole save rolled back;
  --           otherwise a completed/reviewed plan goes back to 'draft'
COMMIT;   -- deferred UNIQUE (plan_id, phase, position) checked here
```

- **Optimistic locking.** The client sends the `updated_at` value it loaded. If the plan was saved meanwhile (e.g. in another tab), the update matches 0 rows and the coach is asked to reload, so no change is silently overwritten.
- **Locked plan.** A plan used by a session cannot be saved with item or target changes (DQ31). The API checks `plan_is_locked()` first and offers "duplicate" (T9); the trigger is the final guarantee.
- **Status.** Saving a changed plan moves it back to `draft`. When the coach finishes, the API sets `status = 'completed'`. The coach then runs the BR1–BR8 check on `v_plan_item`, reviews the warnings, and the API sets `status = 'reviewed'`. Each status change is a short transaction of its own.

#### T6 — Coach enters attendance after class (US3.5)

```sql
UPDATE session SET participants_present = :n, status = 'done'
 WHERE id = :sid AND status = 'reviewed';
```

This is a single statement and therefore atomic by itself. The CHECK constraint ensures `participants_present` is not NULL when the status becomes `done` (DQ05). `participants_present` can also be entered earlier, without changing the status (it is the base of BR9/BR10 shares once known).

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

#### T8 — Coach finishes the session review (US5.1, US5.2)

```sql
-- 1. outside the transaction: the backend reads v_session_plan for :sid
--    and runs the BR1–BR8 check on it; the coach sees the result
BEGIN;
  UPDATE session SET status = 'reviewed'
   WHERE id = :sid AND status = 'closed'
  RETURNING id;          -- 0 rows -> already reviewed or not closed yet
  -- trigger: P0001 (DQ32) if any recommendation has no decision -> 409
COMMIT;
```

- The trigger counts undecided recommendations inside the same statement, so the check and the status change are atomic.
- A session with no recommendations can be reviewed at once.

#### T9 — Coach duplicates a plan

```sql
BEGIN;
  SELECT duplicate_plan(:pid, :title);   -- returns the new plan id
COMMIT;
```

- The new plan and all its items are inserted in one transaction: there is never a copy without its items.
- The copy is a `draft` without sessions, so it is not locked and the coach can edit it (T5).
- The API checks that the caller owns `:pid` before calling the function (the function runs with the caller's rights, `kinetune_api`).

### 3.3 Order of operations inside T2

DQ06 ("recommendations only after the check-in is closed") is not a trigger, because the guarantee comes from the order of steps inside T2. The status change is the first statement, and recommendations are inserted after it, in the same transaction. If inserting a recommendation fails, the status change is rolled back too, and the session stays `open`.

### 3.4 Concurrency scenarios

| Scenario | Risk | How it is prevented |
|---|---|---|
| A participant submits a check-in at the moment the coach closes it | Under READ COMMITTED, the check-in trigger could read `open` just before T2 commits. The check-in would then be saved but missed by the recommendations. | The trigger reads the session with `FOR SHARE`, and T2's `UPDATE` needs an exclusive row lock, so the two wait for each other. If the check-in comes first, T2 waits and then sees it. If T2 comes first, the trigger waits, then reads `closed` and rejects the check-in. |
| The coach clicks "Close check-in" twice | Duplicate recommendations | `UPDATE … WHERE status = 'open'` changes the row only once (T2) |
| Two decisions for one recommendation | Conflicting decisions; wrong K3 | Primary key on `recommendation_decision.recommendation_id` + `ON CONFLICT DO NOTHING` (T4) |
| The plan is edited in two tabs | Lost update | Optimistic lock on `plan.updated_at` (T5) |
| A plan item is edited while a session is being created from the same plan | The session would start from a plan that is no longer the reviewed one, or a locked plan would change | The item trigger locks the plan row `FOR UPDATE`; the session trigger locks it `FOR SHARE`. If the edit comes first, the plan becomes `draft` and the session is rejected (DQ30). If the session comes first, the edit waits and is then rejected as locked (DQ31). |
| Two replacements for the same item are accepted at the same moment | Two effective exercises for one item | The decision trigger locks the plan item row (`FOR NO KEY UPDATE`); the second accept waits, then sees the first and fails (DQ33) |
| Two admins revoke each other's admin role | No admin left | `FOR UPDATE` on admin rows in `trg_last_admin_role` (T7) |
| An LLM answer arrives after the coach has decided | The explanation changes under a decision | `NOT EXISTS` decision condition in T3 |
| The KPI report is read while check-ins are being written | Inconsistent numbers | Each report query is a single statement, and PostgreSQL gives every statement a consistent snapshot (MVCC). Readers never block writers. |

### 3.5 Error handling

| SQLSTATE | Cause | API response |
|---|---|---|
| `23505` unique_violation | Duplicate name, e-mail, position | 409 Conflict, naming the field |
| `23503` foreign_key_violation | Deleting a referenced row (`RESTRICT`) or referencing a missing one | 409 Conflict ("in use") / 422 |
| `23514` check_violation, `23502` not_null_violation | Invalid value | 422 Unprocessable Entity |
| `P0001` raised by a trigger | Business rule broken (e.g. check-in after close, locked plan) | 409 Conflict with the trigger's message |
| `P0002` raised by `duplicate_plan()` | The plan does not exist | 404 Not Found |
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
