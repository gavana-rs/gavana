# prepared: research for a better Cornucopia

Status: research, 2026-10-15. Nothing decided yet; the open questions are at the end.

prepared is a SQL-first query library for Gavana. You write plain `.sql` files and prepared generates typed Rust functions and row structs from them. It is not an ORM: there is no query builder, no model layer and no relationship mapping. The SQL you write is the SQL that runs.

## 1. What exists today

| Tool | Approach | Databases | Notes |
|---|---|---|---|
| **Cornucopia** (Rust) | `.sql` files with `--!` annotations, prepared against a live Postgres, codegen to a `.rs` file/crate | Postgres only | 1.0 merged the Clorinde fork back in (Clorinde archived May 2026). Built on `tokio-postgres`/`postgres`, sync and async, deadpool support. Nullability is annotated by hand (`--! q : (col?)`). Needs a live DB or a container it starts. |
| **sqlx** (Rust) | `query!` macros check SQL at compile time against a DB or a committed `.sqlx` offline cache | Postgres, SQLite, MySQL | Infers nullability: Postgres via `pg_attribute` + `EXPLAIN`, SQLite by stepping through VDBE bytecode, MySQL from column `NOT_NULL` flags. SQLite inference is fragile (issue #1126: adding `ORDER BY` flips a column to `Option`). Macros slow builds and give poor IDE support; SQL lives inside Rust strings. |
| **sqlc** (Go, with community plugins) | Parses schema + queries itself (no DB needed for Postgres/MySQL), `-- name: X :one/:many/:exec` | Postgres, MySQL, SQLite | The model most people mean by "SQL-first". Its own catalog means it misses things a real DB would catch; Rust plugins are community-maintained and thin. |
| **PgTyped** (TS) | Prepares against live Postgres, nullability annotations | Postgres | Same shape as Cornucopia; good prior art for `!`/`?` override syntax. |
| **sqlx-gen, keelson** (Rust, 2026) | Schema introspection → structs/CRUD; keelson also compiles `.sql` files | All three | Young (keelson pre-1.0, not in production). Leans toward model/CRUD generation, which is the ORM direction we're avoiding. |

The gap: nothing in Rust gives Cornucopia's ergonomics (SQL in `.sql` files, readable generated code, no macros) across Postgres, SQLite and MySQL, with nullability inferred rather than hand-written.

## 2. What to do better than Cornucopia

1. **Three databases.** Postgres, SQLite and MySQL, because Mastiff needs all three (see `mastiff/design.md`).
2. **Infer nullability, allow overrides.** Infer from the schema and the query shape; let the author force it with `name!` (not null) or `name?` (nullable) when inference is wrong. Hand-annotating every nullable column is Cornucopia's biggest papercut.
3. **No Docker needed for the common case.** SQLite runs in-process, so prepared can apply migrations to an in-memory DB and check queries with zero setup. Postgres and MySQL use `DATABASE_URL` or a throwaway container, same as today.
4. **Offline cache.** After a check, write the inferred signatures to a committed `prepared.lock` (or `.prepared/` dir). CI and normal `cargo build` read the cache and never need a database. A stale cache is a clear error naming the query that changed.
5. **Plain generated code, not macros.** Generate ordinary `.rs` files (one module per `.sql` file) that you can read, jump to and debug. Fast builds, full IDE support. Option to run from `build.rs` (cache-only) or a `prepared` CLI.
6. **Errors point into the `.sql` file.** File, line and column of the bad SQL, with the database's own message.
7. **Common dynamic needs, without a builder.** The things people leave SQL-first tools for:
   - `IN` lists: Postgres uses `= ANY(:ids)`; for SQLite/MySQL prepared expands `:ids...` to the right number of placeholders at runtime.
   - Optional filters: documented pattern `(:email::text IS NULL OR email = :email)` with `Option<T>` params.
   - Sort/order: a declared enum of allowed `ORDER BY` fragments, never a free string.
   - Bulk insert: Postgres `UNNEST(:a, :b)`; SQLite/MySQL multi-row expansion.
8. **Shared row types.** `-- returns: User` maps a query's columns onto a struct declared once, so `find_by_id` and `find_by_login` both return `User`. This is exactly what Mastiff's `Authenticatable`/`UserStore` traits want from the scaffolded `users.sql`.
9. **One API across databases.** When the same query name exists in `queries/postgres/`, `queries/sqlite/` and `queries/mysql/` with compatible signatures, generate a common trait plus one impl per backend. Mastiff's `SessionStore` could then be one generic impl instead of three hand-written ones. This is new; no existing tool does it.
10. **Executor-generic functions.** Generated functions take any executor (pool, connection or transaction), so transactions are just `pool.begin()` and passing `&mut tx`.

## 3. How type-checking works per database

Every database tells you some things at prepare time and hides others. prepared should ask the real database for everything it can, and fill the gaps with its own SQL analysis.

| Need | Postgres | SQLite | MySQL |
|---|---|---|---|
| Result column types | Prepare (RowDescription) | `sqlite3_column_decltype`; weak unless tables are `STRICT` | Prepare (column definitions) |
| Param types | Prepare (ParameterDescription) | **Not given**: must infer | **Not useful** (params come back untyped): must infer |
| Column origin | Table OID + attnum | `sqlite3_column_table_name/origin_name` | org_table/org_name |
| Nullability | `pg_attribute.attnotnull` for direct columns; outer joins/expressions need analysis | `notnull` from `pragma table_info` for direct columns; expressions need analysis | `NOT_NULL` flag on result columns (reasonably reliable) |
| Needs a server | Yes (or container) | No, in-memory | Yes (or container) |
| `RETURNING` | Yes | Yes (3.35+) | No (MariaDB has it); use `LAST_INSERT_ID()` |

So the core is a **hybrid checker**:
- Prepare each query against a DB built from the app's migrations to get result columns, origins and anything else the DB reports.
- Parse the query (`sqlparser-rs`, which has Postgres, SQLite and MySQL dialects; optionally `pg_query.rs` for exact Postgres parsing) to infer param types from where each param is used (`col = :x`, `INSERT INTO t (col) VALUES (:x)`, `LIMIT :n`), and to work out nullability through `LEFT JOIN`, `COALESCE`, aggregates, `CASE` and so on.
- Anything still unknown is an error asking for an override, never a silent guess.

Avoid sqlx's SQLite bytecode-walking approach. It breaks on query-plan changes, which is how `ORDER BY` ends up changing a type.

## 4. Runtime driver

Generated code has to call some driver. Options:

- **sqlx as a runtime only (recommended for v1).** Use `sqlx::query_with`/`Executor`, but not its macros. One dependency covers all three databases, pools and transactions, and Mastiff's design already assumes sqlx-style stores as a fallback. Cost: sqlx's runtime overhead and its type-mapping traits.
- **Native drivers per DB** (`tokio-postgres`, `rusqlite`, `mysql_async`). Faster and closer to Cornucopia, but three different pool, transaction and type stories, and `rusqlite` is sync.
- **Own thin driver trait over native drivers.** Most control, most work. Worth it later if sqlx becomes a constraint, and the generated API can stay the same.

## 5. Query file format

Keep the format the June README already describes for sqeel, since it matches sqlc and is familiar:

```sql
-- name: find_user_by_email :opt
-- returns: User
SELECT id, email, password_hash, created_at
FROM users
WHERE email = :email;

-- name: list_sessions :many
SELECT token_hash, created_at, last_seen_at, ip?   -- force nullable
FROM mastiff_sessions
WHERE user_id = :user_id
ORDER BY last_seen_at DESC;

-- name: delete_sessions_for_user :exec
DELETE FROM mastiff_sessions WHERE user_id = :user_id;
```

Kinds: `:one` (exactly one row, error otherwise), `:opt` (`Option<Row>`), `:many` (`Vec<Row>`), `:stream` (row stream), `:exec` (rows affected). Generated shape, roughly:

```rust
pub async fn find_user_by_email<'e, E: Executor<'e>>(e: E, email: &str) -> Result<Option<User>>;
```

Plus a config file (`prepared.toml`) for type overrides (e.g. `inet` → `std::net::IpAddr`, Postgres enums → Rust enums, `timestamptz`/SQLite `INTEGER` → `OffsetDateTime`), derives on row structs, and the migrations path.

## 6. Suggested build order

1. Format parser + codegen for Postgres only, using real prepare + `pg_attribute` nullability, on sqlx runtime. Mastiff's Postgres store is the first user.
2. Offline cache and the `prepared check` / `prepared generate` CLI.
3. SQLite: in-memory migrations, param-type inference from the parse tree.
4. MySQL, reusing the inference from step 3.
5. Cross-database query sets (shared traits), `IN`-list expansion, bulk insert helpers.
6. Editor support (LSP over the checker) once the core is stable.

## 7. Open questions for Ben

1. Runtime: sqlx-as-runtime for v1 (recommended), or native drivers from the start?
2. Keep the `-- name: X :kind` format from sqeel (recommended), or switch to Cornucopia's `--!` syntax?
3. Is a live Postgres/MySQL (via `DATABASE_URL` or a container) acceptable when regenerating, given the offline cache means builds and CI never need one?
4. Should cross-database query sets (section 2, point 9) be in v1? They would let Mastiff ship one store instead of three.

## Sources

- Cornucopia: https://github.com/cornucopia-rs/cornucopia (1.0 merged Clorinde back in)
- Clorinde (archived 2026-05-21): https://github.com/halcyonnouveau/clorinde
- sqlx SQLite nullability issue: https://github.com/launchbadge/sqlx/issues/1126
- SQLite `sqlite3_column_decltype`: https://sqlite.org/c3ref/column_decltype.html
- sqlx-gen: https://docs.rs/crate/sqlx-gen/latest
- keelson: https://docs.rs/crate/keelson-gen/0.1.1/source/README.md
- sqlc, PgTyped, and the Postgres/MySQL wire-protocol prepare behaviour are described from prior knowledge, not re-checked today.
