//! The integration listing of the core: `hs pkg integrations [--only <name>] <available package names...>` prints one tab-separated
//! row per integration block (package, integration, source, api_url, key_file, extras, key_header); an empty field is `-`.
//! [`parse`] turns that text into typed rows. How the extension gets the text (runs `hs`, or reads a file the core wrote) is its business.
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub struct Integration {
    pub package: String,
    pub integration: String,
    /// Kind of the package (`recipe`, `extension`, ...).
    pub source: String,
    /// Where the API is (`http://127.0.0.1:8096`); `None` when the core could not resolve `{port}`.
    pub api_url: Option<String>,
    pub key_file: Option<String>,
    /// The `k=v` pairs beyond the common fields.
    pub extras: BTreeMap<String, String>,
    /// Name of the HTTP header that carries the key (`X-Emby-Token`); `None` when the block names none.
    pub key_header: Option<String>,
}

/// Rows of `hs pkg integrations`. Lines with fewer than 6 fields are skipped (the listing had 6 columns before key_header was added,
/// so a 6-field line is accepted with `key_header` `None`); blank lines too.
pub fn parse(text: &str) -> Vec<Integration> {
    let opt = |s: &str| (s != "-" && !s.is_empty()).then(|| s.to_string());
    text.lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            if f.len() < 6 {
                return None;
            }
            let extras = opt(f[5])
                .map(|e| {
                    e.split(',')
                        .filter_map(|kv| kv.split_once('='))
                        .map(|(k, v)| (k.to_string(), v.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            Some(Integration {
                package: f[0].into(),
                integration: f[1].into(),
                source: f[2].into(),
                api_url: opt(f[3]),
                key_file: opt(f[4]),
                extras,
                key_header: f.get(6).and_then(|h| opt(h)),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows() {
        let t = "media-hub\tjellyfin\trecipe\thttp://127.0.0.1:8096\tjellyfin.key\ta=1,b=2\tX-Emby-Token\n\
                 media-hub\tplex\trecipe\t-\t-\t-\t-\n\nshort\tline\n\
                 old\tx\trecipe\thttp://h\t-\t-\n";
        let r = parse(t);
        assert_eq!(r.len(), 3);
        assert_eq!(r[0].key_header.as_deref(), Some("X-Emby-Token"));
        assert_eq!(r[0].extras["b"], "2");
        assert_eq!(r[1].api_url, None);
        assert!(r[1].extras.is_empty() && r[1].key_header.is_none());
        assert_eq!(r[2].key_header, None);
    }
}
