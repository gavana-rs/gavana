//! `SessionStore`, `UserStore`, and `Authenticatable` traits; one backend per submodule.

pub mod memory;

#[cfg(feature = "postgres")]
pub mod postgres;

#[cfg(feature = "sqlite")]
pub mod sqlite;

#[cfg(feature = "mysql")]
pub mod mysql;
