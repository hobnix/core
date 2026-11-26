//! The real `pair::Host`: the account and mount work is remote.sh (shell stays the glue), events go through scripts/lib/event.sh.

use crate::pair::{Host, Inner, Refusal};
use crate::{Error, Result, Secret};
use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};

#[derive(Debug)]
pub struct SystemHost {
    scripts: String,
}

impl SystemHost {
    pub fn from_env() -> Result<SystemHost> {
        let scripts = std::env::var("HS_SCRIPTS")
            .ok()
            .filter(|v| !v.is_empty())
            .ok_or_else(|| Error::Missing("HS_SCRIPTS is not set (run it through hs)".into()))?;
        Ok(SystemHost { scripts })
    }

    fn remote(&self) -> String {
        std::env::var("HS_REMOTE")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| format!("{}/remote.sh", self.scripts))
    }

    /// Runs remote.sh with `args` (names only, never a secret) and `stdin`; the exit code and stdout.
    fn run(&self, args: &[&str], stdin: Option<&str>) -> Option<(i32, String)> {
        let mut c = Command::new("bash");
        c.arg(self.remote())
            .args(args)
            .env("HS_PLAIN", "1")
            .env("HS_LANG", "en")
            .stdin(if stdin.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        let mut child = c.spawn().ok()?;
        if let (Some(text), Some(mut pipe)) = (stdin, child.stdin.take()) {
            pipe.write_all(text.as_bytes()).ok()?;
        }
        let out = child.wait_with_output().ok()?;
        Some((
            out.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&out.stdout).into_owned(),
        ))
    }
}

/// `tag<TAB>value` lines of `remote.sh grant`.
fn parse_grant(out: &str, server: &str, share: &str) -> Option<Inner> {
    let get = |k: &str| {
        out.lines()
            .find_map(|l| l.strip_prefix(k).and_then(|r| r.strip_prefix('\t')))
            .map(str::to_string)
    };
    Some(Inner {
        server: get("server").unwrap_or_else(|| server.to_string()),
        host: get("host")?,
        share: share.to_string(),
        login: get("login")?,
        domain: get("domain").unwrap_or_default(),
        password: Secret::new(get("password")?),
        hostkey: get("hostkey").unwrap_or_default(),
    })
}

impl Host for SystemHost {
    fn grant(
        &self,
        server: &str,
        share: &str,
        fingerprint: &str,
        bound: bool,
    ) -> std::result::Result<Inner, Refusal> {
        let b = if bound { "bound" } else { "free" };
        match self.run(&["grant", server, share, fingerprint, b], None) {
            Some((0, out)) => parse_grant(&out, server, share).ok_or(Refusal::Unavailable),
            Some((1, _)) => Err(Refusal::Unknown),
            _ => Err(Refusal::Unavailable),
        }
    }

    fn mount(&self, inner: &Inner) -> std::result::Result<(), Refusal> {
        let fp = crate::pair::fingerprint(&inner.hostkey).unwrap_or_else(|| "-".to_string());
        let args = [
            "accept-mount",
            &inner.server,
            &inner.host,
            &inner.share,
            &inner.login,
            &inner.domain,
            &fp,
        ];
        // the password goes on stdin, never into the arguments
        match self.run(&args, Some(&format!("{}\n", inner.password.expose()))) {
            Some((0, _)) => Ok(()),
            Some((1, _)) => Err(Refusal::Unknown),
            _ => Err(Refusal::Unavailable),
        }
    }

    fn event(&self, kind: &str, subject: &str, level: &str, payload: &Value) {
        let _ = Command::new("bash")
            .args([
                "-c",
                r#". "$1/lib/event.sh"; shift; event_emit "$@""#,
                "_",
                &self.scripts,
                kind,
                subject,
                "-",
                "--level",
                level,
                "--payload",
                &payload.to_string(),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grant_lines_are_read() {
        let i = parse_grant(
            "login\tremote-beta\ndomain\tHOME\nhost\talpha.local\npassword\tabc\nhostkey\tssh-ed25519 AAAA\n",
            "beta",
            "media",
        )
        .unwrap();
        assert_eq!(
            (i.login.as_str(), i.domain.as_str(), i.host.as_str()),
            ("remote-beta", "HOME", "alpha.local")
        );
        assert_eq!(i.password.expose(), "abc");
        assert!(parse_grant("login\tx\n", "beta", "m").is_none());
    }
}
