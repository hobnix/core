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

### pkg.blueprint

hs pkg install was asked for a blueprint, which is applied and never installed.

- Layer: script
- Text: This is a blueprint: apply it instead of installing it.
- Fix: `hs blueprint apply <name>`

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

### integration.denied

The caller may not have the key of an integration.

- Layer: script
- Text: This package may not ask for that key.
- Fix: none

### integration.unknown

The named provider is not there or does not offer the integration.

- Layer: script
- Text: No such provider for this integration.
- Fix: `hs pkg integrations`

### integration.nokey

The provider has no key file to give.

- Layer: script
- Text: This provider has no key.
- Fix: `hs pkg integrations`

### binary.shape

A [[binary]] table of package.toml has a missing, unknown or malformed key.

- Layer: script
- Text: The program entry of this package is malformed.
- Fix: none

### binary.path

The path of a [[binary]] is absolute, has .., goes through a symbolic link or is not a file.

- Layer: script
- Text: The program of this package has a path that is not allowed.
- Fix: none

### binary.target

The target of a [[binary]] is not x86_64-unknown-linux-musl.

- Layer: script
- Text: This package ships a program for a platform this server does not support.
- Fix: none

### binary.duplicate

Two [[binary]] tables use the same path or bin name.

- Layer: script
- Text: This package lists a program twice.
- Fix: none

### binary.missing

The file named by a [[binary]] path is not in the package.

- Layer: script
- Text: The program this package names is not in it.
- Fix: none

### binary.unreferenced

No commands.tsv row and no [service] exec refers to a [[binary]] as @/<path>.

- Layer: script
- Text: This package carries a program that nothing starts.
- Fix: none

### binary.hash

The sha256 of a program differs from the one in package.toml.

- Layer: script
- Text: The program of this package is not the one it declares; it was not installed and the old version stays.
- Fix: `hs pkg fetch`

### binary.exec

The program of a package lacks the executable bit.

- Layer: script
- Text: The program of this package is not executable; it was not installed and the old version stays.
- Fix: none

### binary.arch

The package ships a compiled program for x86_64 and the server is another architecture.

- Layer: script
- Text: This package needs an x86_64 server; it was not installed.
- Fix: none

### binary.unbuilt

The package declares a program that is not built yet (empty sha256, no file).

- Layer: script
- Text: This package has no built program yet; it cannot be installed.
- Fix: none

### binary.runner

A commands.tsv row without the flag proto names a [[binary]] program.

- Layer: script
- Text: This package starts its program the wrong way; it cannot be installed.
- Fix: none

### binary.undeclared

A compiled program, or a non-script service exec, is started from a package without a [[binary]] that declares it.

- Layer: script
- Text: This package starts a program that has no declared hash.
- Fix: none

### code.unknown

A pairing code is not known: wrong, already used, expired, or the server name is taken by another server (one answer for all of them, POST /api/remote/claim).

- Layer: script
- Text: The other server does not know that code: wrong, already used or expired.
- Fix: none

### code.rate

Too many wrong pairing codes from one address within a minute.

- Layer: script
- Text: Too many wrong codes from here. Wait a minute and try again.
- Fix: none

### code.unavailable

The server cannot make the access now (no domain controller, storage locked).

- Layer: script
- Text: The other server cannot make the access now (is its storage unlocked?).
- Fix: none

### ext.state-conflict

The old and the new state folder of a service both exist, or the old path is a wrong link or not a folder (nothing is moved, nothing is deleted).

- Layer: script
- Text: This extension has its data in two places and the server does not know which one to use; its service does not start. Nothing was changed.
- Fix: `see docs/extensions-sdk.md, "If something goes wrong"`

### ext.state-move-failed

The state folder of a service cannot be moved because /var/lib/hs is on another file system (no copy is made).

- Layer: script
- Text: The data of this extension cannot be moved to its new folder; its service does not start. Nothing was changed.
- Fix: `see docs/extensions-sdk.md, "If something goes wrong"`

### ext.state-reserved

A package has the name of a folder the server itself keeps in /var/lib/hs (nothing is moved).

- Layer: script
- Text: This extension has a name the server uses for its own data; its service does not start. Nothing was changed.
- Fix: `see docs/extensions-sdk.md, "If something goes wrong"`

### ext.state-link-failed

The old path of a state folder could not be made a link to the new folder.

- Layer: script
- Text: The server could not link the data folder of this extension. Nothing was deleted.
- Fix: `see docs/extensions-sdk.md, "If something goes wrong"`

<!-- END generated -->

Not tested on hardware yet.
