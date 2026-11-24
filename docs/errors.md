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

A bulk folder cannot be passed into a virtual machine.

- Layer: script
- Text: Bulk folders cannot be passed into a virtual machine.
- Fix: none

### ct.none-running

No running instance is left to update.

- Layer: script
- Text: No instance is running.
- Fix: none

<!-- END generated -->

Not tested on hardware yet.
