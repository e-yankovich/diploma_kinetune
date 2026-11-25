-- =====================================================================
-- Kinetune — database structure (DDL)
-- File 1 of 2: types, tables, constraints, indexes, comments
-- Matches kinetune_schema.dbml v0.5 and data_dictionary.md v0.5
-- Target: PostgreSQL 18 (also runs on 16+)
-- Normally applied by Alembic migration 0001 (one transaction).
-- Manual run as the migrator role:  psql -v ON_ERROR_STOP=1 --single-transaction -f 01_schema.sql
-- =====================================================================


CREATE SCHEMA IF NOT EXISTS kinetune;
SET search_path TO kinetune;

-- ---------------------------------------------------------------------
-- 1. Enumerated types
-- ---------------------------------------------------------------------

CREATE TYPE phase               AS ENUM ('warm_up', 'main', 'cool_down');
CREATE TYPE exercise_mode       AS ENUM ('dynamic', 'static', 'stato_dynamic');
CREATE TYPE starting_pose       AS ENUM ('seated', 'standing', 'lying', 'balance');
CREATE TYPE side                AS ENUM ('left', 'right', 'both');
CREATE TYPE relation_type       AS ENUM ('variation', 'progression');
CREATE TYPE session_status      AS ENUM ('open', 'closed', 'done');
CREATE TYPE recommendation_form AS ENUM ('alternative', 'replacement');
CREATE TYPE explanation_source  AS ENUM ('template', 'llm');
CREATE TYPE decision_type       AS ENUM ('accepted', 'declined');

-- ---------------------------------------------------------------------
-- 2. Access control (application roles)
-- ---------------------------------------------------------------------

CREATE TABLE app_user (
    id             integer      GENERATED ALWAYS AS IDENTITY,
    email          varchar(254) NOT NULL,
    password_hash  text         NOT NULL,
    display_name   varchar(80)  NOT NULL,
    is_active      boolean      NOT NULL DEFAULT true,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    last_login_at  timestamptz,
    CONSTRAINT pk_app_user PRIMARY KEY (id),
    CONSTRAINT uq_app_user_email UNIQUE (email),
    CONSTRAINT ck_app_user_email_lower CHECK (email = lower(email)),
    CONSTRAINT ck_app_user_display_name CHECK (btrim(display_name) <> '')
);

CREATE TABLE role (
    id           smallint    GENERATED ALWAYS AS IDENTITY,
    code         varchar(32) NOT NULL,
    name         varchar(64) NOT NULL,
    description  text,
    CONSTRAINT pk_role PRIMARY KEY (id),
    CONSTRAINT uq_role_code UNIQUE (code),
    CONSTRAINT ck_role_code CHECK (code ~ '^[a-z_]+$')
);

CREATE TABLE permission (
    id           smallint    GENERATED ALWAYS AS IDENTITY,
    code         varchar(64) NOT NULL,
    description  text        NOT NULL,
    CONSTRAINT pk_permission PRIMARY KEY (id),
    CONSTRAINT uq_permission_code UNIQUE (code),
    CONSTRAINT ck_permission_code CHECK (code ~ '^[a-z_]+\.[a-z_]+$')
);

CREATE TABLE role_permission (
    role_id        smallint NOT NULL,
    permission_id  smallint NOT NULL,
    CONSTRAINT pk_role_permission PRIMARY KEY (role_id, permission_id),
    CONSTRAINT fk_role_permission_role
        FOREIGN KEY (role_id) REFERENCES role (id) ON DELETE CASCADE,
    CONSTRAINT fk_role_permission_permission
        FOREIGN KEY (permission_id) REFERENCES permission (id) ON DELETE CASCADE
);

CREATE TABLE user_role (
    user_id     integer     NOT NULL,
    role_id     smallint    NOT NULL,
    granted_at  timestamptz NOT NULL DEFAULT now(),
    granted_by  integer,
    CONSTRAINT pk_user_role PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_user_role_user
        FOREIGN KEY (user_id) REFERENCES app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_role_role
        FOREIGN KEY (role_id) REFERENCES role (id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_role_granted_by
        FOREIGN KEY (granted_by) REFERENCES app_user (id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------
-- 3. Reference data
-- ---------------------------------------------------------------------

CREATE TABLE body_area (
    id       smallint    GENERATED ALWAYS AS IDENTITY,
    code     varchar(32) NOT NULL,
    name_en  varchar(64) NOT NULL,
    name_ru  varchar(64) NOT NULL,
    CONSTRAINT pk_body_area PRIMARY KEY (id),
    CONSTRAINT uq_body_area_code UNIQUE (code),
    CONSTRAINT ck_body_area_code CHECK (code ~ '^[a-z_]+$'),
    CONSTRAINT ck_body_area_name_en CHECK (btrim(name_en) <> ''),
    CONSTRAINT ck_body_area_name_ru CHECK (btrim(name_ru) <> '')
);

CREATE TABLE muscle (
    id            smallint    GENERATED ALWAYS AS IDENTITY,
    name          varchar(64) NOT NULL,
    body_area_id  smallint    NOT NULL,
    CONSTRAINT pk_muscle PRIMARY KEY (id),
    CONSTRAINT uq_muscle_name UNIQUE (name),
    CONSTRAINT fk_muscle_body_area
        FOREIGN KEY (body_area_id) REFERENCES body_area (id) ON DELETE RESTRICT
);

CREATE TABLE joint (
    id            smallint    GENERATED ALWAYS AS IDENTITY,
    name          varchar(64) NOT NULL,
    body_area_id  smallint    NOT NULL,
    CONSTRAINT pk_joint PRIMARY KEY (id),
    CONSTRAINT uq_joint_name UNIQUE (name),
    CONSTRAINT fk_joint_body_area
        FOREIGN KEY (body_area_id) REFERENCES body_area (id) ON DELETE RESTRICT
);

CREATE TABLE rule (
    id           smallint NOT NULL,          -- set explicitly: 1–11 = BR1–BR11
    description  text     NOT NULL,
    explanation  text     NOT NULL,
    CONSTRAINT pk_rule PRIMARY KEY (id),
    CONSTRAINT ck_rule_id CHECK (id BETWEEN 1 AND 11)
);

-- ---------------------------------------------------------------------
-- 4. Exercise library
-- ---------------------------------------------------------------------

CREATE TABLE exercise (
    id                        integer       GENERATED ALWAYS AS IDENTITY,
    name                      varchar(120)  NOT NULL,
    description               text,
    mode                      exercise_mode NOT NULL,
    starting_pose             starting_pose NOT NULL,
    is_symmetric              boolean       NOT NULL DEFAULT true,
    required_compensation_id  integer,
    difficulty                smallint      NOT NULL,
    default_duration_sec      integer       NOT NULL,
    is_active                 boolean       NOT NULL DEFAULT true,
    created_at                timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_exercise PRIMARY KEY (id),
    CONSTRAINT uq_exercise_name UNIQUE (name),
    CONSTRAINT ck_exercise_difficulty CHECK (difficulty BETWEEN 1 AND 3),
    CONSTRAINT ck_exercise_duration CHECK (default_duration_sec > 0),
    CONSTRAINT ck_exercise_compensation_not_self CHECK (required_compensation_id <> id),
    CONSTRAINT fk_exercise_required_compensation
        FOREIGN KEY (required_compensation_id) REFERENCES exercise (id) ON DELETE RESTRICT
);

CREATE TABLE exercise_muscle (
    exercise_id  integer  NOT NULL,
    muscle_id    smallint NOT NULL,
    is_primary   boolean  NOT NULL DEFAULT false,
    CONSTRAINT pk_exercise_muscle PRIMARY KEY (exercise_id, muscle_id),
    CONSTRAINT fk_exercise_muscle_exercise
        FOREIGN KEY (exercise_id) REFERENCES exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise_muscle_muscle
        FOREIGN KEY (muscle_id) REFERENCES muscle (id) ON DELETE RESTRICT
);

CREATE TABLE exercise_joint (
    exercise_id  integer  NOT NULL,
    joint_id     smallint NOT NULL,
    is_primary   boolean  NOT NULL DEFAULT false,
    CONSTRAINT pk_exercise_joint PRIMARY KEY (exercise_id, joint_id),
    CONSTRAINT fk_exercise_joint_exercise
        FOREIGN KEY (exercise_id) REFERENCES exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise_joint_joint
        FOREIGN KEY (joint_id) REFERENCES joint (id) ON DELETE RESTRICT
);

CREATE TABLE exercise_relation (
    id                integer       GENERATED ALWAYS AS IDENTITY,
    from_exercise_id  integer       NOT NULL,
    to_exercise_id    integer       NOT NULL,
    type              relation_type NOT NULL,
    is_directed       boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_exercise_relation PRIMARY KEY (id),
    CONSTRAINT uq_exercise_relation UNIQUE (from_exercise_id, to_exercise_id, type),
    CONSTRAINT ck_exercise_relation_not_self CHECK (from_exercise_id <> to_exercise_id),
    -- an undirected edge is stored once, with the smaller id first
    CONSTRAINT ck_exercise_relation_undirected_order
        CHECK (is_directed OR from_exercise_id < to_exercise_id),
    CONSTRAINT fk_exercise_relation_from
        FOREIGN KEY (from_exercise_id) REFERENCES exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise_relation_to
        FOREIGN KEY (to_exercise_id) REFERENCES exercise (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 5. Planning
-- ---------------------------------------------------------------------

CREATE TABLE plan (
    id          integer      GENERATED ALWAYS AS IDENTITY,
    coach_id    integer      NOT NULL,
    title       varchar(120) NOT NULL,
    notes       text,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_plan PRIMARY KEY (id),
    CONSTRAINT ck_plan_title CHECK (btrim(title) <> ''),
    CONSTRAINT fk_plan_coach
        FOREIGN KEY (coach_id) REFERENCES app_user (id) ON DELETE RESTRICT
);

CREATE TABLE plan_item (
    id            integer  GENERATED ALWAYS AS IDENTITY,
    plan_id       integer  NOT NULL,
    exercise_id   integer  NOT NULL,
    phase         phase    NOT NULL,
    position      smallint NOT NULL,
    duration_sec  integer  NOT NULL,
    side          side     NOT NULL DEFAULT 'both',
    reps_count    smallint,
    CONSTRAINT pk_plan_item PRIMARY KEY (id),
    -- checked at COMMIT so that items can be reordered in one transaction
    CONSTRAINT uq_plan_item_position UNIQUE (plan_id, phase, position)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT ck_plan_item_position CHECK (position >= 1),
    CONSTRAINT ck_plan_item_duration CHECK (duration_sec > 0),
    CONSTRAINT ck_plan_item_reps CHECK (reps_count > 0),
    CONSTRAINT fk_plan_item_plan
        FOREIGN KEY (plan_id) REFERENCES plan (id) ON DELETE CASCADE,
    CONSTRAINT fk_plan_item_exercise
        FOREIGN KEY (exercise_id) REFERENCES exercise (id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 6. Sessions and participant input
-- ---------------------------------------------------------------------

CREATE TABLE session (
    id                    integer        GENERATED ALWAYS AS IDENTITY,
    coach_id              integer        NOT NULL,
    plan_id               integer        NOT NULL,
    group_name            varchar(80)    NOT NULL,
    starts_at             timestamptz    NOT NULL,
    status                session_status NOT NULL DEFAULT 'open',
    checkin_token         varchar(43)    NOT NULL,
    checkin_closed_at     timestamptz,
    participants_present  smallint,
    created_at            timestamptz    NOT NULL DEFAULT now(),
    CONSTRAINT pk_session PRIMARY KEY (id),
    CONSTRAINT uq_session_checkin_token UNIQUE (checkin_token),
    CONSTRAINT ck_session_group_name CHECK (btrim(group_name) <> ''),
    CONSTRAINT ck_session_token_format CHECK (checkin_token ~ '^[A-Za-z0-9_-]{43}$'),
    CONSTRAINT ck_session_closed_at CHECK ((status = 'open') = (checkin_closed_at IS NULL)),
    CONSTRAINT ck_session_present_nonneg CHECK (participants_present >= 0),
    CONSTRAINT ck_session_present_when_done
        CHECK (status <> 'done' OR participants_present IS NOT NULL),
    CONSTRAINT fk_session_coach
        FOREIGN KEY (coach_id) REFERENCES app_user (id) ON DELETE RESTRICT,
    CONSTRAINT fk_session_plan
        FOREIGN KEY (plan_id) REFERENCES plan (id) ON DELETE RESTRICT
);

CREATE TABLE checkin (
    id            integer     GENERATED ALWAYS AS IDENTITY,
    session_id    integer     NOT NULL,
    energy        smallint    NOT NULL,
    poor_sleep    boolean     NOT NULL,
    language      char(2)     NOT NULL,
    submitted_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_checkin PRIMARY KEY (id),
    CONSTRAINT ck_checkin_energy CHECK (energy BETWEEN 1 AND 5),
    CONSTRAINT ck_checkin_language CHECK (language IN ('en', 'ru')),
    CONSTRAINT fk_checkin_session
        FOREIGN KEY (session_id) REFERENCES session (id) ON DELETE CASCADE
);

CREATE TABLE checkin_discomfort (
    checkin_id    integer  NOT NULL,
    body_area_id  smallint NOT NULL,
    CONSTRAINT pk_checkin_discomfort PRIMARY KEY (checkin_id, body_area_id),
    CONSTRAINT fk_checkin_discomfort_checkin
        FOREIGN KEY (checkin_id) REFERENCES checkin (id) ON DELETE CASCADE,
    CONSTRAINT fk_checkin_discomfort_body_area
        FOREIGN KEY (body_area_id) REFERENCES body_area (id) ON DELETE RESTRICT
);

CREATE TABLE feedback (
    id            integer     GENERATED ALWAYS AS IDENTITY,
    session_id    integer     NOT NULL,
    rating        smallint    NOT NULL,
    comment       text,
    submitted_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_feedback PRIMARY KEY (id),
    CONSTRAINT ck_feedback_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT ck_feedback_comment_length CHECK (char_length(comment) <= 1000),
    CONSTRAINT fk_feedback_session
        FOREIGN KEY (session_id) REFERENCES session (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 7. Recommendations
-- ---------------------------------------------------------------------

CREATE TABLE recommendation (
    id                     integer             GENERATED ALWAYS AS IDENTITY,
    session_id             integer             NOT NULL,
    plan_item_id           integer             NOT NULL,
    rule_id                smallint            NOT NULL,
    form                   recommendation_form NOT NULL,
    is_warning             boolean             NOT NULL DEFAULT false,
    candidate_exercise_id  integer,
    affected_count         smallint            NOT NULL,
    explanation            text                NOT NULL,
    explanation_source     explanation_source  NOT NULL,
    created_at             timestamptz         NOT NULL DEFAULT now(),
    CONSTRAINT pk_recommendation PRIMARY KEY (id),
    CONSTRAINT ck_recommendation_warning
        CHECK (is_warning = (candidate_exercise_id IS NULL)),
    CONSTRAINT ck_recommendation_affected CHECK (affected_count >= 0),
    CONSTRAINT ck_recommendation_explanation CHECK (btrim(explanation) <> ''),
    CONSTRAINT fk_recommendation_session
        FOREIGN KEY (session_id) REFERENCES session (id) ON DELETE CASCADE,
    CONSTRAINT fk_recommendation_plan_item
        FOREIGN KEY (plan_item_id) REFERENCES plan_item (id) ON DELETE RESTRICT,
    CONSTRAINT fk_recommendation_rule
        FOREIGN KEY (rule_id) REFERENCES rule (id) ON DELETE RESTRICT,
    CONSTRAINT fk_recommendation_candidate
        FOREIGN KEY (candidate_exercise_id) REFERENCES exercise (id) ON DELETE RESTRICT
);

CREATE TABLE recommendation_decision (
    recommendation_id  integer       NOT NULL,
    decision           decision_type NOT NULL,
    decided_at         timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_recommendation_decision PRIMARY KEY (recommendation_id),
    CONSTRAINT fk_recommendation_decision_recommendation
        FOREIGN KEY (recommendation_id) REFERENCES recommendation (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 8. Indexes
-- PRIMARY KEY and UNIQUE constraints create their own indexes.
-- The indexes below support the main queries and FK checks.
-- ---------------------------------------------------------------------

-- recursive candidate search (WITH RECURSIVE over the exercise graph)
CREATE INDEX ix_exercise_relation_from_type ON exercise_relation (from_exercise_id, type);
-- undirected edges are also followed backwards
CREATE INDEX ix_exercise_relation_to        ON exercise_relation (to_exercise_id);
-- session list and per-period KPIs
CREATE INDEX ix_session_starts_at           ON session (starts_at);
-- per-session aggregates and cascading deletes
CREATE INDEX ix_checkin_session             ON checkin (session_id);
CREATE INDEX ix_feedback_session            ON feedback (session_id);
CREATE INDEX ix_recommendation_session      ON recommendation (session_id);
-- "who holds role X" (last-admin check, coach-role checks)
CREATE INDEX ix_user_role_role              ON user_role (role_id);

-- ---------------------------------------------------------------------
-- 9. Comments (documentation stored in the database)
-- ---------------------------------------------------------------------

COMMENT ON SCHEMA kinetune IS 'Kinetune: hybrid recommendation system for adapting group training plans';

COMMENT ON TABLE app_user                IS 'Accounts that log in (coach, admin; client later). Personal data.';
COMMENT ON TABLE role                    IS 'Application roles: coach, admin';
COMMENT ON TABLE permission              IS 'Application permissions, code <resource>.<action>';
COMMENT ON TABLE role_permission         IS 'Permissions of each role (M:N)';
COMMENT ON TABLE user_role               IS 'Roles of each user (M:N)';
COMMENT ON TABLE body_area               IS 'Body area reported in check-in discomfort; consists of muscles and joints';
COMMENT ON TABLE muscle                  IS 'Muscle; belongs to one body area';
COMMENT ON TABLE joint                   IS 'Joint; belongs to one body area';
COMMENT ON TABLE rule                    IS 'Business rules BR1–BR11 (id = BR number)';
COMMENT ON TABLE exercise                IS 'Exercise library (predefined by the author)';
COMMENT ON TABLE exercise_muscle         IS 'Muscles worked by an exercise (M:N)';
COMMENT ON TABLE exercise_joint          IS 'Joints loaded by an exercise (M:N)';
COMMENT ON TABLE exercise_relation       IS 'Exercise graph edges: variation / progression';
COMMENT ON TABLE plan                    IS 'Reusable class plan (template)';
COMMENT ON TABLE plan_item               IS 'Exercise at a position within a phase of a plan';
COMMENT ON TABLE session                 IS 'One class held with a plan; owns the check-in link';
COMMENT ON TABLE checkin                 IS 'Anonymous pre-class answer';
COMMENT ON TABLE checkin_discomfort      IS 'Body areas marked as uncomfortable in a check-in';
COMMENT ON TABLE feedback                IS 'Anonymous voluntary feedback after class';
COMMENT ON TABLE recommendation          IS 'Suggestion generated for a plan item when check-in closes';
COMMENT ON TABLE recommendation_decision IS 'Coach decision on a recommendation (1:1)';

COMMENT ON COLUMN exercise.required_compensation_id IS 'Exercise that must follow this one before the end of class (BR6)';
COMMENT ON COLUMN exercise.is_symmetric             IS 'false = asymmetric, performed per side (BR7)';
COMMENT ON COLUMN exercise_relation.is_directed     IS 'false = edge followed both ways; stored once with from < to';
COMMENT ON COLUMN session.participants_present      IS 'Entered after class; base for K2 and K4';
COMMENT ON COLUMN recommendation.form               IS 'What the rule called for: alternative (BR9) or replacement (BR10)';
COMMENT ON COLUMN recommendation.is_warning         IS 'true = no suitable substitute found; general advice instead (BR11)';
