// Refused shapes of #[derive(Args)].
use hobnix_pkg_command::Args;

#[derive(Args)]
struct RestNotLast {
    names: Vec<String>,
    last: String,
}

#[derive(Args)]
struct RequiredAfterOptional {
    first: Option<String>,
    second: String,
}

#[derive(Args)]
struct Tuple(String);

#[derive(Args)]
enum NotAStruct {
    A,
}

fn main() {}
