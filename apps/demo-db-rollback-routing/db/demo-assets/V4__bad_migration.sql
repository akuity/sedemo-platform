-- DEMO ASSET: copy into db/migrations/ and commit to main to trigger the
-- failed-migration beat. References a table that does not exist, so
-- flyway-migrate fails, the Promotion fails, and the autoRollback policy
-- re-promotes the last good Freight. Postgres DDL is transactional, so the
-- failed attempt leaves no partial schema behind; the step's built-in
-- `flyway repair` clears the failed history row on the next run.
ALTER TABLE order_items
    ADD COLUMN discount_cents INTEGER NOT NULL DEFAULT 0;
