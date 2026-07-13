#!/usr/bin/env bash
# Generates a fresh, timestamp-versioned Flyway migration so every demo run is
# repeatable without resetting databases or reverting commits.
#
#   ./new-migration.sh "Enabled loyalty tier for gold customers"
#       -> V<UTC timestamp>__demo_release_note.sql inserting a release_notes row
#
#   ./new-migration.sh --bad
#       -> V<UTC timestamp>__demo_bad_migration.sql referencing a table that
#          does not exist; the flyway-migrate step fails and the promotion
#          fails with it (dev has no autoRollback, staging/prod do)
#
#   ./new-migration.sh --fix
#       -> rewrites every *__demo_bad_migration.sql in db/migrations into a
#          valid release_notes insert. Fix-forward: a failed migration was
#          never recorded by Flyway, so its file can be edited freely.
#
# Commit and push the result to main; the Warehouse mints new Freight from it.
set -euo pipefail

MIGRATIONS_DIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
VERSION=$(date -u +%Y%m%d%H%M%S)

case "${1:-}" in
  --bad)
    FILE="$MIGRATIONS_DIR/V${VERSION}__demo_bad_migration.sql"
    cat > "$FILE" <<EOF
-- Intentionally broken demo migration (generated $(date -u +%FT%TZ)).
-- Run ./new-migration.sh --fix after the failure beat, then commit.
INSERT INTO table_that_does_not_exist (note) VALUES ('this will fail');
EOF
    echo "created $FILE"
    ;;
  --fix)
    shopt -s nullglob
    FIXED=0
    for f in "$MIGRATIONS_DIR"/V*__demo_bad_migration.sql; do
      cat > "$f" <<EOF
-- Fixed forward (generated $(date -u +%FT%TZ)): the failed run was never
-- recorded in flyway_schema_history, so editing this file is safe.
INSERT INTO release_notes (note) VALUES ('fixed forward after failed migration demo');
EOF
      echo "fixed $f"
      FIXED=1
    done
    [ "$FIXED" = 1 ] || { echo "no bad migrations found"; exit 1; }
    ;;
  "")
    echo "usage: $0 \"release note text\" | --bad | --fix" >&2
    exit 1
    ;;
  *)
    NOTE=${1//\'/\'\'}
    FILE="$MIGRATIONS_DIR/V${VERSION}__demo_release_note.sql"
    cat > "$FILE" <<EOF
-- Demo migration (generated $(date -u +%FT%TZ)).
INSERT INTO release_notes (note) VALUES ('${NOTE}');
EOF
    echo "created $FILE"
    ;;
esac
