//! rusqlite is synchronous; every connection runs on its own worker thread (tokio-rusqlite or equivalent).
pub mod codec;
pub mod executor;
pub mod transaction;
