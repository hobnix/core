//! `#[derive(Args)]`: the argument schema and the reader of a struct whose named fields are the positional arguments of a command.

use proc_macro2::TokenStream;
use quote::quote;
use syn::{Data, DeriveInput, Error, Expr, Fields, Lit, Meta, Result, Type};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Required,
    Optional,
    Rest,
}

/// The kind of a field by its type, and the type a value is read as (`Option<u32>` and `Vec<u32>` are read as `u32`).
fn kind_of(ty: &Type) -> (Kind, String) {
    let tokens = |t: &dyn quote::ToTokens| quote!(#t).to_string().replace(' ', "");
    if let Type::Path(p) = ty
        && p.qself.is_none()
        && let Some(last) = p.path.segments.last()
        && let syn::PathArguments::AngleBracketed(a) = &last.arguments
        && let [syn::GenericArgument::Type(inner)] = a.args.iter().collect::<Vec<_>>().as_slice()
    {
        if last.ident == "Option" {
            return (Kind::Optional, tokens(inner));
        }
        if last.ident == "Vec" {
            return (Kind::Rest, tokens(inner));
        }
    }
    (Kind::Required, tokens(ty))
}

/// The doc comment of a field as one line.
fn help_of(attrs: &[syn::Attribute]) -> String {
    let lines: Vec<String> = attrs
        .iter()
        .filter_map(|a| match &a.meta {
            Meta::NameValue(nv) if nv.path.is_ident("doc") => match &nv.value {
                Expr::Lit(e) => match &e.lit {
                    Lit::Str(s) => Some(s.value().trim().to_owned()),
                    _ => None,
                },
                _ => None,
            },
            _ => None,
        })
        .collect();
    lines
        .join(" ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// The schema entry and the read of field number `i`, and its kind; `before` is the kind of the field before it.
fn field(f: &syn::Field, i: usize, before: Kind) -> Result<(TokenStream, TokenStream, Kind)> {
    let Some(ident) = &f.ident else {
        return Err(Error::new_spanned(f, "Args needs named fields"));
    };
    let (kind, type_name) = kind_of(&f.ty);
    if before == Kind::Rest {
        return Err(Error::new_spanned(
            ident,
            "a Vec field takes the rest of the arguments, so it must be the last field",
        ));
    }
    if before == Kind::Optional && kind == Kind::Required {
        return Err(Error::new_spanned(
            ident,
            "a required field cannot come after an Option field",
        ));
    }
    let raw = ident.to_string();
    let name = raw.strip_prefix("r#").unwrap_or(&raw).replace('_', "-");
    let help = help_of(&f.attrs);
    let (variant, read) = match kind {
        Kind::Required => (quote!(Required), quote!(required)),
        Kind::Optional => (quote!(Optional), quote!(optional)),
        Kind::Rest => (quote!(Rest), quote!(rest)),
    };
    let p = quote!(::hobnix_pkg_command::__private);
    Ok((
        quote!(#p::arg(#name, #p::ArgKind::#variant, #type_name, #help)),
        quote!(#ident: #p::#read(argv, #i, #name)?),
        kind,
    ))
}

fn expand_checked(input: TokenStream) -> Result<TokenStream> {
    let d: DeriveInput = syn::parse2(input)?;
    if !d.generics.params.is_empty() {
        return Err(Error::new_spanned(
            &d.generics,
            "Args has no generic parameters",
        ));
    }
    let fields = match &d.data {
        Data::Struct(s) => match &s.fields {
            Fields::Named(n) => n.named.iter().collect::<Vec<_>>(),
            Fields::Unit => Vec::new(),
            Fields::Unnamed(u) => {
                return Err(Error::new_spanned(
                    u,
                    "Args needs named fields: the names are the argument names",
                ));
            }
        },
        _ => return Err(Error::new_spanned(&d.ident, "Args goes on a struct")),
    };
    let p = quote!(::hobnix_pkg_command::__private);
    let (mut specs, mut reads, mut last) = (Vec::new(), Vec::new(), Kind::Required);
    for (i, f) in fields.iter().enumerate() {
        let (spec, read, kind) = field(f, i, last)?;
        last = kind;
        specs.push(spec);
        reads.push(read);
    }
    let ident = &d.ident;
    let body = if matches!(&d.data, Data::Struct(s) if matches!(s.fields, Fields::Unit)) {
        quote!(Self)
    } else {
        quote!(Self { #(#reads),* })
    };
    Ok(quote! {
        impl #p::Args for #ident {
            const SPEC: &'static [#p::ArgSpec] = &[#(#specs),*];
            fn parse(argv: &[::std::string::String]) -> ::core::result::Result<Self, #p::Failure> {
                #p::check_count(argv, Self::SPEC)?;
                ::core::result::Result::Ok(#body)
            }
        }
    })
}

pub(crate) fn expand(input: TokenStream) -> TokenStream {
    expand_checked(input).unwrap_or_else(Error::into_compile_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_fields_in_order_with_their_kind_and_help() {
        let out = expand(quote! {
            struct A {
                /// the user
                user_name: String,
                /// minutes
                ///   watched
                minutes: Option<u32>,
                titles: Vec<String>,
            }
        })
        .to_string();
        assert!(out.contains("arg (\"user-name\" , :: hobnix_pkg_command :: __private :: ArgKind :: Required , \"String\" , \"the user\")"), "{out}");
        assert!(out.contains("\"u32\" , \"minutes watched\""), "{out}");
        assert!(out.contains("rest (argv , 2usize , \"titles\")"), "{out}");
    }

    #[test]
    fn refused_input_is_a_compile_error() {
        for (input, want) in [
            (
                quote!(
                    struct A {
                        a: Vec<String>,
                        b: String,
                    }
                ),
                "must be the last field",
            ),
            (
                quote!(
                    struct A {
                        a: Option<String>,
                        b: String,
                    }
                ),
                "cannot come after",
            ),
            (
                quote!(
                    struct A(String);
                ),
                "named fields",
            ),
            (
                quote!(
                    enum A {
                        X,
                    }
                ),
                "goes on a struct",
            ),
            (
                quote!(
                    struct A<T> {
                        a: T,
                    }
                ),
                "no generic",
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
