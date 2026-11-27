//! Service layer: typed inputs and results, no terminal output (docs/adr/0001-rust-strangler.md).

pub mod db;
pub mod error;
pub mod events;
pub mod jobs;
pub mod log;
pub mod pair;
pub mod pair_host;
pub mod secret;
pub mod secrets;

pub use error::{EXIT_MISSING, EXIT_OK, EXIT_REFUSED, Error, Result};
pub use secret::Secret;

/// Version of this build of the Rust part.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_not_empty() {
        assert!(!version().is_empty());
    }
}
