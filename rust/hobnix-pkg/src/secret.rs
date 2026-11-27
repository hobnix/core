//! [`Secret`]: a value that must never reach a log line, an error or a terminal by accident.
use std::fmt;

/// A key or token. `Debug` and `Display` print `***`; [`Secret::expose`] is the only way to read the value. Not `Clone`: a copy is
/// made on purpose, with `Secret::new(s.expose())`.
pub struct Secret(String);

impl Secret {
    /// Wrap `value`.
    pub fn new(value: impl Into<String>) -> Self {
        Secret(value.into())
    }

    /// The value; call it only where the secret is really used (an http header, a hash).
    pub fn expose(&self) -> &str {
        &self.0
    }

    /// `true` for an empty value (a credential file that holds only whitespace).
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("***")
    }
}

impl fmt::Display for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("***")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_secret_is_never_printed() {
        let s = Secret::new("hunter2");
        assert_eq!(format!("{s}"), "***");
        assert_eq!(format!("{s:?}"), "***");
        assert_eq!(format!("{:?}", Some(&s)), "Some(***)");
        assert_eq!(s.expose(), "hunter2");
        assert!(!s.is_empty() && Secret::new("").is_empty());
    }
}
