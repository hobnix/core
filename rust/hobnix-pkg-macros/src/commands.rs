//! `commands!(package = "demo", script = "@/bin/demo", status, sync)`: the list of commands, the table of rows built at compile time,
//! and the `Commands` value that dispatches.

use std::collections::BTreeSet;

use proc_macro2::{Span, TokenStream};
use quote::quote;
use syn::parse::{Parse, ParseStream, Parser};
use syn::punctuated::Punctuated;
use syn::{Error, Ident, LitStr, Path, PathArguments, Result, Token};

use crate::{command, text};

/// One entry: `key = "value"` or the path of a command function.
enum Entry {
    Key(Ident, LitStr),
    Command(Path),
}

impl Parse for Entry {
    fn parse(input: ParseStream<'_>) -> Result<Self> {
        if input.peek(Ident) && input.peek2(Token![=]) {
            let key: Ident = input.parse()?;
            input.parse::<Token![=]>()?;
            Ok(Entry::Key(key, input.parse()?))
        } else {
            Ok(Entry::Command(input.parse()?))
        }
    }
}

struct Input {
    package: String,
    script: String,
    commands: Vec<Path>,
}

fn parse_input(tokens: TokenStream) -> Result<Input> {
    let entries = Punctuated::<Entry, Token![,]>::parse_terminated.parse2(tokens)?;
    let (mut package, mut script, mut commands, mut seen) =
        (None, None, Vec::new(), BTreeSet::new());
    for e in entries {
        match e {
            Entry::Key(k, v) if k == "package" && package.is_none() => {
                package = Some(text::word(&v, "package")?);
            }
            Entry::Key(k, v) if k == "script" && script.is_none() => {
                script = Some(text::script(&v)?);
            }
            Entry::Key(k, _) if k == "package" || k == "script" => {
                return Err(Error::new(k.span(), format!("{k} is given twice")));
            }
            Entry::Key(k, _) => {
                return Err(Error::new(
                    k.span(),
                    "unknown key; the keys are package and script",
                ));
            }
            Entry::Command(p) => {
                let Some(last) = p.segments.last() else {
                    return Err(Error::new_spanned(&p, "expected a command function"));
                };
                if !matches!(last.arguments, PathArguments::None) {
                    return Err(Error::new_spanned(
                        &p,
                        "a command function has no generic arguments",
                    ));
                }
                if !seen.insert(last.ident.to_string()) {
                    return Err(Error::new_spanned(&p, "this command is listed twice"));
                }
                commands.push(p);
            }
        }
    }
    let missing = |what| Error::new(Span::call_site(), format!("commands! needs {what}"));
    let package = package.ok_or_else(|| missing("package = \"<name of the package>\""))?;
    let script = script.ok_or_else(|| missing("script = \"@/<path of the program>\""))?;
    if commands.is_empty() {
        return Err(missing("at least one command function"));
    }
    Ok(Input {
        package,
        script,
        commands,
    })
}

/// The path of the constant `#[command]` made beside the function at `path`.
fn const_path(path: &Path) -> Path {
    let mut p = path.clone();
    if let Some(last) = p.segments.last_mut() {
        last.ident = command::const_name(&last.ident);
    }
    p
}

fn expand_checked(tokens: TokenStream) -> Result<TokenStream> {
    let Input {
        package,
        script,
        commands,
    } = parse_input(tokens)?;
    let consts = commands.iter().map(const_path);
    let p = quote!(::hobnix_pkg_command::__private);
    Ok(quote! {{
        const __HOBNIX_LIST: &[#p::Command] = &[#(#consts),*];
        const __HOBNIX_LEN: usize = #p::table_len(__HOBNIX_LIST, #package, #script);
        #[used]
        static __HOBNIX_TABLE: [u8; __HOBNIX_LEN] = #p::table(__HOBNIX_LIST, #package, #script);
        #p::Commands::new(__HOBNIX_LIST, &__HOBNIX_TABLE, #script)
    }})
}

pub(crate) fn expand(tokens: TokenStream) -> TokenStream {
    expand_checked(tokens).unwrap_or_else(Error::into_compile_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_the_constants_of_the_functions() {
        let out = expand(quote!(
            package = "demo",
            script = "@/bin/demo",
            status,
            sub::r#sync
        ))
        .to_string();
        assert!(
            out.contains("[__HOBNIX_COMMAND_STATUS , sub :: __HOBNIX_COMMAND_SYNC]"),
            "{out}"
        );
        assert!(
            out.contains("table_len (__HOBNIX_LIST , \"demo\" , \"@/bin/demo\")"),
            "{out}"
        );
    }

    #[test]
    fn refused_input_is_a_compile_error() {
        for (input, want) in [
            (quote!(script = "@/bin/demo", status), "needs package"),
            (quote!(package = "demo", status), "needs script"),
            (
                quote!(package = "demo", script = "@/bin/demo"),
                "at least one command",
            ),
            (
                quote!(package = "demo", package = "x", script = "@/bin/demo", a),
                "given twice",
            ),
            (
                quote!(package = "Demo", script = "@/bin/demo", a),
                "package must be one word",
            ),
            (
                quote!(package = "demo", script = "bin/demo", a),
                "script must be",
            ),
            (
                quote!(package = "demo", script = "@/bin/demo", a, b::a),
                "listed twice",
            ),
            (
                quote!(package = "demo", script = "@/bin/demo", colour = "red", a),
                "unknown key",
            ),
            (
                quote!(package = "demo", script = "@/bin/demo", a::<u8>),
                "no generic",
            ),
            (
                quote!(package = "demo", script = "@/bin/demo", 42),
                "expected",
            ),
        ] {
            let out = expand(input).to_string();
            assert!(
                out.contains("compile_error") && out.contains(want),
                "{want}: {out}"
            );
        }
    }
}
