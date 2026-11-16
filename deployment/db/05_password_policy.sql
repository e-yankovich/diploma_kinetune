-- =====================================================================
-- Kinetune — password storage policy
-- Applied by Alembic migration 0004. Manual run:
--   psql -v ON_ERROR_STOP=1 --single-transaction -f 05_password_policy.sql
--
-- Application passwords are hashed by the backend with argon2id
-- (argon2-cffi, defaults m=65536 KiB, t=3, p=4) and stored in PHC string
-- format:  $argon2id$v=19$m=65536,t=3,p=4$<salt b64>$<hash b64>
-- The CHECK makes the database reject anything else: plain text, MD5,
-- SHA-1/SHA-256 hex digests, bcrypt, or argon2i/argon2d.
-- Database login roles use SCRAM-SHA-256 (db/init/login_roles.psql).
-- =====================================================================

SET search_path TO kinetune;

ALTER TABLE app_user
    ADD CONSTRAINT ck_app_user_password_argon2id
    CHECK (password_hash ~ '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]{16,}\$[A-Za-z0-9+/]{32,}$');

COMMENT ON COLUMN app_user.password_hash IS
    'argon2id hash in PHC format, computed by the backend; never plain text, MD5 or SHA-1';
