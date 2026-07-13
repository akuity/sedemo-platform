-- Demo driver table: each demo run generates a new timestamped migration that
-- inserts a row here (db/demo-assets/new-migration.sh), so the migration beat
-- is repeatable forever without resetting schemas or reverting commits.
CREATE TABLE release_notes (
    id         SERIAL PRIMARY KEY,
    note       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
