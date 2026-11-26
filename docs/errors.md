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

### pkg.rows

An installed package carried a command or app route the core refuses (it clashes with the core or another package), so it was not kept.

- Layer: script
- Text: The package was not installed: its commands clash with the core or another package.
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

### binary.sdk-pin

repo-check --release: the Cargo.toml of a package does not take hobnix-ext-sdk from the core by a release tag (vX.Y.Z, or a beta tag vX.Y.Z-beta.N).

- Layer: script
- Text: This package is not ready for a release: its extension SDK is not pinned to a core release.
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

### backup.browse-state

Browsing of the backup is already in the state asked for.

- Layer: script
- Text: Browsing is already in that state.
- Fix: none

### backup.count-invalid

The number of drill restores is not from 1 to 100.

- Layer: script
- Text: The count is a number from 1 to 100.
- Fix: none

### backup.disk-missing

The backup disk is not plugged in.

- Layer: script
- Text: The backup disk is not plugged in.
- Fix: none

### backup.disk-present

A backup disk is plugged in already.

- Layer: script
- Text: A backup disk is plugged in already.
- Fix: none

### backup.instance-unknown

The backup was asked about an instance that does not exist.

- Layer: script
- Text: No such instance was found.
- Fix: none

### backup.kind-invalid

The kind of backup item or off-site target is not one that exists.

- Layer: script
- Text: That kind is not known.
- Fix: none

### backup.no-offsite

No off-site repository is set, or it is off already.

- Layer: script
- Text: There is no off-site repository to change.
- Fix: none

### backup.not-set-up

The backup is not set up yet.

- Layer: script
- Text: The backup is not set up yet.
- Fix: `hs backup init <device>`

### backup.repo-invalid

A repository address or a field of an off-site target has characters that do not belong in it.

- Layer: script
- Text: That is not a valid repository address.
- Fix: none

### backup.rule-invalid

A backup include or exclude rule is malformed.

- Layer: script
- Text: That backup rule is not valid.
- Fix: none

### backup.to-invalid

The value after --to is not on or off.

- Layer: script
- Text: The value is on or off.
- Fix: none

### disk.backup-disk

The disk is the backup disk and is not erased here.

- Layer: script
- Text: This is the backup disk.
- Fix: none

### disk.close-failed

An encrypted volume on the disk could not be closed.

- Layer: script
- Text: The encrypted volume could not be closed.
- Fix: none

### disk.forget-failed

A missing disk could not be removed from the inventory.

- Layer: script
- Text: The disk could not be forgotten.
- Fix: none

### disk.in-use

The disk or partition is mounted or used as swap.

- Layer: script
- Text: The disk is in use.
- Fix: none

### disk.not-data-disk

The name is not a data disk of the array (data-NN).

- Layer: script
- Text: That is not a data disk of the array.
- Fix: none

### disk.not-empty

A disk to add to a pool still holds data.

- Layer: script
- Text: The disk is not empty.
- Fix: none

### disk.not-missing

Only a disk that is missing can be forgotten.

- Layer: script
- Text: The disk is in the machine.
- Fix: none

### disk.not-offered

The disk is not one that may be mounted as a temp disk.

- Layer: script
- Text: This disk is not offered for mounting.
- Fix: none

### disk.not-recovering

The disk is not out of the pool for a recovery.

- Layer: script
- Text: The disk is not in a recovery.
- Fix: none

### disk.not-whole

The name is a partition, not a whole disk.

- Layer: script
- Text: This is not a whole disk.
- Fix: none

### disk.pool-member

The disk is a member of a ZFS pool or of the data array.

- Layer: script
- Text: The disk is a member of a pool.
- Fix: none

### disk.temp-refused

The temp disk script refused a mount, an eject or a copy.

- Layer: script
- Text: The temp disk step was refused.
- Fix: none

### disk.test-kind

The self-test is not short or long.

- Layer: script
- Text: The test is short or long.
- Fix: none

### disk.test-refused

The disk cannot run a self-test now.

- Layer: script
- Text: The self-test cannot start.
- Fix: none

### disk.test-running

A self-test is running on the disk already.

- Layer: script
- Text: A self-test is running already.
- Fix: none

### disk.wipe-failed

The disk could not be erased.

- Layer: script
- Text: The disk could not be erased.
- Fix: none

### part.already

The part is already in the state asked for.

- Layer: script
- Text: The part is already in that state.
- Fix: none

### part.not-switchable

The part follows the role of this server and is not switched by hand.

- Layer: script
- Text: This part is not switched here.
- Fix: none

### part.pending

The part is switched on and waits for the next rebuild.

- Layer: script
- Text: The part takes effect with the next rebuild.
- Fix: `hs rebuild`

### part.unknown

No part of that name exists.

- Layer: script
- Text: No such part was found.
- Fix: none

### part.write-failed

machine.toml could not be changed.

- Layer: script
- Text: machine.toml could not be changed.
- Fix: none

### pool.zfs-member

The disk belongs to a ZFS pool.

- Layer: script
- Text: The disk belongs to a ZFS pool.
- Fix: none

### share.as-invalid

The owner given with --as is not <uid>:<gid>.

- Layer: script
- Text: The owner is <uid>:<gid>.
- Fix: none

### share.exists

A share of that name exists already.

- Layer: script
- Text: A share of that name exists already.
- Fix: none

### share.folder-invalid

The folder is not a folder inside the share.

- Layer: script
- Text: That is not a folder inside the share.
- Fix: none

### share.instance-unknown

The instance named for a share does not exist.

- Layer: script
- Text: No such instance was found.
- Fix: none

### share.kind-invalid

The kind of share is not shares or sensitive.

- Layer: script
- Text: The kind is shares or sensitive.
- Fix: none

### share.needs-zfs

Snapshots need the ZFS layout.

- Layer: script
- Text: Snapshots need the ZFS layout.
- Fix: none

### share.no-snapshots

The share has no snapshots.

- Layer: script
- Text: This share has no snapshots.
- Fix: none

### share.not-kept

Only a kept folder of a deleted share can be removed or brought back.

- Layer: script
- Text: Only a kept folder can be changed here.
- Fix: none

### share.path-invalid

The path inside an instance does not start with /.

- Layer: script
- Text: The path must start with /.
- Fix: none

### share.perm-invalid

A permission is not <sid>=<level>.

- Layer: script
- Text: The permission is <sid>=<level>.
- Fix: none

### share.reserved

The share name is reserved.

- Layer: script
- Text: That name is reserved.
- Fix: none

### share.snapshot-invalid

The snapshot id is not an id.

- Layer: script
- Text: That is not a snapshot id.
- Fix: none

### share.snapshot-unknown

The share has no snapshot of that id.

- Layer: script
- Text: No such snapshot was found.
- Fix: none

### share.tier-invalid

The tier is not one of the two offered.

- Layer: script
- Text: The tier is not one of the two offered.
- Fix: none

### share.to-invalid

The value after --to does not fit the setting.

- Layer: script
- Text: That value does not fit the setting.
- Fix: none

### share.unknown

No share of that name exists.

- Layer: script
- Text: No such share was found.
- Fix: none

### app.is-manager

The app is the Docker manager, which is not changed here.

- Layer: script
- Text: This app is the Docker manager and cannot be changed here.
- Fix: none

### app.unreadable

The app or its current revision cannot be read.

- Layer: script
- Text: The app could not be read.
- Fix: none

### app.not-web-managed

The app is not managed by the web interface.

- Layer: script
- Text: Only apps managed by the web interface can be saved, rebuilt or deleted.
- Fix: none

### app.doc-invalid

The document sent for an app is empty or has a malformed record.

- Layer: script
- Text: The document is not valid.
- Fix: none

### app.exists

An app, a Docker app or an instance of that name exists already.

- Layer: script
- Text: That name is taken already.
- Fix: none

### app.folder-missing

The folder of the app cannot be found.

- Layer: script
- Text: The folder of the app was not found.
- Fix: none

### app.compose-invalid

The compose file does not pass the check.

- Layer: script
- Text: The compose file is not valid.
- Fix: none

### app.port-used

A port of the compose file is used by another app.

- Layer: script
- Text: A port is used by another app.
- Fix: none

### app.container-name-used

A container name of the compose file is used by another app.

- Layer: script
- Text: A container name is used by another app.
- Fix: none

### app.compose-refused

The policy check of the compose file refused it.

- Layer: script
- Text: The compose file was refused.
- Fix: none

### app.recreate-failed

The recreate of the app failed.

- Layer: script
- Text: The app could not be recreated.
- Fix: none

### app.workdir-missing

The working directory of the app cannot be found.

- Layer: script
- Text: The working directory of the app was not found.
- Fix: none

### app.action-failed

An action on the app failed.

- Layer: script
- Text: The action failed.
- Fix: none

### app.usage

The command of the Docker app script got too few arguments.

- Layer: script
- Text: The command is missing arguments.
- Fix: none

### app.rev-missing

The action needs --rev and did not get it.

- Layer: script
- Text: The action needs a revision.
- Fix: none

### registry.user-missing

--user has no name.

- Layer: script
- Text: --user needs a name.
- Fix: none

### registry.user-invalid

The user name of a registry login is not valid.

- Layer: script
- Text: The user name is not valid.
- Fix: none

### registry.unknown

No registry of that name is set up.

- Layer: script
- Text: No such registry is set up.
- Fix: none

### registry.token-invalid

The token of a registry login is missing or not valid.

- Layer: script
- Text: The token is missing or not valid.
- Fix: none

### registry.login-failed

The registry did not accept the login.

- Layer: script
- Text: The login failed. Check the user and the token.
- Fix: none

### registry.store-failed

The token of a registry login could not be stored.

- Layer: script
- Text: The token could not be stored.
- Fix: none

### registry.forget-failed

The login of a registry could not be removed.

- Layer: script
- Text: The login could not be removed.
- Fix: none

### registry.usage

The command of the registry script got too few arguments.

- Layer: script
- Text: The command is missing arguments.
- Fix: none

### apps.repo-invalid

--repo is not a repository name.

- Layer: script
- Text: The repository name is not valid.
- Fix: none

### apps.tag-invalid

--tag is not a release tag.

- Layer: script
- Text: The release tag is not valid.
- Fix: none

### apps.tag-missing

A start has no --tag of the plan.

- Layer: script
- Text: The start needs the tag of the plan.
- Fix: none

### apps.from-missing

--from has no step.

- Layer: script
- Text: --from needs a step.
- Fix: none

### apps.from-invalid

--from names a step the package does not have.

- Layer: script
- Text: That step does not exist.
- Fix: none

### apps.by-invalid

--by is not a user name.

- Layer: script
- Text: The user name is not valid.
- Fix: none

### apps.role-invalid

--role is not a role.

- Layer: script
- Text: The role is not valid.
- Fix: none

### apps.set-invalid

--set is not KEY=value.

- Layer: script
- Text: --set needs KEY=value.
- Fix: none

### apps.no-release

The package has no verified release.

- Layer: script
- Text: The package has no verified release.
- Fix: none

### apps.not-in-repo

The package is not in the repository asked for.

- Layer: script
- Text: The package is not in that repository.
- Fix: none

### apps.no-steps

The release names no steps.

- Layer: script
- Text: The release names no steps.
- Fix: none

### apps.needs-newer-core

The package needs a newer core than this server has.

- Layer: script
- Text: The package needs a newer core.
- Fix: none

### apps.update-available

The package is installed and a newer release is out.

- Layer: script
- Text: The package is installed; update it instead.
- Fix: none

### apps.installed

The package is installed already.

- Layer: script
- Text: The package is installed already.
- Fix: none

### apps.needs-terminal

The package asks for a password and needs a terminal.

- Layer: script
- Text: This package must be installed at a terminal.
- Fix: none

### apps.takes-no-name

The package takes no container name and no answers.

- Layer: script
- Text: This package takes no name and no answers.
- Fix: none

### apps.single-instance

The package runs once on a server.

- Layer: script
- Text: This package runs once on a server.
- Fix: none

### apps.name-taken

The instance name is taken by an instance or a service.

- Layer: script
- Text: That name is taken already.
- Fix: none

### apps.answer-invalid

An answer to a question of the package does not fit.

- Layer: script
- Text: The answer does not fit.
- Fix: none

### apps.answer-unknown

The package does not ask that question.

- Layer: script
- Text: The package does not ask that question.
- Fix: none

### apps.need-unknown

The package needs something this server cannot provide.

- Layer: script
- Text: The package needs something this server cannot provide.
- Fix: none

### apps.need-off

The package needs a part that is switched off.

- Layer: script
- Text: A part the package needs is off. Switch it on first.
- Fix: none

### apps.storage-locked

The storage is locked.

- Layer: script
- Text: The storage is locked. Unlock it first.
- Fix: none

### apps.no-network

The step needs the network and it is down.

- Layer: script
- Text: The server has no network.
- Fix: none

### apps.docker-self

Docker was named as a need of itself.

- Layer: script
- Text: Docker cannot be a need of itself.
- Fix: none

### apps.secret-invalid

The secret has a control character.

- Layer: script
- Text: The secret is not valid.
- Fix: none

### recipe.name-missing

--name has no value.

- Layer: script
- Text: --name needs a value.
- Fix: none

### recipe.by-invalid

--by is not a user name.

- Layer: script
- Text: The user name is not valid.
- Fix: none

### recipe.role-invalid

--role is not a role.

- Layer: script
- Text: The role is not valid.
- Fix: none

### recipe.set-invalid

--set is not KEY=value.

- Layer: script
- Text: --set needs KEY=value.
- Fix: none

### recipe.unknown

No recipe of that name exists.

- Layer: script
- Text: No such recipe was found.
- Fix: none

### recipe.needs-terminal

The recipe asks for a password and needs a terminal.

- Layer: script
- Text: This recipe must be run at a terminal.
- Fix: none

### recipe.parked

The recipe is parked and does nothing without force.

- Layer: script
- Text: This recipe is parked.
- Fix: none

### recipe.answer-invalid

An answer to a question of the recipe does not fit.

- Layer: script
- Text: The answer does not fit.
- Fix: none

### recipe.answer-unknown

The recipe does not ask that question.

- Layer: script
- Text: The recipe does not ask that question.
- Fix: none

### recipe.secret-invalid

The secret has a control character.

- Layer: script
- Text: The secret is not valid.
- Fix: none

### ct.all-misuse

all is used with an action other than update-all, or update-all with another instance.

- Layer: script
- Text: all belongs to update-all only.
- Fix: none

### ct.value-invalid

A value (number, autostart, docker, type or stop keep) is not one that exists.

- Layer: script
- Text: The value is not valid.
- Fix: none

### ct.option-misplaced

An option is used with an action it does not belong to.

- Layer: script
- Text: The option does not belong to this action.
- Fix: none

### ct.iso-vm-only

An installer image is given for something other than a virtual machine.

- Layer: script
- Text: An installer image is for a virtual machine only.
- Fix: none

### ct.iso-invalid

The installer image name is not valid.

- Layer: script
- Text: The image name is not valid.
- Fix: none

### ct.iso-missing

The installer image is not in the library.

- Layer: script
- Text: No such image is in the library.
- Fix: none

### ct.pool-unknown

The storage pool does not exist.

- Layer: script
- Text: No such storage pool exists.
- Fix: none

### ct.pool-full

The disk does not fit in the free space of the pool.

- Layer: script
- Text: The disk does not fit in the pool.
- Fix: none

### ct.bind-invalid

A bind is not tier:name:path.

- Layer: script
- Text: The bind is not valid.
- Fix: none

### ct.bind-duplicate

Two binds have the same name.

- Layer: script
- Text: Two binds have the same name.
- Fix: none

### ct.bind-vm

A folder of the large-storage tier cannot be passed into a virtual machine.

- Layer: script
- Text: That folder cannot be passed into a virtual machine.
- Fix: none

### ct.none-running

No running instance is left to update.

- Layer: script
- Text: No instance is running.
- Fix: none

### system.force-misplaced

--force was given to an action other than sync.

- Layer: script
- Text: --force belongs to sync only.
- Fix: none

### system.days-invalid

The number of days is not a whole number of 1 or more.

- Layer: script
- Text: Give a number of days, 1 or more.
- Fix: none

### system.not-snapraid

A sync was asked on a server whose data is not on SnapRAID.

- Layer: script
- Text: There is nothing to sync on this server.
- Fix: none

### system.pool-unknown

A storage pool that does not exist was named.

- Layer: script
- Text: No such storage pool was found.
- Fix: none

### system.scrub-running

A scrub of the pool is running already.

- Layer: script
- Text: A scrub is running already.
- Fix: none

### system.storage-locked

The storage is locked, so an update or rebuild would refuse.

- Layer: script
- Text: The storage is locked: unlock it first.
- Fix: none

### system.power-refused

The reboot or shutdown check refused.

- Layer: script
- Text: The server cannot do this now.
- Fix: none

### system.schedule-failed

The reboot, update or rebuild could not be scheduled.

- Layer: script
- Text: It could not be scheduled.
- Fix: none

### service.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### service.value-invalid

An option was given a value that is not yes or no.

- Layer: script
- Text: The value is yes or no.
- Fix: none

### service.proxy-invalid

The --proxy option is neither public nor local.

- Layer: script
- Text: The proxy is public or local.
- Fix: none

### service.public-name-invalid

The public name is not a full domain name.

- Layer: script
- Text: The public name is a full name like app.example.org.
- Fix: none

### service.public-name-missing

A public service was asked without a public name.

- Layer: script
- Text: A public service needs its public name.
- Fix: none

### service.no-proxy

No reverse proxy is set up.

- Layer: script
- Text: No reverse proxy is set up yet.
- Fix: none

### service.exists

A service with this name exists already.

- Layer: script
- Text: There is a service with this name already.
- Fix: none

### service.unknown

No service has this name.

- Layer: script
- Text: No such service was found.
- Fix: none

### service.port-invalid

The port is not a number from 1 to 65535.

- Layer: script
- Text: The port is a number from 1 to 65535.
- Fix: none

### service.target-both

Both a container and a host were given.

- Layer: script
- Text: Give a container or a host, not both.
- Fix: none

### service.target-missing

Neither a container nor a host was given.

- Layer: script
- Text: Give the container or the host the service runs on.
- Fix: none

### service.exposure-invalid

The exposure is not never-public, private-ok or public-ok.

- Layer: script
- Text: The exposure is never-public, private-ok or public-ok.
- Fix: none

### service.nothing-to-change

An edit or set names nothing to change.

- Layer: script
- Text: Nothing was changed: give a field to change.
- Fix: none

### service.nothing-to-do

There is nothing to adopt, describe or reconcile.

- Layer: script
- Text: There is nothing to do.
- Fix: none

### service.failed

The service command failed or refused.

- Layer: script
- Text: The service could not be changed.
- Fix: none

### config.no-machine-toml

There is no machine.toml on this server.

- Layer: script
- Text: There is no machine.toml on this server.
- Fix: none

### config.no-machine-nix

There is no machine.nix to convert.

- Layer: script
- Text: There is no machine.nix to convert.
- Fix: none

### config.exists

machine.toml exists already, so there is nothing to convert.

- Layer: script
- Text: machine.toml exists already.
- Fix: none

### config.nothing-new

machine.toml is in the layout of the example already.

- Layer: script
- Text: Nothing is new.
- Fix: none

### config.rewrite-failed

machine.toml could not be rewritten or converted (it is left as it was).

- Layer: script
- Text: machine.toml could not be rewritten.
- Fix: none

### config.not-settable

The setting cannot be changed from the interface.

- Layer: script
- Text: This setting is changed on the server.
- Fix: none

### config.key-unknown

The name is not an option of machine.toml.example.

- Layer: script
- Text: No such setting was found.
- Fix: none

### config.not-scalar

The setting is a list or table.

- Layer: script
- Text: Edit this setting in machine.toml on the server.
- Fix: none

### config.value-invalid

The value does not fit the setting.

- Layer: script
- Text: The value does not fit this setting.
- Fix: none

### config.not-set

The setting to switch off is not set.

- Layer: script
- Text: This setting is not set.
- Fix: none

### config.unchanged

The setting has this value already.

- Layer: script
- Text: The setting has this value already.
- Fix: none

### config.cannot-switch-off

The setting cannot be switched off.

- Layer: script
- Text: This setting cannot be switched off.
- Fix: none

### config.args-invalid

The arguments of set or apply are wrong.

- Layer: script
- Text: The arguments are not a key and a value.
- Fix: none

### config.key-twice

A setting was given twice in one apply.

- Layer: script
- Text: A setting was given twice.
- Fix: none

### config.write-failed

A setting could not be written (the earlier state is put back).

- Layer: script
- Text: The setting could not be written.
- Fix: none

### config.check-failed

machine.toml would have problems after the change (it was put back).

- Layer: script
- Text: The change would break machine.toml.
- Fix: none

### setup.not-open

The first-run wizard is not open.

- Layer: script
- Text: The first-run wizard is not open.
- Fix: none

### setup.close-failed

The first-run wizard could not be closed.

- Layer: script
- Text: The wizard could not be closed.
- Fix: none

### iso.args-missing

A file or URL, or an image name, was not given.

- Layer: script
- Text: Give a file or URL, or an image name.
- Fix: none

### iso.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### iso.option-misplaced

An option was given to an action it does not belong to.

- Layer: script
- Text: That option does not belong to this action.
- Fix: none

### iso.not-found

No image has this name in the library.

- Layer: script
- Text: No such image was found.
- Fix: none

### iso.attached

The image is attached to an instance.

- Layer: script
- Text: Detach the image first.
- Fix: none

### iso.url-invalid

The URL is too long or not a plain http or https address.

- Layer: script
- Text: The URL is not valid.
- Fix: none

### iso.url-local

The URL points to this server itself.

- Layer: script
- Text: This server does not download from itself.
- Fix: none

### iso.path-invalid

The path of a file is not an absolute path without "..".

- Layer: script
- Text: The path is not valid.
- Fix: none

### iso.file-missing

The file does not exist.

- Layer: script
- Text: No such file was found.
- Fix: none

### iso.file-unreadable

The file cannot be read.

- Layer: script
- Text: The file cannot be read.
- Fix: none

### iso.in-library

The file is in the image library already.

- Layer: script
- Text: The file is in the library already.
- Fix: none

### iso.source-invalid

The source is neither an absolute path nor an http(s) URL.

- Layer: script
- Text: Give a file path or an http(s) URL.
- Fix: none

### iso.exists

An image with this name is in the library already.

- Layer: script
- Text: Remove it first or use another name.
- Fix: none

### iso.checksum-conflict

Both --checksum and --no-checksum were given.

- Layer: script
- Text: Give one of them, not both.
- Fix: none

### iso.checksum-invalid

The checksum is not hexadecimal text, or its length or prefix does not fit.

- Layer: script
- Text: The checksum is not valid.
- Fix: none

### iso.no-room

The image does not fit in the free space of the folder.

- Layer: script
- Text: There is not enough room for the image.
- Fix: none

### release.channel-unknown

The channel is not stable, beta or edge.

- Layer: script
- Text: The channel is stable, beta or edge.
- Fix: none

### release.unchanged

The server is on this channel already.

- Layer: script
- Text: The server is on this channel already.
- Fix: none

### release.signature-invalid

The signature of the release is not valid for a trusted release key.

- Layer: script
- Text: The release is not signed by a trusted key.
- Fix: none

### vps.host-missing

The setting vpsHost is not set.

- Layer: script
- Text: The proxyserver is not set up yet.
- Fix: none

### vps.host-invalid

The setting vpsHost is not a host name or address.

- Layer: script
- Text: vpsHost is not a host name or address.
- Fix: none

### vps.no-key

There is no key for the proxyserver yet.

- Layer: script
- Text: There is no key for the proxyserver yet.
- Fix: none

### net.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### net.address-invalid

The address of the router is not an http(s) address.

- Layer: script
- Text: That is not an address of the router.
- Fix: none

### net.key-invalid

The key of the router has a control character.

- Layer: script
- Text: The key has a control character.
- Fix: none

### net.failed

The router could not be connected, or it refused the key.

- Layer: script
- Text: The router could not be connected.
- Fix: none

### notify.name-missing

A channel name was not given.

- Layer: script
- Text: A channel name is needed.
- Fix: none

### notify.provider-fixed

The provider of an existing channel was changed.

- Layer: script
- Text: The provider of a channel cannot be changed.
- Fix: none

### notify.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### notify.set-invalid

A --set option is not in the form key=value.

- Layer: script
- Text: The setting must be key=value.
- Fix: none

### notify.options-misplaced

Options were given to an action that takes none.

- Layer: script
- Text: This action takes no options.
- Fix: none

### notify.secret-many

More than one --secret was given.

- Layer: script
- Text: Give one secret at a time.
- Fix: none

### notify.priority-invalid

The minimum priority is not min, low, default, high or urgent.

- Layer: script
- Text: The minimum priority is min, low, default, high or urgent.
- Fix: none

### notify.quiet-invalid

The quiet rule is not respect or ignore.

- Layer: script
- Text: The quiet rule is respect or ignore.
- Fix: none

### notify.enabled-invalid

The enabled value is not yes or no.

- Layer: script
- Text: Enabled is yes or no.
- Fix: none

### notify.classes-invalid

A message class is not alarm, status, heartbeat or digest.

- Layer: script
- Text: The message classes are alarm, status, heartbeat and digest.
- Fix: none

### notify.exists

A channel with this name exists already.

- Layer: script
- Text: There is already a channel with this name.
- Fix: none

### notify.unknown

No channel has this name.

- Layer: script
- Text: There is no channel with this name.
- Fix: none

### notify.provider-unknown

No provider has this name.

- Layer: script
- Text: There is no provider with this name.
- Fix: none

### notify.setting-unknown

The provider has no text setting of this name.

- Layer: script
- Text: The provider has no such setting.
- Fix: none

### notify.value-multiline

A setting value has a line break or a tab.

- Layer: script
- Text: A value is one line without a tab.
- Fix: none

### notify.secret-unknown

The provider has no secret setting of this name.

- Layer: script
- Text: That is not a secret setting of the provider.
- Fix: none

### notify.value-invalid

A setting value does not match the form the provider expects.

- Layer: script
- Text: A value does not look right.
- Fix: none

### notify.class-unsupported

The provider cannot carry a message class that was asked for.

- Layer: script
- Text: The provider cannot carry this message class.
- Fix: none

### notify.settings-unusable

The provider refused the settings as they are.

- Layer: script
- Text: The settings are not usable.
- Fix: none

### health.nothing-paused

Resume was asked while nothing is paused.

- Layer: script
- Text: Nothing is paused.
- Fix: none

### health.id-missing

A problem id was not given.

- Layer: script
- Text: A problem id is needed.
- Fix: none

### health.for-invalid

The --for time is not a number with m, h, d or w.

- Layer: script
- Text: Give a time such as 90m, 12h, 7d or 2w.
- Fix: none

### health.note-invalid

The --note text is missing or longer than 200 characters.

- Layer: script
- Text: The note is at most 200 characters.
- Fix: none

### health.id-invalid

The problem id has characters that are not allowed.

- Layer: script
- Text: That is not a problem id.
- Fix: none

### health.not-active

The problem is not in the list of active problems.

- Layer: script
- Text: This is not an active problem.
- Fix: none

### health.acked-already

The problem is acknowledged already.

- Layer: script
- Text: This problem is acknowledged already.
- Fix: none

### health.not-acked

The problem is not acknowledged.

- Layer: script
- Text: This problem is not acknowledged.
- Fix: none

### expiry.name-missing

An entry name was not given.

- Layer: script
- Text: A name is needed.
- Fix: none

### expiry.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### expiry.date-invalid

The date is not a real date in the form YYYY-MM-DD.

- Layer: script
- Text: Use a date as YYYY-MM-DD.
- Fix: none

### expiry.renew-invalid

The renewal hint has a line break or a tab, or is longer than 120 characters.

- Layer: script
- Text: The hint is one line of at most 120 characters.
- Fix: none

### expiry.unknown

No entry has this name.

- Layer: script
- Text: There is no entry with this name.
- Fix: none

### job.unit-invalid

The unit is not a job of this server (hs-*).

- Layer: script
- Text: That is not a job of this server.
- Fix: none

### job.not-running

Stop was asked for a job that is not running.

- Layer: script
- Text: This job is not running.
- Fix: none

### job.unknown

No job has this name.

- Layer: script
- Text: There is no job with this name.
- Fix: none

### job.not-scheduled

Run now was asked for a unit that is not a scheduled job.

- Layer: script
- Text: Only scheduled jobs can be run now.
- Fix: none

### job.systemctl-failed

The service manager could not stop or start the job.

- Layer: script
- Text: The job could not be changed.
- Fix: none

### testlab.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### testlab.stage-invalid

The stage is not 1 to 6, a stage name or all.

- Layer: script
- Text: The stage is 1 to 6, a stage name or all.
- Fix: none

### testlab.off

The test-lab is off.

- Layer: script
- Text: The test-lab is off.
- Fix: none

### testlab.ref-refused

The ref or repository is not a branch, tag or commit of a Hobnix repository.

- Layer: script
- Text: That ref or repository is not accepted.
- Fix: none

### pkg.value-missing

An option or the address of a repository was given without its value.

- Layer: script
- Text: A value is missing.
- Fix: none

### pkg.draft-readonly

A start was asked for a package draft, which is only checked.

- Layer: script
- Text: A draft is only checked, nothing is started.
- Fix: none

### pkg.draft-unchecked

The check of a package draft did not run.

- Layer: script
- Text: The draft could not be checked.
- Fix: none

### pkg.draft-invalid

A package draft has problems.

- Layer: script
- Text: The draft has problems.
- Fix: none

### pkg.unknown

No repository offers a package of this name.

- Layer: script
- Text: There is no such package in the repositories.
- Fix: none

### pkg.installed

Install was asked for a package that is installed already.

- Layer: script
- Text: The package is installed already.
- Fix: none

### pkg.not-installed

The package is not installed from a repository.

- Layer: script
- Text: The package is not installed.
- Fix: none

### pkg.up-to-date

Update was asked for a package that has no newer release.

- Layer: script
- Text: The package is up to date.
- Fix: none

### pkg.core

Remove was asked for a core package.

- Layer: script
- Text: A core package is not removed.
- Fix: none

### pkg.remove-refused

The dry run of the removal refused it.

- Layer: script
- Text: The package cannot be removed now.
- Fix: none

### pkg.repo-unknown

No repository has this name.

- Layer: script
- Text: There is no repository with this name.
- Fix: none

### pkg.repo-exists

A repository of this name exists already.

- Layer: script
- Text: That name is taken already.
- Fix: none

### pkg.repo-url-invalid

The address of the repository is not in an allowed form.

- Layer: script
- Text: The address of the repository is not valid.
- Fix: none

### pkg.repo-default

Remove was asked for a default repository.

- Layer: script
- Text: A default repository stays.
- Fix: none

### pkg.key-invalid

The public signing key of the repository is missing or is not an SSH public key.

- Layer: script
- Text: An SSH public key is needed.
- Fix: none

### pkg.repo-add-failed

The repository could not be added.

- Layer: script
- Text: The repository could not be added.
- Fix: none

### pkg.repo-unreadable

No signed release could be read from a new repository with the given key.

- Layer: script
- Text: No signed release could be read, so the repository was not kept.
- Fix: none

### pkg.action-failed

The package command failed.

- Layer: script
- Text: The action on the package failed.
- Fix: none

### pkg.storage-locked

The storage is locked, so the rebuild would refuse.

- Layer: script
- Text: The storage is locked.
- Fix: none

### pkg.no-network

The step needs the network and it is down.

- Layer: script
- Text: This needs the network.
- Fix: none

### pkg.nothing-to-do

Every package that was asked for is installed and on already.

- Layer: script
- Text: There is nothing to do.
- Fix: none

### pkg.require-circle

Packages require each other in a circle.

- Layer: script
- Text: The packages require each other in a circle.
- Fix: none

### pkg.ambiguous

A package is in more than one repository.

- Layer: script
- Text: The package is in more than one repository.
- Fix: none

### pkg.added-repo

A package of an added repository is not installed together with others.

- Layer: script
- Text: Install this package from the Marketplace.
- Fix: none

### pkg.role-part

A required part follows the role of the server and is not switched by hand.

- Layer: script
- Text: A required part follows the role of this server.
- Fix: none

### pkg.require-missing

A required part is neither on the server nor offered by a repository.

- Layer: script
- Text: A required part is not available.
- Fix: none

### pkg.core-too-old

Install or update was asked for a package whose requires_core is above the API level of this core.

- Layer: script
- Text: The package needs a newer core: update the server first.
- Fix: `hs update`

### pkg.core-too-new

Install or update was asked for a package whose requires_core_max is below the API level of this core.

- Layer: script
- Text: The package does not support this core yet: wait for a release of the package that does.
- Fix: none

### pkg.core-range

The requires_core or requires_core_max of a package is not in a valid form.

- Layer: script
- Text: The package states its core range in a form this server does not accept.
- Fix: none

### blueprint.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### blueprint.unreadable

The blueprint does not exist, cannot be read or has problems.

- Layer: script
- Text: The blueprint cannot be used.
- Fix: none

### blueprint.role

The blueprint is not made for the role of this server.

- Layer: script
- Text: This blueprint is for another role.
- Fix: none

### blueprint.storage-locked

The storage is locked, so the rebuild would refuse.

- Layer: script
- Text: The storage is locked.
- Fix: none

### blueprint.no-network

The step needs the network and it is down.

- Layer: script
- Text: This needs the network.
- Fix: none

### blueprint.docker-refused

The plan to turn Docker on refused.

- Layer: script
- Text: Docker cannot be turned on.
- Fix: none

### blueprint.needs-docker

An app of the blueprint needs Docker, which is off and not part of the blueprint.

- Layer: script
- Text: An app of the blueprint needs Docker.
- Fix: none

### blueprint.confirm-unknown

A typed name was given that the plan does not ask for.

- Layer: script
- Text: The plan does not ask for that name.
- Fix: none

### apps.usage

The command to retry, clean up or remove an app was called without its arguments.

- Layer: script
- Text: The command is missing arguments.
- Fix: none

### apps.job-only

A step that only runs as a job body was called directly.

- Layer: script
- Text: This step only runs as a job.
- Fix: none

### apps.job-not-failed

Retry or clean up was asked for a job that did not fail.

- Layer: script
- Text: This job did not fail.
- Fix: none

### apps.no-failed-step

The job has no failed step to retry or clean up.

- Layer: script
- Text: The job has no failed step. Install again from the start.
- Fix: none

### apps.record-invalid

The job record names no usable app or an unknown step.

- Layer: script
- Text: The record of the job cannot be used.
- Fix: none

### apps.other-run

The app was installed by another run, so a clean-up could delete a working app.

- Layer: script
- Text: Another run installed this app. Use Remove for it.
- Fix: none

### apps.no-created-record

There is no record of what the install created.

- Layer: script
- Text: There is no record of what the install created.
- Fix: none

### apps.part-owned

The app belongs to a part and is removed by switching that part off.

- Layer: script
- Text: This app belongs to a part. Switch that part off.
- Fix: none

### apps.nothing-to-remove

Nothing is listed for the app.

- Layer: script
- Text: There is nothing to remove.
- Fix: none

### job.id-invalid

The argument is not a job id.

- Layer: script
- Text: That is not a job id.
- Fix: none

### job.record-unreadable

The record of the job cannot be read.

- Layer: script
- Text: The job record cannot be read.
- Fix: none

### job.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### job.value-invalid

The value of an option of an answer is not in the allowed form.

- Layer: script
- Text: A value is not valid.
- Fix: none

### job.no-question

An answer was given to a job that does not ask questions.

- Layer: script
- Text: This job does not ask questions.
- Fix: none

### job.answer-forbidden

Someone who neither started the run nor is an administrator tried to answer.

- Layer: script
- Text: Only the person who started this run, or an administrator, may answer.
- Fix: none

### job.answer-invalid

The answer does not fit the question.

- Layer: script
- Text: The answer does not fit the question.
- Fix: none

### disk.recovering

The disk is out of the pool for a recovery.

- Layer: script
- Text: The disk is out of the pool for a recovery.
- Fix: none

### disk.already-detached

The disk is detached already.

- Layer: script
- Text: The disk is detached already.
- Fix: none

### disk.not-mounted

The disk is not mounted.

- Layer: script
- Text: The disk is not mounted.
- Fix: none

### disk.last-data-disk

No other data disk would keep the pool running.

- Layer: script
- Text: This is the last data disk of the pool in use.
- Fix: none

### disk.not-detached

Attach was asked for a disk that is not detached.

- Layer: script
- Text: The disk is not detached.
- Fix: none

### disk.mount-failed

The disk could not be mounted.

- Layer: script
- Text: The disk could not be mounted.
- Fix: none

### disk.value-missing

An option or the thing to move was not given.

- Layer: script
- Text: A value is missing.
- Fix: none

### disk.target-invalid

--to does not name a data disk.

- Layer: script
- Text: The target is a data disk.
- Fix: none

### disk.path-invalid

The path on the disk is not allowed.

- Layer: script
- Text: The path is not allowed.
- Fix: none

### disk.path-missing

There is no such folder or file on the disk.

- Layer: script
- Text: There is no such path on the disk.
- Fix: none

### disk.target-same

The target is the disk the files are on.

- Layer: script
- Text: The target is the same disk.
- Fix: none

### disk.target-closed

The target disk is closed and takes no new files.

- Layer: script
- Text: The target disk takes no new files.
- Fix: none

### disk.target-unmounted

The target disk is not mounted or is out for a recovery.

- Layer: script
- Text: The target disk is not available.
- Fix: none

### disk.no-target

No other data disk can take the files.

- Layer: script
- Text: No other data disk can take the files.
- Fix: none

### disk.target-full

The target disk has not enough room.

- Layer: script
- Text: The target disk has not enough room.
- Fix: none

### disk.types-invalid

--types is not media or all.

- Layer: script
- Text: The types are media or all.
- Fix: none

### disk.recovery-running

The recovery of the disk is still running.

- Layer: script
- Text: The recovery is still running.
- Fix: none

### disk.tool-missing

A program the step needs is not installed.

- Layer: script
- Text: A program this step needs is not installed.
- Fix: none

### docker.args-missing

The command did not get what it needs.

- Layer: script
- Text: The command is missing arguments.
- Fix: none

### docker.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### docker.remote-read-only

A remote share is read only and takes no --as.

- Layer: script
- Text: A remote share is read only.
- Fix: none

### docker.value-invalid

The value of a Docker setting is not one of the allowed ones.

- Layer: script
- Text: The value is not valid.
- Fix: none

### docker.key-unknown

Only the Docker settings of the setup can be set here.

- Layer: script
- Text: This setting cannot be set here.
- Fix: none

### docker.already-on

Docker is on already.

- Layer: script
- Text: Docker is on already.
- Fix: none

### gateway.set-invalid

--set is not key=value.

- Layer: script
- Text: --set needs key=value.
- Fix: none

### gateway.key-unknown

The key is not a setting of the gateway setup.

- Layer: script
- Text: This is not a gateway setting.
- Fix: none

### gateway.key-twice

A setting was given twice.

- Layer: script
- Text: A setting was given twice.
- Fix: none

### gateway.nothing-to-change

No setting to change was given.

- Layer: script
- Text: There is nothing to change.
- Fix: none

### gateway.value-invalid

The value does not fit the setting.

- Layer: script
- Text: The value does not fit this setting.
- Fix: none

### gateway.not-scalar

The setting is a list or a table and is edited on the server.

- Layer: script
- Text: Edit this setting in machine.toml on the server.
- Fix: none

### gateway.unchanged

The gateway has these values already.

- Layer: script
- Text: Nothing changes.
- Fix: none

### gateway.port-conflict

The ports of the gateway clash with each other or with the server.

- Layer: script
- Text: The ports clash.
- Fix: none

### gateway.tunnel-from-missing

A tunnel port is set without the address the tunnel comes from.

- Layer: script
- Text: The address the tunnel comes from is missing.
- Fix: none

### gateway.acme-invalid

The certificate settings do not fit together.

- Layer: script
- Text: The certificate settings are not valid.
- Fix: none

### gateway.certificate-needed

The chosen answer for unknown hosts needs a certificate.

- Layer: script
- Text: This needs a certificate.
- Fix: none

### gateway.write-failed

A file of the gateway setup could not be written.

- Layer: script
- Text: A file could not be written.
- Fix: none

### gateway.check-failed

The change would break machine.toml.

- Layer: script
- Text: The change would break machine.toml.
- Fix: none

### gateway.rebuild-failed

The rebuild failed and the files were put back.

- Layer: script
- Text: The rebuild failed.
- Fix: none

### migrate.no-pool

No pool for data was found.

- Layer: script
- Text: No pool for data was found.
- Fix: none

### migrate.not-snapraid

Unraid disks are only adopted into a SnapRAID pool.

- Layer: script
- Text: This pool cannot take disks from Unraid.
- Fix: none

### migrate.disk-not-free

The name is not a free disk of the server.

- Layer: script
- Text: That is not a free disk.
- Fix: none

### migrate.disk-unusable

The disk holds no file system, or one that cannot be adopted.

- Layer: script
- Text: This disk cannot be adopted.
- Fix: none

### migrate.disk-twice

A disk was named twice or in two roles.

- Layer: script
- Text: A disk was named twice.
- Fix: none

### migrate.parity-not-empty

The disk named as old parity holds a file system.

- Layer: script
- Text: That is not an Unraid parity disk.
- Fix: none

### migrate.disk-too-small

The parity or spare disk is smaller than the largest data disk.

- Layer: script
- Text: The disk is too small.
- Fix: none

### migrate.passphrase-missing

The passphrase of the Unraid disks was not given.

- Layer: script
- Text: The passphrase is missing.
- Fix: none

### pool.not-recorded

The server has no pools line yet.

- Layer: script
- Text: The pools of this server are not recorded yet.
- Fix: none

### pool.already-imported

The pool is imported already.

- Layer: script
- Text: The pool is imported already.
- Fix: none

### pool.is-array

The name is the SnapRAID pool of the server.

- Layer: script
- Text: That is the SnapRAID pool of this server.
- Fix: none

### pool.not-waiting

No pool of this name waits to be imported.

- Layer: script
- Text: No such pool is waiting to be imported.
- Fix: none

### pool.name-ambiguous

Two pools have the same name.

- Layer: script
- Text: Two pools have this name.
- Fix: none

### pool.damaged

The pool is damaged and is not imported.

- Layer: script
- Text: The pool is damaged.
- Fix: none

### pool.foreign

The pool was last used by another system and is never forced.

- Layer: script
- Text: The pool was last used by another system.
- Fix: none

### pool.disk-not-whole

A disk of the pool is not a whole disk of this server.

- Layer: script
- Text: A disk of the pool is not a whole disk.
- Fix: none

### pool.disk-not-free

The disk is not a free disk of the pool.

- Layer: script
- Text: That is not a free disk of the pool.
- Fix: none

### pool.apps-unsupported

Importing an apps pool is not built yet.

- Layer: script
- Text: An apps pool cannot be imported yet.
- Fix: none

### pool.mountpoint-used

The folder of the pool already holds files on the system disk.

- Layer: script
- Text: The folder of the pool is not empty.
- Fix: none

### pool.use-invalid

--use is not data or apps.

- Layer: script
- Text: The use is data or apps.
- Fix: none

### preset.unknown

No preset has this name.

- Layer: script
- Text: There is no preset with this name.
- Fix: none

### preset.apply-failed

The preset could not be applied.

- Layer: script
- Text: The preset could not be applied.
- Fix: none

### preset.unreadable

The preset could not be read.

- Layer: script
- Text: The preset could not be read.
- Fix: none

### fm.capability-off

The file manager needs the capability storage.

- Layer: script
- Text: The file manager is not available on this server.
- Fix: none

### fm.usage

The command of the file manager was called without its arguments.

- Layer: script
- Text: The command is missing arguments.
- Fix: none

### fm.path-invalid

The path is not allowed or leaves the location.

- Layer: script
- Text: The path is not allowed.
- Fix: none

### fm.folder-missing

There is no such folder.

- Layer: script
- Text: There is no such folder.
- Fix: none

### fm.protected

The folder or file belongs to the array.

- Layer: script
- Text: This belongs to the array and cannot be used.
- Fix: none

### fm.value-missing

An option or a needed argument was not given.

- Layer: script
- Text: A value is missing.
- Fix: none

### fm.value-invalid

The value of an option is not in the allowed form.

- Layer: script
- Text: A value is not valid.
- Fix: none

### fm.option-misplaced

The option does not belong to this operation.

- Layer: script
- Text: That option does not belong to this action.
- Fix: none

### fm.selection-invalid

The selection that was sent cannot be used.

- Layer: script
- Text: The selection is not valid.
- Fix: none

### fm.nothing-selected

Nothing is selected.

- Layer: script
- Text: Nothing is selected.
- Fix: none

### fm.not-in-trash

The item is not in the trash, or its origin is not known.

- Layer: script
- Text: The item cannot be restored from the trash.
- Fix: none

### fm.in-trash

The folder is the trash, which is changed with restore only.

- Layer: script
- Text: That is the trash. Use restore.
- Fix: none

### fm.one-location

The operation works inside one location only.

- Layer: script
- Text: This works inside one location only.
- Fix: none

### fm.read-only

The location does not take this change.

- Layer: script
- Text: This location cannot be changed this way.
- Fix: none

### fm.exists

Something of that name exists already.

- Layer: script
- Text: That name is taken already.
- Fix: none

### fm.item-missing

There is no such item.

- Layer: script
- Text: There is no such item.
- Fix: none

### fm.item-unreadable

The item cannot be read.

- Layer: script
- Text: The item cannot be read.
- Fix: none

### fm.link

Links are not copied or moved.

- Layer: script
- Text: Links are not copied or moved.
- Fix: none

### fm.is-share

The folder is a share, which has its own rules.

- Layer: script
- Text: This is a share.
- Fix: none

### fm.target-invalid

The target does not fit the selection.

- Layer: script
- Text: The target does not fit.
- Fix: none

### fm.overwrite-move

Overwrite is refused together with move.

- Layer: script
- Text: Overwrite is not offered for a move.
- Fix: none

### fm.no-room

The target has not enough free room.

- Layer: script
- Text: There is not enough room at the target.
- Fix: none

### fm.busy

Another job works on the location or holds the lock of the pool.

- Layer: script
- Text: Another job is running. Try again when it is done.
- Fix: none

### fm.write-off

The file manager is read only until writing is allowed.

- Layer: script
- Text: The file manager is read only.
- Fix: none

### fm.state-unwritable

The state folder of the file manager is not writable.

- Layer: script
- Text: The file manager cannot write its state.
- Fix: none

### vault.value-missing

An option was given without its value.

- Layer: script
- Text: The option needs a value.
- Fix: none

### vault.args-unexpected

A secret name was given to an action that takes none.

- Layer: script
- Text: This action takes no names.
- Fix: none

### vault.name-invalid

The name is not a name of a secret.

- Layer: script
- Text: That is not a name of a secret.
- Fix: none

### vault.closed-already

Close was asked for a vault that is closed.

- Layer: script
- Text: The vault is closed already.
- Fix: none

### vault.missing

The server has no vault.

- Layer: script
- Text: There is no vault on this server.
- Fix: `hs vault init`

### docker.failed

A step of hs docker failed and gave no code of its own.

- Layer: script
- Text: The step failed.
- Fix: none

### fm.location-unknown

The id is not a location of the file manager.

- Layer: script
- Text: There is no such location.
- Fix: none

### fm.storage-locked

The encrypted storage is locked.

- Layer: script
- Text: The encrypted storage is locked: unlock it first.
- Fix: `hs unlock`

### fm.no-array

A disk was asked for on a server without an array.

- Layer: script
- Text: This server has no data disks of an array.
- Fix: none

### fm.no-cache

The upload cache was asked for on a server without one.

- Layer: script
- Text: There is no upload cache on this server.
- Fix: none

### fm.share-unknown

No pool holds a share of this name.

- Layer: script
- Text: There is no such share.
- Fix: none

### fm.location-unusable

The location exists but is not mounted.

- Layer: script
- Text: The location cannot be used now.
- Fix: none

### fm.same-files

Two locations show the same files.

- Layer: script
- Text: Both sides show the same files.
- Fix: none

<!-- END generated -->

Not tested on hardware yet.
