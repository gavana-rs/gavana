-- migrate:up
CREATE TABLE mastiff_sessions (
    token_hash   bytea PRIMARY KEY,
    user_id      bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    user_agent   text,
    ip           inet
);
CREATE INDEX mastiff_sessions_user_id_idx ON mastiff_sessions (user_id);

-- migrate:down
DROP TABLE mastiff_sessions;
