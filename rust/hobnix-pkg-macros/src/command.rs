//! `#[command(...)]`: keeps the function and adds a hidden `Command` constant beside it, which `commands!` lists.

use proc_macro2::{Span, TokenStream};
use quote::{format_ident, quote};
use syn::parse::Parser;
use syn::spanned::Spanned;
use syn::{Error, FnArg, Ident, ItemFn, LitInt, LitStr, Result, ReturnType, Type};

use crate::text;

/// The name of the constant `#[command]` puts beside the function `ident`; `commands!` names it the same way.
pub(crate) fn const_name(ident: &Ident) -> Ident {
    let name = ident.to_string();
    let name = name.strip_prefix("r#").unwrap_or(&name).to_uppercase();
    format_ident!("__HOBNIX_COMMAND_{}", name, span = ident.span())
}

/// The keys of the attribute.
#[derive(Default)]
struct Options {
    name: Option<String>,
    changes: Option<bool>,
    help: Option<String>,
    help_de: Option<String>,
    topic: Option<String>,
    timeout: Option<u32>,
    sys: Option<String>,
}

fn once<T>(slot: &mut Option<T>, value: T, span: Span, key: &str) -> Result<()> {
    if slot.is_some() {
        return Err(Error::new(span, format!("{key} is given twice")));
    }
    *slot = Some(value);
    Ok(())
}

fn parse_options(attr: TokenStream) -> Result<Options> {
    let mut o = Options::default();
    let parser = syn::meta::parser(|meta| {
        let span = meta.path.span();
        let key = meta
            .path
            .get_ident()
            .map(ToString::to_string)
            .unwrap_or_default();
        match key.as_str() {
            "name" => once(&mut o.name, text::words(&meta.value()?.parse::<LitStr>()?)?, span, "name"),
            "reads" | "changes" => once(&mut o.changes, key == "changes", span, "reads or changes"),
            "help" => once(&mut o.help, text::help(&meta.value()?.parse::<LitStr>()?)?, span, "help"),
            "help_de" => once(&mut o.help_de, text::help(&meta.value()?.parse::<LitStr>()?)?, span, "help_de"),
            "topic" => once(&mut o.topic, text::word(&meta.value()?.parse::<LitStr>()?, "topic")?, span, "topic"),
            "sys" => once(&mut o.sys, text::help(&meta.value()?.parse::<LitStr>()?)?, span, "sys"),
            "timeout" => {
                let lit: LitInt = meta.value()?.parse()?;
                let secs: u32 = lit.base10_parse()?;
                if !(1..=3600).contains(&secs) {
                    return Err(Error::new(lit.span(), "timeout is a number of seconds from 1 to 3600"));
                }
                once(&mut o.timeout, secs, span, "timeout")
            }
            _ => Err(meta.error("unknown key; the keys are name, reads, changes, help, help_de, topic, timeout and sys")),
        }
    });
    parser.parse2(attr)?;
    Ok(o)
}

/// The `Row` constructors of the command's rows.
fn rows(o: &Options) -> Result<Vec<TokenStream>> {
    let missing = |what: &str| Error::new(Span::call_site(), format!("#[command] needs {what}"));
    let changes = o.changes.ok_or_else(|| missing("reads or changes"))?;
    let help = o.help.as_deref().ok_or_else(|| missing("help = \"...\""))?;
    let access = if changes { "changes" } else { "reads" };
    let timeout = o
        .timeout
        .map(|t| format!(",timeout:{t}"))
        .unwrap_or_default();
    let topic = o
        .topic
        .as_ref()
        .map(|t| format!("topic:{t},"))
        .unwrap_or_default();
    let user_flags = format!("{topic}{access}{timeout},proto");
    let help_de = o.help_de.as_deref().unwrap_or("-");
    let mut out =
        vec![quote!(::hobnix_pkg_command::__private::Row::user(#help, #help_de, #user_flags))];
    if let Some(sys) = &o.sys {
        let sys_flags = format!("{access}{timeout},proto");
        out.push(quote!(::hobnix_pkg_command::__private::Row::sys(#sys, #sys_flags)));
    }
    Ok(out)
}

/// The type of the arguments (the second parameter, `()` without one), after checking the signature.
fn args_type(f: &ItemFn) -> Result<Type> {
    let sig = &f.sig;
    if let Some(a) = &sig.asyncness {
        return Err(Error::new_spanned(a, "a command is not async"));
    }
    if !sig.generics.params.is_empty() || sig.generics.where_clause.is_some() {
        return Err(Error::new_spanned(
            &sig.generics,
            "a command has no generic parameters",
        ));
    }
    if let ReturnType::Default = sig.output {
        return Err(Error::new_spanned(
            &sig.ident,
            "a command returns Result<Success, E> with E: Into<Failure>",
        ));
    }
    let typed: Vec<&syn::PatType> = sig
        .inputs
        .iter()
        .map(|a| match a {
            FnArg::Typed(t) => Ok(t),
            FnArg::Receiver(r) => Err(Error::new_spanned(
                r,
                "a command is a function, not a method",
            )),
        })
        .collect::<Result<_>>()?;
    match typed.as_slice() {
        [_] => Ok(syn::parse_quote!(())),
        [_, args] | [_, args, _] => Ok((*args.ty).clone()),
        _ => Err(Error::new(
            sig.paren_token.span.join(),
            "a command takes (ctx: &dyn Ctx), (ctx: &dyn Ctx, args: A) or (ctx: &dyn Ctx, args: A, req: &Request)",
        )),
    }
}

fn expand_checked(attr: TokenStream, f: &ItemFn) -> Result<TokenStream> {
    let o = parse_options(attr)?;
    let words = o
        .name
        .clone()
        .ok_or_else(|| Error::new(Span::call_site(), "#[command] needs name = \"...\""))?;
    let rows = rows(&o)?;
    let args_ty = args_type(f)?;
    let ident = &f.sig.ident;
    let call = match f.sig.inputs.len() {
        1 => quote!(#ident(ctx)),
        2 => quote!(#ident(ctx, args)),
        _ => quote!(#ident(ctx, args, req)),
    };
    let vis = &f.vis;
    let name = const_name(ident);
    let p = quote!(::hobnix_pkg_command::__private);
    Ok(quote! {
        #f
        #[doc(hidden)]
        #vis const #name: #p::Command = #p::Command::new(#words, &[#(#rows),*], <#args_ty as #p::Args>::SPEC, {
            fn call(req: &#p::Request, ctx: &dyn #p::Ctx) -> ::core::result::Result<#p::Success, #p::Failure> {
                let args: #args_ty = #p::parse_for(&req.argv, #words)?;
                let _ = &args;
                ::core::result::Result::map_err(#call, ::core::convert::Into::into)
            }
            call
        });
    })
}

/// The function and its constant, or the function and the error (so the function's own errors still show).
pub(crate) fn expand(attr: TokenStream, item: TokenStream) -> TokenStream {
    let f: ItemFn = match syn::parse2(item.clone()) {
        Ok(f) => f,
        Err(e) => {
            let e = Error::new(e.span(), "#[command] goes on a function");
            return item.into_iter().chain(e.into_compile_error()).collect();
        }
    };
    match expand_checked(attr, &f) {
        Ok(t) => t,
        Err(e) => {
            let err = e.into_compile_error();
            quote!(#f #err)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn expanded(attr: TokenStream, item: TokenStream) -> String {
        expand(attr, item).to_string()
    }

    #[test]
    fn makes_the_rows_and_the_constant() {
        let out = expanded(
            quote!(
                name = "status",
                reads,
                help = "show it",
                help_de = "zeigt es",
                topic = "apps",
                timeout = 90,
                sys = "as data"
            ),
            quote!(
                fn status(ctx: &dyn Ctx, args: StatusArgs) -> Result<Success, Failure> {
                    todo()
                }
            ),
        );
        assert!(out.contains("const __HOBNIX_COMMAND_STATUS"), "{out}");
        assert!(
            out.contains("\"topic:apps,reads,timeout:90,proto\""),
            "{out}"
        );
        assert!(
            out.contains("Row :: sys (\"as data\" , \"reads,timeout:90,proto\")"),
            "{out}"
        );
        assert!(out.contains("status (ctx , args)"), "{out}");
    }

    #[test]
    fn without_arguments_the_type_is_unit() {
        let out = expanded(
            quote!(name = "list", changes, help = "x"),
            quote!(
                fn list(ctx: &dyn Ctx) -> Result<Success, Failure> {
                    x
                }
            ),
        );
        assert!(out.contains("< () as"), "{out}");
        assert!(out.contains("\"-\" , \"changes,proto\""), "{out}");
    }

    #[test]
    fn a_refused_key_is_a_compile_error_not_a_panic() {
        let f = quote!(
            fn f(ctx: &dyn Ctx) -> Result<Success, Failure> {
                x
            }
        );
        for (attr, want) in [
            (quote!(reads, help = "x"), "needs name"),
            (quote!(name = "a", help = "x"), "needs reads or changes"),
            (quote!(name = "a", reads), "needs help"),
            (
                quote!(name = "a", reads, changes, help = "x"),
                "given twice",
            ),
            (
                quote!(name = "A", reads, help = "x"),
                "the name must be words",
            ),
            (
                quote!(name = "a", reads, help = "x", timeout = 0),
                "1 to 3600",
            ),
            (
                quote!(name = "a", reads, help = "x", colour = "red"),
                "unknown key",
            ),
        ] {
            let out = expanded(attr, f.clone());
            assert!(
                out.contains("compile_error") && out.contains(want),
                "{want}: {out}"
            );
        }
    }

    #[test]
    fn a_refused_function_is_a_compile_error_not_a_panic() {
        for (item, want) in [
            (
                quote!(
                    async fn f(ctx: &dyn Ctx) -> Result<Success, Failure> {
                        x
                    }
                ),
                "not async",
            ),
            (
                quote!(
                    fn f<T>(ctx: &dyn Ctx) -> Result<Success, Failure> {
                        x
                    }
                ),
                "no generic",
            ),
            (
                quote!(
                    fn f(ctx: &dyn Ctx) {}
                ),
                "returns Result",
            ),
            (
                quote!(
                    fn f() -> Result<Success, Failure> {
                        x
                    }
                ),
                "a command takes",
            ),
            (
                quote!(
                    struct S;
                ),
                "goes on a function",
            ),
        ] {
            let out = expanded(quote!(name = "a", reads, help = "x"), item);
            assert!(
                out.contains("compile_error") && out.contains(want),
                "{want}: {out}"
            );
        }
    }
}
