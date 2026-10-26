-- migrate:up
CREATE TABLE authors (
    id    bigserial PRIMARY KEY,
    name  text NOT NULL,
    email text UNIQUE
);

-- migrate:down
DROP TABLE authors;
