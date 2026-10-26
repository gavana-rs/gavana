-- migrate:up
CREATE TABLE mastiff_password_resets (
    token_hash bytea PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL
);
CREATE INDEX mastiff_password_resets_user_id_idx ON mastiff_password_resets (user_id);

-- migrate:down
DROP TABLE mastiff_password_resets;
