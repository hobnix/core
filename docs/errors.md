# Error codes

The names that a plan or start of a change can give for what went wrong, so the web interface can act on a code and never on English text. For developers; the design is in ADR 0028 (docs/adr/0028-error-codes.md).

## How it looks

A refused or failed plan or start prints `code<TAB><name>` beside `status` and `reason`. The `reason` stays English text and is what the terminal shows. Exit numbers keep three meanings: 0 = ok, 1 = refused, anything else = the run broke.

## The list

The one list is `scripts/lib/error-codes.tsv`: one line per code with the columns `code`, `layer`, `meaning`, `text` and `fix`. A script may print only a code that is listed there (`tests/error-codes.sh` fails otherwise). Add the line in the same change that adds the `refuse_code`, then run `python3 scripts/errors-doc-gen.py write`.

- `run` codes are set by the web server (scripts/web-serve.py) when the script gave no status line.
- `script` codes are printed by a change script through `refuse_code <code> [<reason>]` (scripts/lib/ui.sh): `status`, `reason` (the given text, else the text below), `fix` (when the list has one) and `code`. A plain `refuse "<text>"` means the code `refused`.
- A code is `<area>.<what>`, lower case, digits and `-`. It never changes meaning; a rename keeps the old name as an alias for one release.

<!-- BEGIN generated from scripts/lib/error-codes.tsv (python3 scripts/errors-doc-gen.py write) -->

| Code | Layer | Meaning | Text | Fix |
| --- | --- | --- | --- | --- |
| `refused` | script | A plain refuse "<text>" without a more exact code | The server did not do this. | none |
| `run.timeout` | run | The time limit of the web server passed before the command ended | The server stopped waiting. A start may still be running or be partly done: check Jobs and the page before you try again. | none |
| `run.not-found` | run | The command could not be started | The server could not run the command. | none |
| `run.killed` | run | The command ended because a signal stopped it | The command was stopped before it finished. | none |
| `run.no-status` | run | The command ended without a status line | The server could not do this. | none |
| `vault.locked` | script | The vault is closed and the step needs a secret in it | The vault is closed: unlock it first. | `hs vault open` |
| `docker.off` | script | Docker is not on or not running | Docker is not on or not running. | none |
| `app.unknown` | script | No app of that name exists | No such app was found. | none |
| `name.invalid` | script | A name is not in the allowed form | The name is not valid. | none |
| `plan.changed` | script | What the plan saw changed before it was applied | It changed meanwhile. Reload it and try again. | none |
| `job.busy` | script | The same job is running already | This is running already. | none |

<!-- END generated -->

Not tested on hardware yet.
