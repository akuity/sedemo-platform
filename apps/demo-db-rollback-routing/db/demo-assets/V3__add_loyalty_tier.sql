-- DEMO ASSET: copy into db/migrations/ and commit to main to trigger the
-- happy-path migration beat. Expand/contract friendly: additive, nullable
-- with a default, so the previous app version keeps working against it
-- (which is what makes auto-rollback of the app safe).
ALTER TABLE customers
    ADD COLUMN loyalty_tier TEXT NOT NULL DEFAULT 'bronze';

UPDATE customers SET loyalty_tier = 'gold' WHERE email = 'ada@example.com';
