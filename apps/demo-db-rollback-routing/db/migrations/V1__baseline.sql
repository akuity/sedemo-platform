-- Baseline schema. Flyway records each applied migration in
-- flyway_schema_history, visible in the pgweb schema viewer.
CREATE TABLE customers (
    id         SERIAL PRIMARY KEY,
    name       TEXT        NOT NULL,
    email      TEXT        NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
    id          SERIAL PRIMARY KEY,
    customer_id INTEGER     NOT NULL REFERENCES customers (id),
    total_cents INTEGER     NOT NULL,
    placed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
