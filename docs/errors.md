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

### ext.dynamic-write

A service or confined command declares fs.write outside /var/lib/hs/<its name>.

- Layer: script
- Text: This extension wants to write outside its own folder; its service does not start.
- Fix: none

### ext.dynamic-read

A service or confined command declares fs.read of the state of the server or of another extension.

- Layer: script
- Text: This extension wants to read data that is not its own; its service does not start.
- Fix: none

### user.name-missing

The user or group name was not given.

- Layer: script
- Text: Give the name of the user or group.
- Fix: none

### user.option-misplaced

An option was given to an action it does not belong to.

- Layer: script
- Text: That option does not belong to this action.
- Fix: none

### user.nothing-to-change

An edit names no field to change.

- Layer: script
- Text: Nothing was changed: give a field to change.
- Fix: none

### user.group-forbidden

Domain Users was chosen as a group; every user is in it already.

- Layer: script
- Text: Every user is in Domain Users; it cannot be chosen.
- Fix: none

### user.group-unknown

A group that does not exist was named.

- Layer: script
- Text: No such group was found.
- Fix: none

### user.access-invalid

A share access is not written as share=read, write or full.

- Layer: script
- Text: The access is share=read, write or full.
- Fix: none

### user.share-unknown

A share that does not exist was named.

- Layer: script
- Text: No such share was found.
- Fix: none

### user.password-missing

The password was not passed on standard input.

- Layer: script
- Text: No password was given.
- Fix: none

### admin.option-misplaced

An option was given to an action it does not belong to.

- Layer: script
- Text: That option does not belong to this action.
- Fix: none

### admin.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### admin.no-push-address

The test push message needs an address that is not set.

- Layer: script
- Text: There is no push address yet.
- Fix: none

### admin.test-failed

The test message could not be sent.

- Layer: script
- Text: The test message could not be sent.
- Fix: none

### admin.pin-failed

The MAC addresses could not be pinned.

- Layer: script
- Text: The MAC addresses could not be pinned.
- Fix: none

### admin.not-snapraid

The upload cache exists only on the snapraid layout.

- Layer: script
- Text: There is no upload cache on this layout.
- Fix: none

### admin.no-cache

The upload cache is not mounted.

- Layer: script
- Text: There is no upload cache on this server.
- Fix: none

### admin.seconds-invalid

The seconds of the fan cleaning are not a number from 3 to 30.

- Layer: script
- Text: The seconds are a number from 3 to 30.
- Fix: none

### admin.no-fan-controller

No fan controller was found on this machine.

- Layer: script
- Text: No fan controller was found.
- Fix: none

### dc.option-misplaced

An option was given to an action it does not belong to.

- Layer: script
- Text: That option does not belong to this action.
- Fix: none

### dc.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### dc.name-invalid

The name of the domain controller is not an instance name.

- Layer: script
- Text: That is not an instance name.
- Fix: none

### dc.ca-exists

The certificate authority exists already (a new one would make every certificate invalid).

- Layer: script
- Text: The CA exists already.
- Fix: none

### dc.ca-failed

The certificate authority could not be made.

- Layer: script
- Text: The CA could not be made.
- Fix: none

### dc.no-ca

There is no certificate authority yet.

- Layer: script
- Text: There is no CA yet: make it first.
- Fix: none

### dc.not-local

The domain controller does not run on this server.

- Layer: script
- Text: That controller does not run on this server.
- Fix: none

### token.name-missing

The name of the token was not given.

- Layer: script
- Text: Give the name of the token.
- Fix: none

### token.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### token.caller-missing

Who asks (the person and the role) was not given.

- Layer: script
- Text: Who asks is missing.
- Fix: none

### token.role-unknown

The role of the person who asks is not one that exists.

- Layer: script
- Text: That role is not known.
- Fix: none

### token.days-invalid

The days of a token are not a number from 1 to 365.

- Layer: script
- Text: The days are a number from 1 to 365.
- Fix: none

### token.invalid

The token cannot be created with these values.

- Layer: script
- Text: The token cannot be created.
- Fix: none

### token.not-found

There is no token with this name, or it belongs to someone else.

- Layer: script
- Text: There is no token with this name.
- Fix: none

### ssh.key-missing

The public key or the id of the key was not given.

- Layer: script
- Text: Give the public key or the id of the key.
- Fix: none

### ssh.too-long

The key line is longer than 800 characters.

- Layer: script
- Text: That is too long.
- Fix: none

### ssh.not-one-line

The key has more than one line or has control characters.

- Layer: script
- Text: It must be one line without control characters.
- Fix: none

### ssh.not-public-key

The text is not a public key line.

- Layer: script
- Text: That is not a public key line.
- Fix: none

### ssh.key-invalid

The public key did not pass the check of ssh-keygen.

- Layer: script
- Text: That is not a valid public key.
- Fix: none

### ssh.key-listed

The key is in the list already.

- Layer: script
- Text: This key is in the list already.
- Fix: none

### ssh.key-unknown

There is no key with this id.

- Layer: script
- Text: There is no key with this id.
- Fix: none

### ssh.last-key

The key is the last one; without a key nobody could log in over SSH.

- Layer: script
- Text: That is the last key.
- Fix: none

### ssh.session-key

The key is the one the current SSH session used.

- Layer: script
- Text: That key is in use by your session.
- Fix: none

### ssh.failed

The key script refused the change.

- Layer: script
- Text: The key could not be changed.
- Fix: none

### peer.invalid

A value of the peer (name, host, share, path ...) has characters that do not belong in it.

- Layer: script
- Text: That value is not valid.
- Fix: none

### peer.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### peer.name-missing

The name for the other server was not given.

- Layer: script
- Text: Give the name of the other server.
- Fix: none

### peer.args-missing

The host and the share were not both given.

- Layer: script
- Text: Give the host and the share.
- Fix: none

### peer.user-missing

The login of the mount was not given.

- Layer: script
- Text: Give the login.
- Fix: none

### peer.offered

The share is offered to this peer already.

- Layer: script
- Text: That share is offered already.
- Fix: none

### peer.mounted

The share of this peer is set up already.

- Layer: script
- Text: That share is set up already.
- Fix: none

### peer.not-mounted

Nothing is mounted from this peer.

- Layer: script
- Text: Nothing is mounted from that peer.
- Fix: none

### peer.not-offered

Nothing is shared with this peer.

- Layer: script
- Text: Nothing is shared with that peer.
- Fix: none

### peer.failed

The peer script refused the step.

- Layer: script
- Text: The step was refused.
- Fix: none

### node.name-missing

The name of the node was not given.

- Layer: script
- Text: Give the name of the node.
- Fix: none

### node.name-invalid

The name is not a node name (lower case letters, digits and dashes, starting with a letter).

- Layer: script
- Text: That is not a node name.
- Fix: none

### node.host-invalid

The host is not a host name or an address.

- Layer: script
- Text: That is not a host name or address.
- Fix: none

### node.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### node.kind-invalid

The kind of the node is not peer, vps or edge.

- Layer: script
- Text: The kind is peer, vps or edge.
- Fix: none

### node.port-invalid

The port is not a number from 1 to 65535.

- Layer: script
- Text: That is not a port.
- Fix: none

### node.exists

A node with this name exists already.

- Layer: script
- Text: There is already a node with this name.
- Fix: none

### node.unknown

No node has this name.

- Layer: script
- Text: There is no node with this name.
- Fix: none

### node.from-config

The node comes from a setting and goes away with that setting.

- Layer: script
- Text: That node comes from a setting.
- Fix: none

<!-- END generated -->

Not tested on hardware yet.
