//! The arguments of a command written with [`command`](crate::command): a struct whose fields are read from the request's `argv` in order.

use std::fmt::Write as _;
use std::str::FromStr;

use crate::Failure;

/// How often an argument may be given.
#[non_exhaustive]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArgKind {
    /// Exactly once (a field of any type that implements `FromStr`).
    Required,
    /// Once or not at all (an `Option<T>` field).
    Optional,
    /// Any number, all the remaining ones (a `Vec<T>` field; only the last field).
    Rest,
}

/// One argument of a command: the schema that help, completion and later the web forms read.
#[non_exhaustive]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArgSpec {
    /// The name (the field name, `_` written as `-`).
    pub name: &'static str,
    /// Required, optional or the rest.
    pub kind: ArgKind,
    /// The type a value is read as, as written in the struct (`u32`, `String`).
    pub type_name: &'static str,
    /// The doc comment of the field, or empty.
    pub help: &'static str,
}

/// The arguments of a command, read from the request's `argv`. Write `#[derive(Args)]` on a struct with named fields instead of an
/// implementation by hand: the fields are positional, a required one first, then `Option<T>` fields, then at most one `Vec<T>` as the last.
/// `()` is the argument type of a command that takes none.
pub trait Args: Sized {
    /// The arguments in the order they are read.
    const SPEC: &'static [ArgSpec];
    /// Read the arguments.
    ///
    /// # Errors
    /// A `bad_request` [`Failure`] when an argument is missing, one too many is given or a value cannot be read as its type.
    fn parse(argv: &[String]) -> Result<Self, Failure>;
}

/// No arguments: any argument is refused.
impl Args for () {
    const SPEC: &'static [ArgSpec] = &[];
    fn parse(argv: &[String]) -> Result<Self, Failure> {
        check_count(argv, Self::SPEC)
    }
}

/// `usage: <words> <required> [optional] [rest...]`.
pub(crate) fn usage(words: &str, spec: &[ArgSpec]) -> String {
    let mut out = format!("usage: {words}");
    for a in spec {
        let _ = match a.kind {
            ArgKind::Required => write!(out, " <{}>", a.name),
            ArgKind::Optional => write!(out, " [{}]", a.name),
            ArgKind::Rest => write!(out, " [{}...]", a.name),
        };
    }
    out
}

/// At most 60 characters of a value in a message.
fn shown(value: &str) -> String {
    let mut s: String = value.chars().take(60).collect();
    if s.len() < value.len() {
        s.push_str("...");
    }
    s
}

fn read<T: FromStr>(value: &str, name: &str) -> Result<T, Failure> {
    let type_name = std::any::type_name::<T>().rsplit("::").next().unwrap_or("");
    value.parse().map_err(|_| {
        Failure::bad_request(format!(
            "argument {name}: cannot read '{}' as {type_name}",
            shown(value)
        ))
    })
}

/// Not more arguments than `spec` takes.
#[doc(hidden)]
pub fn check_count(argv: &[String], spec: &[ArgSpec]) -> Result<(), Failure> {
    let has_rest = spec.iter().any(|a| a.kind == ArgKind::Rest);
    if !has_rest && argv.len() > spec.len() {
        return Err(Failure::bad_request("too many arguments"));
    }
    Ok(())
}

/// The required argument at `index`.
#[doc(hidden)]
pub fn required<T: FromStr>(argv: &[String], index: usize, name: &str) -> Result<T, Failure> {
    match argv.get(index) {
        Some(v) => read(v, name),
        None => Err(Failure::bad_request(format!("missing argument {name}"))),
    }
}

/// The optional argument at `index`.
#[doc(hidden)]
pub fn optional<T: FromStr>(
    argv: &[String],
    index: usize,
    name: &str,
) -> Result<Option<T>, Failure> {
    argv.get(index).map(|v| read(v, name)).transpose()
}

/// The arguments from `index` on.
#[doc(hidden)]
pub fn rest<T: FromStr>(argv: &[String], index: usize, name: &str) -> Result<Vec<T>, Failure> {
    argv.get(index..)
        .unwrap_or_default()
        .iter()
        .map(|v| read(v, name))
        .collect()
}

/// The arguments of the request, or `bad_request` with the usage line of the command appended.
#[doc(hidden)]
pub fn parse_for<A: Args>(argv: &[String], words: &str) -> Result<A, Failure> {
    A::parse(argv).map_err(|mut f| {
        let _ = write!(f.message, "; {}", usage(words, A::SPEC));
        f
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn argv(a: &[&str]) -> Vec<String> {
        a.iter().map(ToString::to_string).collect()
    }

    const SPEC: &[ArgSpec] = &[
        ArgSpec {
            name: "n",
            kind: ArgKind::Required,
            type_name: "u32",
            help: "",
        },
        ArgSpec {
            name: "label",
            kind: ArgKind::Optional,
            type_name: "String",
            help: "",
        },
    ];

    #[test]
    fn usage_marks_required_optional_and_rest() {
        let mut spec = SPEC.to_vec();
        spec.push(ArgSpec {
            name: "more",
            kind: ArgKind::Rest,
            type_name: "String",
            help: "",
        });
        assert_eq!(usage("count", &spec), "usage: count <n> [label] [more...]");
    }

    #[test]
    fn refuses_too_many_and_missing_and_unreadable_arguments() {
        assert_eq!(
            check_count(&argv(&["1", "a", "b"]), SPEC)
                .unwrap_err()
                .message,
            "too many arguments"
        );
        assert_eq!(
            required::<u32>(&argv(&[]), 0, "n").unwrap_err().message,
            "missing argument n"
        );
        let e = required::<u32>(&argv(&["x"]), 0, "n").unwrap_err();
        assert_eq!(e.message, "argument n: cannot read 'x' as u32");
        let long = "y".repeat(100);
        assert!(
            required::<u8>(&argv(&[&long]), 0, "n")
                .unwrap_err()
                .message
                .ends_with("y...' as u8")
        );
    }

    #[test]
    fn reads_optional_and_rest() {
        assert_eq!(optional::<String>(&argv(&["1"]), 1, "label").unwrap(), None);
        assert_eq!(
            rest::<u8>(&argv(&["1", "2", "3"]), 1, "more").unwrap(),
            vec![2, 3]
        );
        assert_eq!(
            rest::<u8>(&argv(&["1"]), 5, "more").unwrap(),
            Vec::<u8>::new()
        );
    }

    #[test]
    fn unit_takes_no_arguments_and_the_error_carries_the_usage() {
        assert!(parse_for::<()>(&argv(&[]), "list").is_ok());
        let e = parse_for::<()>(&argv(&["x"]), "list").unwrap_err();
        assert_eq!(e.message, "too many arguments; usage: list");
    }
}
