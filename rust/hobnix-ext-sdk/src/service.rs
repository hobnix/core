//! The 0.13 paths of `hobnix-pkg-service`: the message types are re-exported, [`Service`] keeps its `Result<(), String>` and [`run`]
//! adapts it to the new trait.
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use crate::Ctx;

pub use hobnix_pkg_service::{EventRow, Health, Init, Lang};

/// The 0.13 form of `hobnix_pkg_service::Service`: errors are `String`.
pub trait Service {
    /// Called once after `init`, before `ready`. An `Err` ends the process with status 1.
    fn start(&mut self, _init: &Init, _ctx: &dyn Ctx) -> Result<(), String> {
        Ok(())
    }
    /// Handle one event. `Ok` sends the `ack`; `Err` logs the reason and sends no ack.
    fn on_event(&mut self, _event: &EventRow, _ctx: &dyn Ctx) -> Result<(), String> {
        Ok(())
    }
    /// Called at startup and then every half `health_interval`.
    fn tick(&mut self, _ctx: &dyn Ctx) -> Health {
        Health::ok()
    }
}

/// An old [`Service`] as a new one; the text of an error stays the text of the log line and of the stderr line.
struct Adapter<S>(S);

impl<S: Service> hobnix_pkg_service::Service for Adapter<S> {
    fn start(&mut self, init: &Init, ctx: &dyn hobnix_pkg::Ctx) -> Result<(), hobnix_pkg::Error> {
        self.0.start(init, &ctx).map_err(hobnix_pkg::Error::from)
    }
    fn on_event(
        &mut self,
        event: &EventRow,
        ctx: &dyn hobnix_pkg::Ctx,
    ) -> Result<(), hobnix_pkg::Error> {
        self.0
            .on_event(event, &ctx)
            .map_err(hobnix_pkg::Error::from)
    }
    fn tick(&mut self, ctx: &dyn hobnix_pkg::Ctx) -> Health {
        self.0.tick(&ctx)
    }
}

/// Run the service against stdin/stdout (see `hobnix_pkg_service::run`).
#[deprecated(
    since = "0.14.0",
    note = "use hobnix_pkg_service::run (crates hobnix-pkg and hobnix-pkg-service); hobnix-ext-sdk is removed after 0.14"
)]
pub fn run(service: impl Service) -> ExitCode {
    hobnix_pkg_service::run(Adapter(service))
}

/// [`run`] over any reader and writer (for tests).
#[deprecated(
    since = "0.14.0",
    note = "use hobnix_pkg_service::run_with (crates hobnix-pkg and hobnix-pkg-service); hobnix-ext-sdk is removed after 0.14"
)]
pub fn run_with(
    input: impl BufRead + Send + 'static,
    output: impl Write + Send + 'static,
    service: impl Service,
) -> u8 {
    hobnix_pkg_service::run_with(input, output, Adapter(service))
}

/// The key that the provider package `provider` holds for the integration `name`, as a `String` (see
/// `hobnix_pkg::credentials::credential_for`, which returns a `Secret`).
#[deprecated(
    since = "0.14.0",
    note = "use hobnix_pkg::credentials::credential_for, which returns a Secret; hobnix-ext-sdk is removed after 0.14"
)]
pub fn credential_for(name: &str, provider: &str) -> Option<String> {
    hobnix_pkg::credentials::credential_for(name, provider).map(|s| s.expose().to_owned())
}

/// Deprecated since 0.13: the old one-name form `integration-<name>` (the first provider with a key, owner not told). Use
/// `hobnix_pkg::credentials::credential_for`, which names the provider. `None` when there is no such credential.
#[deprecated(note = "use credential_for(name, provider): the credential is one per provider")]
pub fn credential(name: &str) -> Option<String> {
    let dir = std::env::var_os("CREDENTIALS_DIRECTORY").map(PathBuf::from)?;
    legacy_credential_in(&dir, name)
}

fn legacy_credential_in(dir: &Path, name: &str) -> Option<String> {
    let valid = !name.is_empty()
        && name
            .chars()
            .all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'));
    if !valid {
        return None;
    }
    let text = std::fs::read_to_string(dir.join(format!("integration-{name}"))).ok()?;
    Some(text.trim_end().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_old_one_name_credential_reads_its_own_file() {
        let dir = std::env::temp_dir().join(format!("hs-ext-sdk-cred-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("integration-media"), "OLD\n").unwrap();
        assert_eq!(legacy_credential_in(&dir, "media").as_deref(), Some("OLD"));
        assert!(legacy_credential_in(&dir, "../media").is_none());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
