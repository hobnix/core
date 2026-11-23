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

### refused

A plain refuse "<text>" without a more exact code.

- Layer: script
- Text: The server did not do this.
- Fix: none

### run.timeout

The time limit of the web server passed before the command ended.

- Layer: run
- Text: The server stopped waiting. A start may still be running or be partly done: check Jobs and the page before you try again.
- Fix: none

### run.not-found

The command could not be started.

- Layer: run
- Text: The server could not run the command.
- Fix: none

### run.killed

The command ended because a signal stopped it.

- Layer: run
- Text: The command was stopped before it finished.
- Fix: none

### run.no-status

The command ended without a status line.

- Layer: run
- Text: The server could not do this.
- Fix: none

### vault.locked

The vault is closed and the step needs a secret in it.

- Layer: script
- Text: The vault is closed: unlock it first.
- Fix: `hs vault open`

### docker.off

Docker is not on or not running.

- Layer: script
- Text: Docker is not on or not running.
- Fix: none

### app.unknown

No app of that name exists.

- Layer: script
- Text: No such app was found.
- Fix: none

### name.invalid

A name is not in the allowed form.

- Layer: script
- Text: The name is not valid.
- Fix: none

### plan.changed

What the plan saw changed before it was applied.

- Layer: script
- Text: It changed meanwhile. Reload it and try again.
- Fix: none

### job.busy

The same job is running already.

- Layer: script
- Text: This is running already.
- Fix: none

### job.start-failed

The background job could not be started.

- Layer: script
- Text: The background job could not be started.
- Fix: none

### option.unknown

The command got an option it does not know.

- Layer: script
- Text: The command does not know this option.
- Fix: none

### args.unexpected

The command got more arguments than it takes.

- Layer: script
- Text: The command got more arguments than it takes.
- Fix: none

### confirm.missing

The typed name that confirms a destructive step is missing or wrong.

- Layer: script
- Text: Type the name of the thing to confirm.
- Fix: none

### disk.unknown

No disk of that name exists.

- Layer: script
- Text: No such disk was found.
- Fix: `hs sys pool disks`

### install.failed

An install job stopped at a step.

- Layer: script
- Text: The install stopped.
- Fix: none

### action.unknown

The command does not know the action it was given.

- Layer: script
- Text: The command does not know this action.
- Fix: none

<!-- END generated -->

Not tested on hardware yet.
