//! One credential per provider (hobnix/core#1135): each row reads only its own file. One test only: it sets $CREDENTIALS_DIRECTORY for the process.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)] // test code: a failed unwrap is the failure
use hobnix_ext_sdk::{integrations, service};

#[test]
fn one_credential_per_provider() {
    let dir = std::env::temp_dir().join(format!("hs-sdk-cred-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("integration-media-jellyfin"), "JELLY\n").unwrap();
    std::fs::write(dir.join("integration-media-radarr"), "RADAR \n").unwrap();
    std::fs::write(dir.join("integration-media"), "OLD\n").unwrap();
    std::env::set_var("CREDENTIALS_DIRECTORY", &dir);

    assert_eq!(
        service::credential_for("media", "jellyfin").as_deref(),
        Some("JELLY")
    );
    assert_eq!(
        service::credential_for("media", "radarr").as_deref(),
        Some("RADAR")
    );
    assert!(service::credential_for("media", "sonarr").is_none());
    assert!(service::credential_for("media", "../jellyfin").is_none());

    let rows = integrations::parse(
        "radarr\tmedia\trecipe\thttp://x\t/k\t-\tX-Api-Key\nsonarr\tmedia\trecipe\t-\t-\t-\t-\n",
    );
    assert_eq!(rows[0].credential_name(), "integration-media-radarr");
    assert_eq!(rows[0].credential().as_deref(), Some("RADAR"));
    assert!(rows[1].credential().is_none());

    #[allow(deprecated)]
    {
        assert_eq!(service::credential("media").as_deref(), Some("OLD"));
    }
    std::fs::remove_dir_all(&dir).unwrap();
}
