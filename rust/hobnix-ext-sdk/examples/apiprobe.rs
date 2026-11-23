//! Example: call the JSON API of an integration the way media-hub does. `apiprobe get <listing-file> <integration> <path>` takes the
//! row of the integration from a file with the output of `hs pkg integrations`, reads its key from `$CREDENTIALS_DIRECTORY`
//! (`integration-<name>`), sends it in the row's key header and answers with the JSON of the API. Plain http only (see
//! `hobnix_ext_sdk::http`).
//!
//!   cargo build --example apiprobe
//!   cargo build --release --target x86_64-unknown-linux-musl --example apiprobe   # static binary; `rustup target add` it first
use hobnix_ext_sdk::command::{run, Ctx, Failure, Request, Success};
use hobnix_ext_sdk::http::Client;
use hobnix_ext_sdk::{integrations, service};
use std::process::ExitCode;
use std::time::Duration;

fn handle(req: &Request, _ctx: &Ctx) -> Result<Success, Failure> {
    if req.words().as_slice() != ["get"] {
        return Err(Failure::not_found("no such command"));
    }
    let usage = || Failure::bad_request("usage: get <listing-file> <integration> </path>");
    let [file, name, path] = req.argv.as_slice() else {
        return Err(usage());
    };
    if !path.starts_with('/') {
        return Err(usage());
    }
    let text = std::fs::read_to_string(file)
        .map_err(|e| Failure::bad_request(format!("cannot read {file}: {e}")))?;
    let row = integrations::parse(&text)
        .into_iter()
        .find(|r| r.integration == *name)
        .ok_or_else(|| Failure::bad_request(format!("no integration {name} in the listing")))?;
    let base = row
        .api_url
        .ok_or_else(|| Failure::bad_request("the integration has no api_url"))?;
    let mut client = Client::new().timeout(Duration::from_secs(5));
    if let (Some(h), Some(key)) = (row.key_header, service::credential(name)) {
        client = client.header(h, key);
    }
    let data = client
        .get_json(&format!("{}{path}", base.trim_end_matches('/')))
        .map_err(|e| Failure::bad_request(e.to_string()))?;
    Ok(Success::data(data))
}

fn main() -> ExitCode {
    run(handle)
}
