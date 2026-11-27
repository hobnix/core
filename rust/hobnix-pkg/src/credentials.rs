//! The key of an integration, read from `$CREDENTIALS_DIRECTORY` (systemd credentials), never from argv or the environment.
use std::path::{Path, PathBuf};

use crate::Secret;

/// The key that the provider package `provider` holds for the integration `name` (declared as `integration:<name>` in `permissions`).
///
/// The core hands a confined service one systemd credential per provider, `integration-<name>-<provider>`, read here from
/// `$CREDENTIALS_DIRECTORY`. The provider is the `package` column of `hs pkg integrations` (or
/// [`crate::integrations::Integration::credential`]). Trailing whitespace is cut. `None` when there is no such credential (not declared,
/// the provider has no key, the key is locked or missing) or a name is not `[a-z0-9-]+`.
pub fn credential_for(name: &str, provider: &str) -> Option<Secret> {
    credential_in(&credentials_dir()?, name, provider)
}

/// `$CREDENTIALS_DIRECTORY`, read where a credential is asked for (the tests pass a folder to [`credential_in`] instead).
fn credentials_dir() -> Option<PathBuf> {
    std::env::var_os("CREDENTIALS_DIRECTORY").map(PathBuf::from)
}

fn valid_name(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
}

/// [`credential_for`] from the folder `dir`.
pub(crate) fn credential_in(dir: &Path, name: &str, provider: &str) -> Option<Secret> {
    if !valid_name(name) || !valid_name(provider) {
        return None;
    }
    let text = std::fs::read_to_string(dir.join(format!("integration-{name}-{provider}"))).ok()?;
    Some(Secret::new(text.trim_end()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::integrations::{Integration, parse};

    /// One credential per provider (hobnix/core#1135): each row reads only its own file. The folder is passed in, the environment of the
    /// test process is not changed (tests/ext-sdk-rust.sh covers `$CREDENTIALS_DIRECTORY` end to end).
    #[test]
    fn one_credential_per_provider() {
        let dir = std::env::temp_dir().join(format!("hs-pkg-cred-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("integration-media-jellyfin"), "JELLY\n").unwrap();
        std::fs::write(dir.join("integration-media-radarr"), "RADAR \n").unwrap();
        let read = |n: &str, p: &str| credential_in(&dir, n, p).map(|s| s.expose().to_owned());

        assert_eq!(read("media", "jellyfin").as_deref(), Some("JELLY"));
        assert_eq!(read("media", "radarr").as_deref(), Some("RADAR"));
        assert!(read("media", "sonarr").is_none());
        assert!(read("media", "../jellyfin").is_none());
        assert!(read("", "jellyfin").is_none());

        let rows = parse(
            "radarr\tmedia\trecipe\thttp://x\t/k\t-\tX-Api-Key\nsonarr\tmedia\trecipe\t-\t-\t-\t-\n",
        );
        assert_eq!(rows[0].credential_name(), "integration-media-radarr");
        let of = |r: &Integration| read(&r.integration, &r.package);
        assert_eq!(of(&rows[0]).as_deref(), Some("RADAR"));
        assert!(of(&rows[1]).is_none());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
