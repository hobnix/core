//! The checks of the texts that go into a `commands.tsv` row: one tab-separated line, so no tab, line break or NUL.

use syn::{Error, LitStr, Result};

/// A help text: not empty, not `-` (that means "none" in the row), no tab, line break or NUL.
pub(crate) fn help(lit: &LitStr) -> Result<String> {
    let s = lit.value();
    if s.trim().is_empty() || s == "-" {
        return Err(Error::new(
            lit.span(),
            "the help text must not be empty or -",
        ));
    }
    if s.contains(['\t', '\n', '\r', '\0']) {
        return Err(Error::new(
            lit.span(),
            "the help text must be one line without tabs",
        ));
    }
    Ok(s)
}

/// One word: a lower-case letter or digit first, then letters, digits and `-`.
pub(crate) fn is_word(w: &str) -> bool {
    let mut chars = w.chars();
    chars
        .next()
        .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// Command words: one or more words separated by one space.
pub(crate) fn words(lit: &LitStr) -> Result<String> {
    let s = lit.value();
    if s.split(' ').all(is_word) {
        Ok(s)
    } else {
        Err(Error::new(
            lit.span(),
            "the name must be words of a-z, 0-9 and -, separated by one space",
        ))
    }
}

/// One word (a topic or a package name).
pub(crate) fn word(lit: &LitStr, what: &str) -> Result<String> {
    let s = lit.value();
    if is_word(&s) {
        Ok(s)
    } else {
        Err(Error::new(
            lit.span(),
            format!("{what} must be one word of a-z, 0-9 and -"),
        ))
    }
}

/// The program of a package: `@/` and a relative path of letters, digits, `.`, `_`, `-` and `/`, without `..`.
pub(crate) fn script(lit: &LitStr) -> Result<String> {
    let s = lit.value();
    let ok = s.strip_prefix("@/").is_some_and(|p| {
        !p.is_empty()
            && p.split('/')
                .all(|part| !part.is_empty() && part != "." && part != "..")
            && p.chars()
                .all(|c| c.is_ascii_alphanumeric() || "._-/".contains(c))
    });
    if ok {
        Ok(s)
    } else {
        Err(Error::new(
            lit.span(),
            "script must be @/<path in the package>, as in commands.tsv",
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proc_macro2::Span;

    fn lit(s: &str) -> LitStr {
        LitStr::new(s, Span::call_site())
    }

    #[test]
    fn refuses_texts_that_break_a_row() {
        assert!(help(&lit("show it")).is_ok());
        for bad in ["", " ", "-", "a\tb", "a\nb", "a\0b"] {
            assert!(help(&lit(bad)).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn checks_words_and_scripts() {
        assert!(words(&lit("record session")).is_ok());
        for bad in ["", "Status", "a  b", " a", "-a", "a_b", "<x>"] {
            assert!(words(&lit(bad)).is_err(), "{bad:?}");
        }
        assert!(script(&lit("@/bin/demo")).is_ok());
        for bad in ["bin/demo", "@/", "@/../x", "@/a//b", "@/a b", "@/./a"] {
            assert!(script(&lit(bad)).is_err(), "{bad:?}");
        }
    }
}
