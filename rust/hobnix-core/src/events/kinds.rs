//! What the writer reads from files before its transaction: the level a kind has (scripts/lib/event-kinds.tsv and the declarations of
//! the packages) and the package kinds with their own retention. The reading rules of `scripts/lib/pkg_events.py`.

use super::{EventName, Level};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// The columns of a declaration file; one with a column less (no retention class) is an older one.
const COLUMNS: usize = 11;
const DEFAULT_RETENTION: &str = "audit";
const RETENTIONS: [&str; 3] = ["ephemeral", DEFAULT_RETENTION, "metric"];
const PACKAGE_NAME_MAX: usize = 41;
const KIND_SUFFIX_MAX: usize = 40;

/// Where the files are.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KindFiles {
    /// The scripts of the core: `lib/event-kinds.tsv` and `lib/pkg-events/`.
    pub scripts: PathBuf,
    /// The declarations `hs pkg` installed (`<state>/pkg-events`).
    pub installed: PathBuf,
}

/// A kind a package declares, as far as the writer needs it.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Declaration {
    kind: String,
    level: Level,
    retention: String,
}

/// The package kinds (`pkg.<package>.<kind>`) that are deleted before the general age limit.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(super) struct ShortLived {
    pub(super) ephemeral: Vec<String>,
    pub(super) metric: Vec<String>,
}

/// A lower-case word with `-`, not starting with it, of at most `longest` characters.
fn is_word(text: &str, longest: usize) -> bool {
    text.len() <= longest
        && !text.starts_with('-')
        && !text.is_empty()
        && text
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

fn is_package_name(text: &str) -> bool {
    is_word(text, PACKAGE_NAME_MAX) && text.starts_with(|c: char| c.is_ascii_lowercase())
}

/// The text with `\r\n` and `\r` read as line breaks, as python's text mode reads a file.
fn lines_of(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

fn declaration(line: &str, package: &str) -> Option<Declaration> {
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let mut columns: Vec<&str> = line.split('\t').collect();
    if columns.len() == COLUMNS - 1 {
        columns.push(DEFAULT_RETENTION);
    }
    let [kind, level, .., retention] = columns.as_slice() else {
        return None;
    };
    if columns.len() != COLUMNS || !RETENTIONS.contains(retention) {
        return None;
    }
    let suffix = kind.strip_prefix(&format!("pkg.{package}."))?;
    if !is_word(suffix, KIND_SUFFIX_MAX) {
        return None;
    }
    Some(Declaration {
        kind: (*kind).to_string(),
        level: Level::parse(level)?,
        retention: (*retention).to_string(),
    })
}

/// The declarations of one file: none when it cannot be read, an error when it is not UTF-8.
fn read_file(path: &Path, package: &str) -> Result<Vec<Declaration>, std::str::Utf8Error> {
    let Ok(bytes) = std::fs::read(path) else {
        return Ok(Vec::new());
    };
    let text = lines_of(std::str::from_utf8(&bytes)?);
    Ok(text
        .split('\n')
        .filter_map(|line| declaration(line, package))
        .collect())
}

/// The declaration files of one directory, by package name.
fn directory(path: &Path) -> Result<BTreeMap<String, Vec<Declaration>>, std::str::Utf8Error> {
    let mut found = BTreeMap::new();
    let Ok(entries) = std::fs::read_dir(path) else {
        return Ok(found);
    };
    for entry in entries.flatten() {
        let file = entry.file_name();
        let Some(package) = file.to_str().and_then(|n| n.strip_suffix(".tsv")) else {
            continue;
        };
        if is_package_name(package) {
            found.insert(package.to_string(), read_file(&entry.path(), package)?);
        }
    }
    Ok(found)
}

impl KindFiles {
    fn core_packages(&self) -> PathBuf {
        self.scripts.join("lib").join("pkg-events")
    }

    /// The level of `pkg.<package>.<kind>` as its package declares it. An installed file replaces the core copy of the same package.
    fn declared_level(&self, full: &str) -> Option<Level> {
        let (package, suffix) = full.strip_prefix("pkg.")?.split_once('.')?;
        if !is_package_name(package) || !is_word(suffix, KIND_SUFFIX_MAX) {
            return None;
        }
        let file = format!("{package}.tsv");
        let mut path = self.installed.join(&file);
        if !path.exists() {
            path = self.core_packages().join(&file);
        }
        let declarations = read_file(&path, package).ok()?;
        declarations
            .into_iter()
            .find(|d| d.kind == full)
            .map(|d| d.level)
    }

    /// The level of a kind: the list of the core, for a `pkg.*` kind what its package declares, else info.
    pub(super) fn level(&self, name: &EventName) -> Level {
        let full = name.to_string();
        let list = std::fs::read(self.scripts.join("lib").join("event-kinds.tsv"));
        let listed = list.ok().and_then(|bytes| {
            lines_of(&String::from_utf8_lossy(&bytes))
                .split('\n')
                .find_map(|line| {
                    let mut columns = line.split('\t');
                    (columns.next() == Some(full.as_str()))
                        .then(|| columns.next().and_then(Level::parse))
                        .flatten()
                })
        });
        listed
            .or_else(|| self.declared_level(&full))
            .unwrap_or(Level::Info)
    }

    /// The kinds with their own retention. One file that is not UTF-8 leaves both lists empty, as in state-db.py (`trim_events`).
    pub(super) fn short_lived(&self) -> ShortLived {
        let both = directory(&self.core_packages()).and_then(|mut all| {
            all.extend(directory(&self.installed)?);
            Ok(all)
        });
        let mut lists = ShortLived::default();
        for declaration in both.unwrap_or_default().into_values().flatten() {
            match declaration.retention.as_str() {
                "ephemeral" => lists.ephemeral.push(declaration.kind),
                "metric" => lists.metric.push(declaration.kind),
                _ => {}
            }
        }
        lists
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::tests::TempDir;

    fn row(kind: &str, level: &str, retention: &str) -> String {
        format!("{kind}\t{level}\t-\tL\t-\tm\t-\t-\t-\t-\t{retention}\n")
    }

    fn files(dir: &TempDir) -> KindFiles {
        let files = KindFiles {
            scripts: dir.0.join("scripts"),
            installed: dir.0.join("installed"),
        };
        std::fs::create_dir_all(files.core_packages()).expect("core dir");
        std::fs::create_dir_all(&files.installed).expect("installed dir");
        std::fs::write(
            files.scripts.join("lib").join("event-kinds.tsv"),
            "# kind\tlevel\njob.failed\terror\t-\tm\n",
        )
        .expect("list");
        files
    }

    fn name(text: &str) -> EventName {
        EventName::parse(text).expect("name")
    }

    #[test]
    fn the_level_comes_from_the_list_then_the_package_then_is_info() {
        let dir = TempDir::new("kinds-level");
        let files = files(&dir);
        let text = format!("# c\r\n{}", row("pkg.rapp.loud", "warn", "audit"));
        std::fs::write(files.installed.join("rapp.tsv"), text).expect("package");
        assert_eq!(files.level(&name("job.failed")), Level::Error);
        assert_eq!(files.level(&name("pkg.rapp.loud")), Level::Warn);
        assert_eq!(files.level(&name("pkg.rapp.other")), Level::Info);
        assert_eq!(files.level(&name("pkg.nosuch.kind")), Level::Info);
    }

    #[test]
    fn an_installed_file_replaces_the_core_copy_of_the_package() {
        let dir = TempDir::new("kinds-replace");
        let files = files(&dir);
        let old = "pkg.rapp.a\tinfo\t-\tL\t-\tm\t-\t-\t-\t-\n";
        std::fs::write(files.core_packages().join("rapp.tsv"), old).expect("core");
        std::fs::write(
            files.core_packages().join("other.tsv"),
            row("pkg.other.t", "info", "metric"),
        )
        .expect("core");
        std::fs::write(
            files.installed.join("rapp.tsv"),
            row("pkg.rapp.b", "info", "ephemeral"),
        )
        .expect("installed");
        let lists = files.short_lived();
        assert_eq!(lists.ephemeral, ["pkg.rapp.b"]);
        assert_eq!(lists.metric, ["pkg.other.t"]);
    }

    #[test]
    fn rows_that_do_not_fit_are_dropped() {
        for bad in [
            row("pkg.other.a", "info", "metric"),
            row("pkg.rapp.-a", "info", "metric"),
            row("pkg.rapp.a", "loud", "metric"),
            row("pkg.rapp.a", "info", "forever"),
            "pkg.rapp.a\tinfo\n".to_string(),
        ] {
            assert_eq!(declaration(bad.trim_end(), "rapp"), None, "{bad}");
        }
    }
}
