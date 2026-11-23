# Plan: remote shares in Shares, pairing by code (2026-11-24)

Status: plan; the pairing backend (#1152) is built in Rust (see "Decisions of the owner"), not run on hardware; the views and forms are not built. Issue hobnix/core#1149, milestone 0.13 "Package Registry". Child issues: Shares views #1151, pairing backend #1152,
forms #1153, guide #1154, tests #1155; the share picker comes from #1148.

A remote share is a share of another homeserver that this server mounts read-only, or a share of this server that another homeserver may
read. Today they live on the Network page and are set up by copying four values by hand. This plan moves them to **Shares** and replaces
the copying with a short-lived code that one server makes and the other types.

## Today

- **Where:** Network, tab *Remote shares* (`web/src/pages/Network.svelte`, `?tab=remote`). One table with the kinds `offer` and `mount`.
- **Give (server A):** *Give access…* (`PeerOffer.svelte`) runs `hs sys peers start offer <peer> <share>` (`scripts/peer-change.sh`, then
  `scripts/remote.sh offer`). A makes the domain user `remote-<peer>` with READ on the share and answers host, login, domain and a new
  password once, in the start answer itself (never a job, so no job log keeps it). `PeerOffered.svelte` shows them.
- **Use (server B):** the user carries the four values to B and types them into *Mount a share…* (`PeerMount.svelte`, password on stdin of
  `hs sys peers start add`). `remote.sh add` writes `/var/lib/hs/remote-<peer>.cred` into the vault (`secret_prepare`) and the row into
  `/var/lib/hs/remote-mounts`; the timer `hs-remote-mount` runs `mount-all` every 2 minutes (SMB 3, `ro`, `soft`).
- **Attach:** *Instance…* (`PeerAttach.svelte`, `hs remote attach`) gives an instance `/mnt/remote/<peer>` as a disk device (`recursive`,
  `rslave`).
- **Revoke:** *Revoke…* on A (`hs remote revoke`, deletes the login when no share is left), *Remove…* on B (`hs remote remove`),
  *New password…* on A (`offer --new-password`).
- **Contract:** `hs sys remote list` prints `kind  peer  share  host-or-login  state` (kind `offer`|`mount`, state `given`|`mounted`|`down`).

## Decisions taken

### D1. Shares gets views Local, Remote, Kept folders (not one mixed list)

The Shares page already has a *View* switch (`Segmented`, `?view=kept`). It becomes **Local** (today's list, the default, no query),
**Remote · n** (`?view=remote`) and **Kept folders · n** (`?view=kept`). `/network?tab=remote` redirects to `/shares?view=remote`; the Network
tab *Remote shares* is removed.

Reason: a remote share has other facts and other actions than a local one. A local share has a pool, a size, permissions, snapshots and a
place in the backup and parity; a remote share has a server, a direction (I use / I give), a mount state and instances it is attached to,
and it is **never** in the pool, the parity or the backup. One list would need a column set where half the cells are `–`, the pool filter
would not apply to half the rows, and a remote row next to local rows suggests it is protected like them. The cost of views (a user with
few shares clicks once more) is small: the Remote view shows its count in the label, and the Local view shows one line *"2 remote shares,
see Remote"* when there are any.

The Remote view has two blocks, *Shares I use from other servers* and *Shares I give to other servers*, each a table, and two buttons in
the page header while the view is open: **Add remote share** (primary) and **Give access**.

### D2. Transport: a code with the address as the base, the node link as the shortcut

- **Base (a):** server A (the one that gives) makes a code. The code is shown together with A's address: `K7QX-9M2D-T4PW-3HNC@alpha.local`.
  B's form has one field that takes the combined form, or the code alone plus a *Server* field. B calls A's web service (`hs-web`) with a
  value derived from the code (wire format below).
- **Shortcut (b):** when A is in B's node list (`hs sys node list`, kind `peer`, key `ok`), the *Server* field offers it by name and B claims
  over the node link instead: SSH with B's node key, a new fixed word `pair` in `scripts/node-remote.sh` (and `NODE_WORDS` in
  `scripts/node.sh`), the request on stdin. The host key is already pinned in `known_hosts`, so the fingerprint check is automatic. The code
  is still needed: the node link only lets B *look* at A, it does not let B make logins on A.
- **Not (c):** no discovery (mDNS browse, Tailscale peer list) in this plan. Typing or pasting the address once is enough, and discovery
  would announce the pairing service on the network.
- **Direction:** the first version is one way only: A (gives) makes the code, B (uses) types it. The reverse (B shows a code, A types it
  and picks the share) needs A to push credentials into B's vault, which is a second inbound door; see open question Q3.

### D3. The code

- 16 characters from the alphabet of the setup code (`scripts/first_run.py`: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, no 0 O 1 I), written as
  four groups of four: 80 bits. Typed in any case, with or without dashes or spaces (`normalize` of `first_run.py`, reused).
- 80 bits and not the 40 of the sketch in the issue: the answer is encrypted with a key derived from the code (D4), so an eavesdropper
  on plain HTTP could try codes offline against it. 40 bits fall to that in hours; 80 do not.
- **Life:** 10 minutes by default, `--minutes N` up to 60. **One use:** the first valid claim ends it, also when the later steps fail.
- **Bound to one share** and, when made from a row (*New code…*), to one server name. At most 5 open codes per server.
- **Stored on A only as derived values** in `/run/hs/remote-codes.json` (tmpfs, root, 0600, written atomically): the claim id, the answer
  key, share, server name or `-`, expiry. Never the code. Gone on reboot, removed when used or expired.

### D4. Wire format (version 1)

Both values are derived on each side from the normalized code `c` (HKDF-SHA256, empty salt):
`id = HKDF(c, "hobnix remote v1 id", 32)` (sent, hex), `key = HKDF(c, "hobnix remote v1 key", 32)` (never sent).

Request, B to A, `POST /api/remote/claim` on A's `hs-web` (no session; `http://<host>:8480`, or `https://<host>` when the host ends in
`.ts.net`), or the same JSON on stdin of `ssh <node> pair`:

```json
{"v": 1, "id": "<64 hex>", "name": "beta", "hostkey": "ssh-ed25519 AAAA…"}
```

`name` is B's host name (lower case, `^[a-z0-9][a-z0-9-]{0,19}$`), `hostkey` B's SSH host public key (A shows its fingerprint and keeps it
in `remote-offers` for *Reconnect*).

Answer 200:

```json
{"v": 1, "nonce": "<base64, 12 bytes>", "box": "<base64>"}
```

`box` is ChaCha20-Poly1305 with `key`, the nonce, and the request body bytes as associated data. Inside, JSON:
`{"server": "alpha", "host": "alpha.local", "share": "media", "login": "remote-beta", "domain": "HOME", "password": "…", "hostkey": "ssh-ed25519 …"}`.

Every refusal has the same shape and gives nothing away: `404 {"v": 1, "error": "code.unknown"}` for an unknown, expired or used code
(one answer for all three), `429 {"v": 1, "error": "code.rate"}`, `503 {"v": 1, "error": "code.unavailable"}` (no domain controller, storage
locked). The error names go into `docs/errors.md` (ADR 0028).

### D5. What each side does

On A, `remote.sh claim` (called by `hs-web` and by the `pair` word, the JSON on stdin):

1. Rate limit (below), then look up `id`. Not found: count a failure, answer `code.unknown`.
2. Remove the code (one use) before any other step.
3. Server name: the bound name, else `name` of the request. If `remote-<name>` exists for **another** server (a different stored host key),
   refuse with `code.unknown` and an event for the owner (Q4).
4. Make or reuse the login `remote-<name>` and set a **new** password every time (A never keeps a password it could hand out again), READ on
   the share, the row in `remote-offers` (one new column, the host key fingerprint; the file is internal state, `sys remote list` is not
   touched).
5. Print the inner JSON on stdout to the caller only; the caller encrypts it and answers. Event `remote.claimed` (server, share; never the
   password, never the code).

On B, `remote.sh add --code` (and `hs sys peers start add-code`):

1. Before the claim: the vault is open (`secret_prepare` would succeed), the code parses, the server address is valid. A code is never
   spent when B could not store the answer.
2. Claim (HTTP or node link), decrypt, check `hostkey`: over the node link it must match `known_hosts`; over HTTP its fingerprint is shown
   in the answer and in the row (*"Connected to alpha, key SHA256:3f9K…"*), for the user to compare with A's screen.
3. Write the password with `write_cred` (stdin, as today), the row in `remote-mounts`, mount; the same path as today's `add`. A new password
   for a server that is already set up rewrites its one `.cred` file; mounts that are up stay up until they reconnect.

### D6. Threat notes

- **Reach:** the claim endpoint is part of `hs-web`, which is plain HTTP on the LAN (`webLan`) and HTTPS through `tailscale serve`, never in
  Incus and never behind a Zoraxy rule (`ADMIN_TARGETS` in `scripts/services.py`). The handler also refuses a source that is not loopback,
  RFC 1918, link-local, IPv6 ULA or the tailnet range (100.64.0.0/10, fd7a:115c:a1e0::/48), using the same `X-Forwarded-For` rule as the
  sign-in (trusted from loopback only). The DNS rebinding check (`Host`) applies as for every request. Admin pages stay off any public route.
- **No open code, no door:** with no open code the endpoint answers `code.unknown` at once and starts nothing.
- **Guessing:** 80 bits, 10 minutes, one use. Rate limit in the code store (file lock, shared by HTTP and SSH): 5 failed claims per source
  per minute, then `429` for that source; 20 failed claims in 10 minutes from all sources end every open code (as the burn counter of
  `first_run.py`) and send an event at level warn.
- **Eavesdropping on plain HTTP:** the password travels only inside `box`; the code never travels (only `id`). An attacker who sees `id`
  and `box` must guess 80 bits offline.
- **A fake A** (a wrong address, a spoofed `.local` name): it cannot answer with a valid `box` without the code, so B refuses. The
  fingerprint compare is for the case where somebody typed the code into the wrong server.
- **Secrets:** the code and the password never go through argv, the environment or a job log (CLAUDE.md, `scripts/lib/secret.sh`). The code
  is one line on stdin of `hs sys peers start add-code` and of `hs remote add --code`; the answer of `start code` on A holds the code in
  `secret` lines of the start answer, as `offer` does today, never a background job. `hs remote offer --code` prints it to the terminal only.
  Events carry server and share, never a code, id, key or password.
- **What a code gives:** READ on one share for the login `remote-<name>`, as today's `offer`. Nothing else on A.

### D7. Names

The interface says **server** and **remote share**, never *peer*. A remote share is written `<server>/<share>` (`alpha/media`). The CLI keeps
its arguments and the state files keep their names (`<peer>` in `remote.sh` means the server name); help texts say *server*. The mount path
`/mnt/remote/<server>/<share>`, the login `remote-<name>`, the device `remote-<server>` and `remote:<peer>` in `hs sys docker mount` stay.

### D8. Revoke and renew, one place per row

| Row | Actions |
| --- | --- |
| *I use* `alpha/media` | **Instance…** (attach, detach), **Reconnect…** (type a new code from alpha: new password, same row), **Stop using…** (`remove`, red, type the server name) |
| *I give* `beta` reads `media` | **New code…** (a code bound to `beta` and this share; replaces *New password…*), **Take back…** (`revoke`, red, type the server name) |

*Reconnect* checks that the host key in the answer is the one stored for that server; a different key is refused (Q4).

### D9. CLI

- `hs remote offer <share> --code [--peer <name>] [--minutes N]`: make a code, print it once in a box with the address, the life time and
  *"Take back later with hs remote revoke <name>"*.
- `hs remote add --code [--server <name|host>] [--stdin]`: asks for the code (`ask_secret`) or reads one line on stdin. `--code` takes **no
  value**: the issue sketch `--code <code>` would put the code into argv and shell history. The code may carry `@host`; `--server` picks a
  node by name (shortcut) or gives the address.
- `hs remote codes` / `hs sys remote codes`: open codes on this server: `share  server-or-dash  expires_in`. `hs remote codes --cancel` ends
  them all.
- The old forms (`offer <share> --peer <name>`, `add <peer> <host> <share> --user ...`) keep working: for scripts, for a server without the
  web service, and as *"Enter a login by hand"* in the web form.
- New registry rows: `user remote codes`, `sys remote codes` (reads, a probe in `scripts/smoke.sh`), `sys remote claim` (the A side, stdin
  in, JSON out; called by `hs-web` and `node-remote.sh`). `sys peers plan|start` get the actions `code` and `add-code`. `sys remote list`
  keeps its shape; nothing in this plan needs a new column there (if one is needed later, it is a new row). `docs/api/sys.toml`,
  `openapi.json` and `sys.gen.d.ts` regenerated in the same commit.
- New event kinds in `scripts/lib/event-kinds.tsv`: `remote.code.made`, `remote.claimed`, `remote.claim.refused`, `remote.codes.burned`.

### D10. What stays

The SMB 3 read-only mount and its options, `mount-all` and the timer `hs-remote-mount`, `attach`/`detach` and the `rslave` device, the
state files and their places, the vault handling of the `.cred` file, the `sys remote list` lines, the domain user and its group. This plan
changes the pairing and the view, not the mount.

## Parts

1. **Shares views and the move** (web, #1151): Local, Remote, Kept folders on Shares; the Remote view with its two blocks and today's actions
   renamed (D7, D8); `/network?tab=remote` redirects; the Network tab goes; `PLAN-web-design.md` table and `i18n.js` updated. Works with
   today's backend.
2. **Pairing backend** (#1152): `scripts/remote_pair.py` (code store, HKDF, box, rate limit; tests without sleeping, clock and random source as
   parameters like `first_run.py`), `remote.sh offer --code`, `add --code`, `claim`, `codes`; `peer-change.sh` actions `code`, `add-code`;
   `POST /api/remote/claim` in `web-serve.py` (no session, source check); the `pair` word in `node-remote.sh` and `NODE_WORDS`; registry
   rows, `sys.toml`, `openapi.json`, `sys.gen.d.ts`; event kinds; error names; a row in `docs/THREAT-MODEL-web.md` for the new endpoint.
3. **Forms** (web, #1153): *Add remote share* (code field, *Server* field with the known nodes, *Enter a login by hand* fallback), *Give access*
   (share picker, *Make a code*), the code dialog (code with address, a countdown, copy; it turns into *"beta connected, key SHA256:…"* on
   the event `remote.claimed`), *Reconnect…* and *New code…*. The share picker is `ShareField` from #1148; its group *On other servers*
   lists `<server>/<share>` from `sys remote list`. Needs 1, 2 and #1148.
4. **Guide** (#1154): `docs/users-and-shares.md` "Share a folder with another server" rewritten for the code (web and CLI), the old flow kept as the
   fallback, `docs/web-interface.md`, a changelog entry, "Not tested on hardware yet" on every step.
5. **Tests** (#1155): `tests/remote-pair.sh` (expiry, one use, burn, rate limit, wrong key, answer never in argv, environment or job record),
   `web-login-test.py` (the endpoint: no session, source check, `Host` check, one refusal shape), `tests/commands.sh` rows, the smoke probe,
   and the hardware-test steps for two servers.

```
Shares views #1151 ──────────────────────────┐
Pairing backend #1152 ──► Tests #1155 ───────┼──► Forms #1153 ──► Guide #1154
ShareField #1148 ────────────────────────────┘
```

## Decisions of the owner (2026-11-24)

Answers to the open questions below (comment on #1152):

- **Q1 (cipher):** no Python `cryptography` dependency. The pairing core is Rust in `hobnix-core` (ADR 0001): `rust/hobnix-core/src/pair.rs` (code
  store, alphabet, HKDF-SHA256, ChaCha20-Poly1305, rate limit; clock and random source are parameters) with the crates `chacha20poly1305`, `hkdf`
  and `sha2` (locked in `rust/Cargo.lock`, built offline by `pkgs/hobnix.nix`). It replaces `scripts/remote_pair.py`, which is not written. The
  registry rows are `rust:` rows without a `fallback:` (there is no old implementation): `sys remote codes`, `sys remote claim`, `sys remote accept`.
  `remote.sh`, `peer-change.sh`, `node-remote.sh`, `node.sh` and `web-serve.py` stay thin glue.
- **Q2:** yes, the node link (`node.sh --pair`, word `pair`) is enough for a server without the web service.
- **Q3:** yes, the reverse direction is built: `hs remote receive` (this server shows a code), `hs remote send <share> --peer <name> --code`
  (the other one types it, makes the login and pushes the box to `POST /api/remote/push`). HTTP only; the push needs no key of the giving side.
- **Q4:** yes, a server name that is already taken is refused (`code.unknown`); a code bound to a name by the owner (`--peer`) may reuse a name that has
  no stored host key (older offers).
- **Q5:** yes, the address always shows the port (`alpha.local:8480`).

## Open questions (answered above)

- **Q1. The cipher library.** ChaCha20-Poly1305 and HKDF are not in the Python standard library. Recommended: add `ps.cryptography` to the
  system Python in `configuration.nix` (it is a NixOS package with a good record). Alternative: no encryption, and the code flow is offered
  only over the tailnet (HTTPS) or the node link (SSH), with plain-HTTP LAN servers left on the manual flow. Owner to decide.
- **Q2. A server without the web service** (`webUi` off). It can still claim (B only makes an outbound call), but it cannot be claimed from
  over HTTP. Recommended: the node link is its way in; else the manual flow. Is that enough?
- **Q3. The reverse direction** (B shows a code, A types it and picks the share). Left out of the first version, because A would have to push
  a password into B's vault through a second open endpoint. Wanted later, or never?
- **Q4. A name that is taken.** When `remote-beta` on A belongs to a server with another host key: refuse (recommended, the owner renames with
  `--peer`), or take it over?
- **Q5. Port.** The base uses `8480` (the default `HS_WEB_PORT`). A server with another port has to give `@host:port`. Should the code
  dialog always show the port?

## Not tested on hardware yet

Nothing in this plan was run. The pairing needs two real servers on one LAN and, for the tailnet path, on one tailnet: make a code on A,
claim it on B through the web and through `hs remote add --code`, see the share mounted and the fingerprints match on both screens, try the
same code twice (refused), wait 11 minutes with a new code (refused), try six wrong codes (429), check `journalctl` and the job records on
both servers for the code or the password (none), *Take back* on A and see B's mount fail its next round, *Reconnect* on B with a new code.
