-- migrate: no-transaction
-- migrate:up
CREATE INDEX CONCURRENTLY authors_email_idx ON authors (email);

-- migrate:down
DROP INDEX CONCURRENTLY authors_email_idx;
