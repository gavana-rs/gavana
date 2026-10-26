# gavana-migrate

Migration runner for gavana over `gavana-db`: Postgres, SQLite and MySQL.
SQL-first, timestamp-versioned, checksummed, lock-safe, and lint-aware.
Design decided 2026-10-12; widened to three dialects 2026-10-16.

## File format

One directory per dialect: `db/migrations/{postgres,sqlite,mysql}/`. An app
that ships one database has one directory. One file per migration, named
`YYYYMMDDHHMMSS_snake_case_name.sql`. Markers:

```sql
-- migrate: no-transaction        optional, must come before :up
-- migrate: allow-destructive     optional, required for DROP / column removal
-- migrate:up
...sql...
-- migrate:down                   optional; rollback refuses without it
...sql...
```

Rust migrations (data backfills needing app logic) come later via a
`Migration` trait; they share the version space and the state table.

## Versioning

Timestamps, not sequential ints. A pending migration older than the newest
applied one is an error unless `--allow-out-of-order` is passed. Applied
checksums are compared on every run; a mismatch is an error.

## Running

- A run lock held for the whole run so concurrent deploys queue.
- Each migration in its own transaction where the dialect supports
  transactional DDL, unless `no-transaction` is set.
- A lock timeout per migration so a busy table fails fast rather than
  blocking the application.
- State table `_gavana_migrations`: version, name, checksum, applied_at,
  duration_ms. Same columns on every backend; types per dialect.

## Dialect differences

| Concern            | Postgres                    | SQLite                          | MySQL                                   |
|--------------------|-----------------------------|---------------------------------|-----------------------------------------|
| Run lock           | `pg_advisory_lock`          | `BEGIN IMMEDIATE` (file lock)   | `GET_LOCK('gavana_migrate', timeout)`   |
| Transactional DDL  | yes                         | yes                             | **no**: DDL commits implicitly          |
| Lock timeout       | `SET lock_timeout`          | `busy_timeout`                  | `SET lock_wait_timeout`                 |
| `no-transaction`   | for `CONCURRENTLY` etc.     | rarely needed                   | effectively always on                   |
| `allow-destructive`| same semantics everywhere   |                                 |                                         |

MySQL is the awkward one. Because DDL is not transactional, a failed
migration leaves partial state. The runner records progress per statement
on MySQL and reports exactly which statement failed, and lint warns when a
MySQL migration has more than one DDL statement.

## Rollback

Down is optional. `rollback --steps N` and `rollback --to VERSION`. The `new`
command scaffolds a down for the invertible subset (create table, add column,
create index, add constraint).

## Snapshot (phase 2)

After a successful `migrate`, dump the catalog to `db/schema.sql`. Tests load
it directly; `prepared` introspects against it; reviewers diff it.

## Lint (phase 3)

Needs a SQL parser, shared with `prepared` (`pg_query` for Postgres,
`sqlparser-rs` dialects for the rest). Warn or refuse on: non-concurrent
index on an existing table (Postgres), NOT NULL column without default,
type change forcing a rewrite, rename/drop without `allow-destructive`,
missing timeouts, multi-statement DDL on MySQL.

## Later

`squash` into a baseline, `migrate!()` embed macro, declarative diff mode,
zero-downtime expand/contract mode (pgroll-style).

## CLI (lives in the gavana CLI, not here)

`gavana db create | drop | new | migrate | rollback | status | redo | reset |
lint | dump | load | squash | seed`

## Phases

1. discover, parse, state, runner on Postgres via `gavana-db`: `migrate` and
   `status` work end to end.
2. rollback, `new` with inverse scaffolding, snapshot.
3. lint.
4. squash, embed macro.
5. SQLite and MySQL runners behind the same API, with the dialect table
   above as the spec.
