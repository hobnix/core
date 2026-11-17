"""Console scenarios of the test-lab stages 3 to 5 (hobnix/server#432), run by nested_lib.py on an INSTALLED VM (the one stage 1 made).

UNVERIFIED: written without Incus, KVM or nix. Not tested on hardware yet. The commands are the real `hs` commands of this repository, but no
step ran against a real system; the first real run will show which one needs a different prompt or option.

Adding a stage (for example the upgrade test, #435) is one entry in SCENARIOS: a function (params) -> list of steps (see
nested_lib.build_scenario for the kinds; `login` and the `strip` option of `capture` are added here and in run_steps). Nothing else in this file
changes. params: password (of adminuser), hostname, backup_pass (the restic password of the stage `backup`, only for `restore`), disks (the
Incus device names of the virtual disks a stage may use: dict name -> device name).
"""

import os

LOGIN = r"\n[^\n]*login: $"


POOL = "bulk"   # the pool name of the stages (a name that is spelled once, tests/pool-names-ratchet.sh)
ROOT = "/" + POOL
SHARES = ROOT + "/shares"


def _q(s):
    return "'" + s.replace("'", "'\\''") + "'"


def step(kind, text, **kw):
    d = {"kind": kind, "text": text}
    d.update(kw)
    return d


def full_system(params):
    """A system installed as `homeserver` has only the base until `hs rebuild` has built the full configuration (restic and SnapRAID come with
    it). That configuration always imports a ZFS pool named `fast`, so, as on a real server (docs/install.md), the pool comes first: a mirror
    of two small virtual disks (`hs pool fast add`), then `hs rebuild`. (The VM was installed with --bulk-type snapraid: nested_lib.py.) Safe to run twice."""
    return [
        disk_id_by_name(params, "fast1", "f1"),
        disk_id_by_name(params, "fast2", "f2"),
        # the plan first: its text (and a refusal's reason) stays in the console log
        step("run_var", "zpool list fast >/dev/null 2>&1 || HS_CALLER=test hs sys pool plan fast add --use apps --disks {f1},{f2}; true", what="the plan of the pool fast is shown"),
        step("run_var", "zpool list fast >/dev/null 2>&1 || HS_CALLER=test hs sys pool start fast add --use apps --disks {f1},{f2} --confirm fast",
             timeout=120, what="the pool fast (a mirror of two virtual disks) is started"),
        step("run", "for i in $(seq 1 120); do zpool list fast >/dev/null 2>&1 && break; sleep 5; done; zpool list fast >/dev/null 2>&1",
             timeout=900, what="the pool fast exists"),
        step("run", "command -v restic >/dev/null && command -v mkfs.ext4 >/dev/null && command -v snapraid >/dev/null || hs rebuild --foreground",
             timeout=3000, what="the full configuration is built (hs rebuild)"),
    ]


def login_root(params):
    """Reach a root shell on the console of an installed VM: log in as adminuser when a login prompt is shown, then `sudo -i`."""
    user, pw = "adminuser", params["password"]
    return [
        step("login", "", user=user, secret=pw, timeout=420, what="the console is logged in as adminuser"),
        step("run", "sudo -k", what="sudo forgets an earlier password (it would not ask again, and the password would be typed into the root shell)"),
        step("send", "sudo -i"),
        step("wait", r"\[sudo\] password for %s: ?$" % user, timeout=30, what="sudo asks for the password"),
        step("send_secret", pw),
        # what is typed while sudo still checks the password is thrown away (sudo flushes the terminal input): wait for root's first prompt,
        # the plain bash one or the two-line starship prompt (its first line is "root <host> <dir>")
        step("wait", r"(?:\[root@[^\]]*\]# |root nested-test )", timeout=60, what="sudo gave a root shell"),
        # after the full configuration (hs rebuild) root's shell is zsh with a two-line starship prompt: the harness cannot wait for it. A plain
        # bash with a prompt of its own shape is the same on every system
        step("send", "PS1='[root@nested-test:\\w]# ' exec bash --norc --noprofile"),
        step("wait", r"\[root@[^\]]*\]# ", timeout=60, what="a root shell"),
        # the serial console is 80 columns wide: a long command line wraps, and the redraw of the line editor puts a space or a prompt into the
        # middle of the end marker (seen as "__ HSN9__" in run 20)
        step("run", "stty cols 500", what="the console is wide enough for a long command line"),
    ]


def disk_by_name(params, key, var):
    """A step that finds the virtual disk (an Incus disk device named params['disks'][key]) in the VM: /dev/disk/by-id/...incus_<name>."""
    name = params["disks"][key]
    return step("capture", "readlink -f /dev/disk/by-id/*incus_%s | head -n1" % name, var=var, strip=True, what="the virtual disk %s is visible" % key)


def disk_id_by_name(params, key, var):
    """The /dev/disk/by-id name of the virtual disk: `hs pool ... --disks` takes by-id names (manage-pool.sh), not sdX."""
    name = params["disks"][key]
    return step("capture", "ls /dev/disk/by-id/ | grep 'incus_%s$' | head -n1" % name, var=var, strip=True, what="the by-id name of the virtual disk %s" % key)


# ---------------------------------------------------------------- stage 3: a bad update rolls back by itself
def rollback(params):
    """Put a bad commit on a local origin of /etc/nixos (it makes sshd fail to start after the switch), run `hs update --yes`, and expect that the
    update goes back to the previous generation by itself and sshd runs again (scripts/update.sh, scripts/rebuild.sh rollback_now)."""
    # sshd must exist and fail to start: with services.openssh.enable = false the unit is gone after the switch, and post_check in
    # scripts/rebuild.sh (it only looks at an sshd unit that exists) finds nothing wrong, so no rollback would be due
    bad = '{ lib, pkgs, ... }: { systemd.services.sshd.serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/false"; }'
    # on a homeserver VM (disks for the pool fast given) the full configuration comes first: without the pool fast the switch of the update fails
    # for that reason, and the bad sshd module would never be reached
    prep = full_system(params) if "fast1" in params.get("disks", {}) else []
    return login_root(params) + prep + [
        step("capture", "readlink /run/current-system", var="before", strip=True, what="the generation before the update"),
        # the rollback goes back to the generation, not to the files: the bad commit stays in /etc/nixos and the next rebuild would apply it again
        # (stages 4 and 5 run on this VM afterwards), so the stage puts the checkout back where it was
        step("capture", "git -C /etc/nixos rev-parse HEAD", var="orig", strip=True, what="the commit of /etc/nixos before the stage"),
        step("capture", "git -C /etc/nixos remote get-url origin", var="origin", strip=True, what="the address of origin before the stage"),
        # the ISO of a ref that is not in develop leaves /etc/nixos on a detached HEAD (scripts/lib/checkout.sh): the stage needs a branch to push
        step("run", "git -C /etc/nixos symbolic-ref -q HEAD >/dev/null || git -C /etc/nixos switch -q -c hs-testlab", what="/etc/nixos is on a branch"),
        step("capture", "git -C /etc/nixos symbolic-ref --short HEAD", var="branch", strip=True, what="the name of the branch"),
        step("run", "rm -rf /var/tmp/hs-lab-origin.git /var/tmp/hs-lab-work && git init -q --bare /var/tmp/hs-lab-origin.git", what="a local origin for /etc/nixos"),
        step("run_var", "git -C /etc/nixos push -q /var/tmp/hs-lab-origin.git HEAD:refs/heads/{branch}", what="the current state goes to the local origin"),
        step("run", "git -C /etc/nixos remote set-url origin /var/tmp/hs-lab-origin.git && git -C /etc/nixos fetch -q origin", what="/etc/nixos follows the local origin"),
        step("run_var", "git -C /etc/nixos branch -q --set-upstream-to=origin/{branch}", what="the branch tracks it"),
        # the stable channel follows the newest release tag, and the VM knows v0.1.0 from the ISO's checkout: `hs update` would never look at the
        # bad commit. Without a tag it follows the current branch (scripts/update.sh).
        step("run", "git -C /etc/nixos tag -l | xargs -r git -C /etc/nixos tag -d >/dev/null", what="no release tag: the update follows the branch"),
        step("run_var", "git clone -q -b {branch} /var/tmp/hs-lab-origin.git /var/tmp/hs-lab-work", what="a work copy for the bad commit"),
        step("run", "printf '%%s\\n' %s > /var/tmp/hs-lab-work/hs-testlab-bad.nix" % _q(bad), what="the bad module (sshd off)"),
        step("run", "sed -i 's|imports = \\[ ./hardware-configuration.nix \\]|imports = [ ./hardware-configuration.nix ./hs-testlab-bad.nix ]|' "
                    "/var/tmp/hs-lab-work/configuration.nix && grep -q hs-testlab-bad /var/tmp/hs-lab-work/configuration.nix",
             what="configuration.nix imports it"),
        step("run_var", "cd /var/tmp/hs-lab-work && git add hs-testlab-bad.nix configuration.nix && "
                        "git -c user.name=testlab -c user.email=testlab@localhost commit -q -m 'bad update' && git push -q origin HEAD:{branch}; cd /",
             what="the bad update is published"),
        # the update builds the new system, switches, finds sshd stopped and goes back; its exit code is not the point, the state afterwards is
        step("capture", "hs update --yes 2>&1 | tail -n 40", var="update_out", timeout=2400, strip=True, what="hs update --yes runs (and goes back)"),
        step("run", "systemctl is-active sshd", timeout=120, what="sshd runs again after the update"),
        step("run_var", "test \"$(readlink /run/current-system)\" = {before}", what="the system is on the generation from before the update"),
        step("run", "test ! -e /etc/nixos/hs-testlab-bad.nix || ! systemctl is-active sshd | grep -qv '^active$'", what="the bad change is not live"),
        step("run_var", "git -C /etc/nixos reset -q --hard {orig} && git -C /etc/nixos remote set-url origin {origin} && "
                        "rm -rf /var/tmp/hs-lab-origin.git /var/tmp/hs-lab-work && test ! -e /etc/nixos/hs-testlab-bad.nix",
             what="/etc/nixos is back at its commit, without the bad module"),
    ]


# ---------------------------------------------------------------- stage 4: backup on this VM, restore onto a second clean VM
def backup(params):
    """On the first VM: set up the backup disk (a virtual disk), write a marker file into /var/lib/hs, back up, check the snapshot, and keep the
    restic password stays in the VM: testlab.sh pulls /var/lib/hs/restic-password with `incus file pull`, never through the console log."""
    return login_root(params) + full_system(params) + [
        disk_by_name(params, "backup", "dev"),
        step("run_var", "test -b {dev}", what="the backup disk is a block device"),
        step("run_var", "HS_BACKUP_YES=1 hs backup init {dev}", timeout=300, what="hs backup init makes the disk the backup disk"),
        step("run", "mkdir -p /var/lib/hs && echo hs-testlab-marker > /var/lib/hs/testlab-marker", what="a marker file in the state folder"),
        step("run", "hs backup now --foreground", timeout=1800, what="hs backup now finishes"),
        step("run", "hs backup list | grep -q .", what="a snapshot is listed"),
        step("run", "hs backup verify --foreground", timeout=900, what="hs backup verify passes"),
        step("run", "sync && umount /var/lib/hs-backup 2>/dev/null; sync", expect_rc=None, what="the disk is quiet before it is moved"),
    ]


def restore(params):
    """On the second, clean VM (a fresh install): the backup disk was moved here. Read the host snapshot from the disk with only the backup
    password (hs backup config restore --from-disk) and expect the marker file of the first VM back."""
    pw = params["backup_pass"]
    return login_root(params) + full_system(params) + [
        disk_by_name(params, "backup", "dev"),
        step("run_var", "test -b {dev}", what="the backup disk is attached to the second VM"),
        step("run", "test ! -e /var/lib/hs/testlab-marker", what="the second VM is clean: no marker yet"),
        step("send_var", "HS_BACKUP_YES=1 hs backup config restore --from-disk {dev} latest --with-state; echo \"__RESTORED__ rc=$?\"",
             what="hs backup config restore --from-disk starts"),
        step("wait", r"[Pp]assphrase[^\n]*: ?$", timeout=120, what="it asks for the backup password"),
        step("send_secret", pw),
        step("wait", r"__RESTORED__ rc=0", timeout=900, what="the restore finished"),
        step("run", "grep -qx hs-testlab-marker /var/lib/hs/testlab-marker", what="the marker file of the first VM is back"),
    ]


# ---------------------------------------------------------------- stage 5: a pool and the file manager on virtual disks
FM_HELPERS = (
    # cs <dir>: one checksum over all files below a folder (names and content); fmgo <names> <start args...>: start a job, wait, succeed when it is done;
    # fmcn <names> <plan args...>: the confirm_name of a plan.
    "cs() { (cd \"$1\" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum | sha256sum | cut -c1-64); }; "
    "fmgo() { n=$1; shift; printf '%s\\0' $n | HS_CALLER=test hs sys fm start \"$@\" > /tmp/fm.out 2>&1 || return 1; "
    "u=$(awk -F'\\t' '$1==\"unit\"{print $2}' /tmp/fm.out); for i in $(seq 150); do r=$(hs sys fm progress $u | awk -F'\\t' '$1==\"result\"{print $2}'); "
    "[ \"$r\" = running ] || break; sleep 2; done; echo \"$r\" > /tmp/fm.result; [ \"$r\" = done ]; }; "
    "fmcn() { n=$1; shift; printf '%s\\0' $n | hs sys fm plan \"$@\" | awk -F'\\t' '$1==\"confirm_name\"{print $2}'; }"
)


def write_checks(tag, la, pa, ra, lb, pb, rb, confirm):
    """The write checks of the file manager between two locations: la (location id) with fm path pa, and ra = the same folder as the system sees it;
    lb, pb, rb the same for the target. confirm = the name the overwrite choice asks to be typed (the last folder of the target path, or the location
    name). Every step that moves data compares checksums before and after. Names start with the tag, so two runs on one pool do not meet."""
    s = "%s-src" % tag
    a = "%s/%s" % (ra, s)
    b = "%s/%s" % (rb, s)
    fa = "--from %s --path '%s'" % (la, pa)
    fb = "--from %s --path '%s'" % (lb, pb)
    to = "--to %s --to-path '%s'" % (lb, pb)
    return [
        step("run", "mkdir -p %s/sub && head -c 1048576 /dev/urandom > %s/f1 && head -c 524288 /dev/urandom > %s/f2 && echo three > %s/sub/f3" % (a, a, a, a),
             what="[%s] a test folder with three files" % tag),
        step("run", "cs %s > /tmp/%s.c1; fmgo %s copy %s %s" % (a, tag, s, fa, to), timeout=400, what="[%s] copy a folder %s to %s" % (tag, la, lb)),
        step("run", "[ \"$(cs %s)\" = \"$(cat /tmp/%s.c1)\" ] && [ -d %s ]" % (b, tag, a), what="[%s] the copy has the same checksum, the source is still there" % tag),
        # move: the source goes only after the target is verified
        step("run", "mkdir -p %s/%s-mv && head -c 786432 /dev/urandom > %s/%s-mv/m1 && cs %s/%s-mv > /tmp/%s.c2; fmgo %s-mv move %s %s"
             % (ra, tag, ra, tag, ra, tag, tag, tag, fa, to), timeout=400, what="[%s] move a folder %s to %s" % (tag, la, lb)),
        step("run", "[ \"$(cs %s/%s-mv)\" = \"$(cat /tmp/%s.c2)\" ] && [ ! -e %s/%s-mv ]" % (rb, tag, tag, ra, tag),
             what="[%s] moved: same checksum there, gone from the source" % tag),
        # rename
        step("run", "fmgo %s-mv rename %s --newname %s-moved" % (tag, fb, tag), timeout=120, what="[%s] rename the moved folder" % tag),
        step("run", "[ -d %s/%s-moved ] && [ ! -e %s/%s-mv ] && [ \"$(cs %s/%s-moved)\" = \"$(cat /tmp/%s.c2)\" ]" % (rb, tag, rb, tag, rb, tag, tag),
             what="[%s] renamed, content unchanged" % tag),
        # mkdir
        step("run", "fmgo '' mkdir %s --newname %s-made && [ -d %s/%s-made ]" % (fb, tag, rb, tag), timeout=120, what="[%s] make a folder" % tag),
        # overwrite choice: a changed source file; without the typed confirmation the start is refused and nothing changes
        step("run", "echo changed-%s > %s/f1 && cs %s > /tmp/%s.c3 && cs %s > /tmp/%s.c4" % (tag, a, a, tag, b, tag),
             what="[%s] the source file differs from the copy now" % tag),
        step("run", "! (printf '%s\\0' | HS_CALLER=test hs sys fm start copy %s %s --conflict overwrite) && [ \"$(cs %s)\" = \"$(cat /tmp/%s.c4)\" ]" % (s, fa, to, b, tag),
             what="[%s] overwrite without the typed confirmation is refused, nothing changed" % tag),
        step("run", "fmgo %s copy %s %s --conflict overwrite --confirm '%s'" % (s, fa, to, confirm), timeout=400,
             what="[%s] overwrite with the confirmation" % tag),
        step("run", "[ \"$(cs %s)\" = \"$(cat /tmp/%s.c3)\" ]" % (b, tag), what="[%s] the target now has the changed content" % tag),
        # delete: the plan names the confirmation, a wrong one is refused, the right one deletes
        step("run", "cn=$(fmcn %s-moved delete %s); echo \"$cn\" | grep -q '^delete [0-9]* file' && echo \"$cn\" > /tmp/%s.cn" % (tag, fb, tag),
             what="[%s] the delete plan asks for 'delete N files'" % tag),
        step("run", "! (printf '%s-moved\\0' | HS_CALLER=test hs sys fm start delete %s --confirm 'delete 99 files') && [ -d %s/%s-moved ]" % (tag, fb, rb, tag),
             what="[%s] delete with a wrong confirmation is refused, the folder is still there" % tag),
        step("run", "fmgo %s-moved delete %s --confirm \"$(cat /tmp/%s.cn)\" && [ ! -e %s/%s-moved ]" % (tag, fb, tag, rb, tag), timeout=120,
             what="[%s] delete with the right confirmation" % tag),
        # cancel: a big move is stopped; afterwards the data is whole in one place: intact at the source, or gone from it and complete at the target
        step("run", "mkdir -p %s/%s-big && head -c 1500000000 /dev/zero > %s/%s-big/big && cs %s/%s-big > /tmp/%s.c5" % (ra, tag, ra, tag, ra, tag, tag),
             timeout=300, what="[%s] a big folder to cancel" % tag),
        step("run", "printf '%s-big\\0' | HS_CALLER=test hs sys fm start move %s %s > /tmp/fm.out; u=$(awk -F'\\t' '$1==\"unit\"{print $2}' /tmp/fm.out); sleep 1; "
                    "hs sys jobs stop \"$u\"; sleep 5; hs sys fm progress \"$u\" | grep -q 'result.*\\(cancelled\\|done\\)'" % (tag, fa, to), timeout=120,
             what="[%s] start a move and stop the job" % tag),
        step("run", "if [ -e %s/%s-big/big ]; then [ \"$(cs %s/%s-big)\" = \"$(cat /tmp/%s.c5)\" ]; else [ \"$(cs %s/%s-big)\" = \"$(cat /tmp/%s.c5)\" ]; fi"
                    % (ra, tag, ra, tag, tag, rb, tag, tag),
             what="[%s] after the stop the data is whole in one place (nothing unverified was removed)" % tag),
    ]


def _bulk_steps(params, kind):
    extra = " --role data --fs ext4" if kind == "snapraid" else ""
    return login_root(params) + full_system(params) + [
        step("run", "export HS_CALLER=test", what="hs sys commands typed by hand do not ask (scripts/lib/hs.sh sys_guard)"),
        disk_by_name(params, "pool1", "d1"),
        disk_by_name(params, "pool2", "d2"),
        disk_id_by_name(params, "pool1", "i1"),
        disk_id_by_name(params, "pool2", "i2"),
        step("run_var", "test -b {d1} && test -b {d2}", what="both virtual disks are block devices"),
        step("capture", "hs sys pool start %s add --disks $(basename {d1}),$(basename {d2}) --use data --kind %s%s --confirm %s" % (POOL, kind, extra, POOL), var="start",
             timeout=120, strip=True, what="the %s pool is created as a background job" % kind),
        step("run_var", "echo {start} | grep -q 'status.*started'", what="the job started"),
        step("run", "for i in $(seq 1 360); do systemctl list-units 'hs-job-pool-*' --state=active,activating --no-legend | grep -q . || break; sleep 5; done",
             timeout=1800, what="the pool job finishes"),
        step("run", "hs pool %s | grep -q data" % POOL, what="hs pool lists the pool"),
        step("run", "mountpoint -q " + ROOT, what="the pool is mounted"),
        step("run", "hs config set fileManagerWrite true", what="the file manager may write"),
        step("run", FM_HELPERS, what="helper functions for the checks (checksums, wait for a job)"),
        step("run", "hs share add hslab1 && hs share add hslab2 && [ -d %s/hslab1 ] && [ -d %s/hslab2 ]" % (SHARES, SHARES), what="two shares for share to share"),
    ]


def pool(params):
    """Stage `pool`: a SnapRAID data pool of two data disks (no parity). The file manager is read only until fileManagerWrite is on (scripts/fm.sh), so it
    is switched on first. Then the full write list (docs/PLAN-storage-nas.md step 2, #425): copy, move, rename, mkdir, overwrite, delete, cancel, disk to
    disk and share to share, and the guard: a pool disk and the pool view of its array are never the two sides of one job."""
    dk = "/var/lib/hs/disks"
    return _bulk_steps(params, "snapraid") + [
        step("run", "hs sys fm locations | grep -q 'disk:data-01' && hs sys fm locations | grep -q 'disk:data-02'", what="the file manager sees both data disks"),
        step("run", "mkdir -p %s/data-01/shares/hslab-a %s/data-02/shares/hslab-b && hs sys fm ls disk:data-01 --path shares/hslab-a | grep -q status" % (dk, dk),
             what="a folder on each data disk, the file manager lists it"),
    ] + write_checks("dd", "disk:data-01", "shares/hslab-a", dk + "/data-01/shares/hslab-a",
                     "disk:data-02", "shares/hslab-b", dk + "/data-02/shares/hslab-b", "hslab-b") \
      + write_checks("ss", "share:hslab1", "", SHARES + "/hslab1", "share:hslab2", "", SHARES + "/hslab2", "hslab2") + [
        # the guard
        step("run", "hs sys fm pair disk:data-01 pool:%s | grep -q 'status.refused'" % POOL, what="the guard: a pool disk and the pool view are refused as a pair"),
        step("run", "out=$(printf 'dd-src\\0' | HS_CALLER=test hs sys fm start copy --from disk:data-01 --path shares/hslab-a --to pool:%s --to-path shares/hslab2 2>&1); rc=$?; "
                    "[ $rc -ne 0 ] && echo \"$out\" | grep -q refused" % POOL, what="the guard: a start with that pair refuses"),
    ]


def poolzfs(params):
    """Stage `poolzfs`: the same write list on a ZFS data pool (a mirror of the two virtual disks), on a VM whose two disks are still empty. A ZFS pool has
    no data disks, so the pairs are share to share and share to the pool view."""
    return _bulk_steps(params, "zfs") + [
        step("run", "hs sys fm locations | grep -q pool:" + POOL, what="the file manager sees the pool"),
        step("run", "mkdir -p " + SHARES + "/hslab2/zz-in", what="a folder in the pool view"),
    ] + write_checks("ss", "share:hslab1", "", SHARES + "/hslab1", "share:hslab2", "", SHARES + "/hslab2", "hslab2") \
      + write_checks("sp", "share:hslab1", "", SHARES + "/hslab1", "pool:" + POOL, "shares/hslab2/zz-in", SHARES + "/hslab2/zz-in", "zz-in")


def unraid(params):
    """Stage `unraid` (docs/PLAN-storage-nas.md step 7, #460 a): three still empty virtual disks are made the way Unraid makes them (one partition from
    sector 64, xfs in it, files owned 99:100, the same top folder on both data disks; a parity disk with a partition and no file system), then only
    the read-only side runs: `hs migrate check` and the adopt `--dry-run` plan. The checksum of each partition before and after proves nothing was
    written. Keys of HS_NESTED_DISKS: unraid1, unraid2 (data), unraidp (parity, smaller). Not tested on hardware yet."""
    fxp = "fxp() { lsblk -nrpo PATH,TYPE $1 | awk '$2==\"part\"{print $1; exit}'; }"
    mk = ("mkunraid() { d=$1; printf 'label: gpt\\nfirst-lba: 34\\nstart=64\\n' | sfdisk -q $d && partprobe $d && udevadm settle; p=$(fxp $d); "
          "mkfs.xfs -q -f $p && mkdir -p /mnt/unraid-fx && mount $p /mnt/unraid-fx && mkdir -p /mnt/unraid-fx/Media /mnt/unraid-fx/Shared /mnt/unraid-fx/Own-$2 && "
          "echo film-$2 > /mnt/unraid-fx/Media/$2.mkv && echo shared-$2 > /mnt/unraid-fx/Shared/$2.txt && chown -R 99:100 /mnt/unraid-fx/Media /mnt/unraid-fx/Shared /mnt/unraid-fx/Own-$2 && "
          "umount /mnt/unraid-fx; }")
    return login_root(params) + [
        disk_by_name(params, "unraid1", "u1"),
        disk_by_name(params, "unraid2", "u2"),
        disk_by_name(params, "unraidp", "up"),
        step("run_var", "test -b {u1} && test -b {u2} && test -b {up}", what="the three virtual disks are block devices"),
        step("run", "command -v mkfs.xfs sfdisk partprobe >/dev/null", what="the tools to build the fixtures are installed"),
        step("run", fxp, what="a helper that names the partition of a disk"),
        step("run", mk, what="a helper that builds one Unraid data disk"),
        step("run_var", "mkunraid {u1} one && mkunraid {u2} two", timeout=300, what="two data disks: partition 1, xfs, files 99:100, the same top folder"),
        step("run_var", "printf 'label: gpt\\nfirst-lba: 34\\nstart=64\\n' | sfdisk -q {up} && partprobe {up}", what="a parity disk: a partition, no file system"),
        step("run_var", "for d in {u1} {u2}; do blkid -p -o export $(fxp $d); done | sha256sum > /tmp/unraid-before", what="the superblocks are noted"),
        step("run", "hs migrate check --parity $(basename {up}) | tee /tmp/unraid-check.out | grep -q xfs", what="migrate check lists the xfs disks"),
        step("run", "grep -q 'can be adopted' /tmp/unraid-check.out", what="migrate check: they can be adopted"),
        step("run_var", "hs pool %s add --role adopt --disks $(basename {u1}),$(basename {u2}) --merge --dry-run | tee /tmp/unraid-plan.out | grep -q Own-one" % POOL,
             what="the adopt plan lists the folder of the first disk"),
        step("run", "grep -q 'merged with folders of the same name' /tmp/unraid-plan.out && grep -q Shared /tmp/unraid-plan.out", what="the plan merges the shared top folder"),
        step("run_var", "for d in {u1} {u2}; do blkid -p -o export $(fxp $d); done | sha256sum | cmp - /tmp/unraid-before", what="nothing was written to the data disks"),
    ]


# ---------------------------------------------------------------- stage 6 (browser): the address of the VM
def address(params):
    """Read the IPv4 address of the VM from its own serial console. `incus list` shows none (no incus agent in the installed system, and the VM
    sits on a LAN bridge Incus does not manage), so testlab.sh stage_browser reads the value recorded here from result-address.json."""
    return [
        step("login", "", user="adminuser", secret=params["password"], timeout=420, what="the console is logged in as adminuser"),
        step("capture", "ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -n1", var="ip", strip=True, record=True,
             what="the VM has a global IPv4 address"),
        step("run_var", "echo {ip} | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'", what="it looks like an IPv4 address"),
    ]


def upgrade_steps(params):
    """Stage upgrade (#435): the system installed from the LAST release ISO is set up (a share, one app), `hs update` moves it to the candidate
    (a branch of the Hobnix repository that the old checkout is pointed at), and it must still be healthy with its shares, state.db and app.
    Not tested on hardware yet: the command lines are written from the scripts, never run in a VM."""
    user, pw = "adminuser", params["password"]
    cand = params.get("candidate") or os.environ.get("HS_NESTED_CANDIDATE") or "<candidate-branch>"   # the branch the server updates to
    repo = params.get("candidate_repo") or os.environ.get("HS_NESTED_CANDIDATE_REPO") or "https://github.com/hobnix/server.git"
    app, share = params.get("app") or os.environ.get("HS_NESTED_UPGRADE_APP", ""), "upgrade-test"
    db = "/var/lib/hs/state.db"
    ver = "python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(\"PRAGMA user_version\").fetchone()[0])' " + db
    rows = ("python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(\"SELECT count(*) FROM events\").fetchone()[0])' " + db)
    # adminuser has to type the password for sudo (as on a real server): the stage works in a root shell, like the others
    steps = login_root(params) + [
        step("run", "systemctl is-system-running --wait | grep -Eq '^(running|degraded)$'", timeout=300, what="the old release finished starting"),
        # set up what a server in the field has
        step("run", "hs config set timeZone Europe/Vienna", timeout=300, what="a setting is changed on the old release (a share needs the storage pool, a minimal system has none)"),
        step("run", "grep -q Vienna /etc/nixos/machine.toml", what="the setting is in machine.toml"),
    ]
    if app:
        steps += [step("run", "hs pkg install %s --yes" % _q(app), timeout=1800, what="one app is installed on the old release")]
    steps += [
        step("run", "git -C /etc/nixos rev-parse HEAD > /var/tmp/upgrade-rev-before", what="the revision of the old release is noted"),
        step("run", "cp /etc/nixos/machine.toml /var/tmp/upgrade-machine-before", what="machine.toml of the old release is kept"),
        step("run", "%s > /var/tmp/upgrade-schema-before && %s > /var/tmp/upgrade-events-before" % (ver, rows), what="the state.db schema version and event count are noted"),
        # The stable channel follows the newest signed release tag (v0.1.0 is the newest: "already the latest"), and a candidate is no tag yet. The
        # channel edge follows origin/develop: the candidate becomes `develop` of a bare repository in the VM, and origin points there (no network needed)
        step("run", "git -C /etc/nixos fetch origin +refs/heads/%s:refs/remotes/origin/candidate" % _q(cand), timeout=600, what="the candidate branch is fetched"),
        step("run", "git init -q --bare /var/tmp/candidate.git && git -C /etc/nixos push -q /var/tmp/candidate.git refs/remotes/origin/candidate:refs/heads/develop --tags", what="the candidate is `develop` of a local repository"),
        step("run", "chown -R \"$(stat -c %U /etc/nixos)\" /var/tmp/candidate.git && git -C /etc/nixos remote set-url origin /var/tmp/candidate.git", what="origin is that repository"),
        step("run", "hs config set updateChannel edge", what="the update channel is edge"),
        step("run", "hs update --yes --foreground", timeout=3600, what="hs update moves the server to the candidate"),
        # the checks
        step("run", "test \"$(git -C /etc/nixos rev-parse HEAD)\" != \"$(cat /var/tmp/upgrade-rev-before)\"", what="the checkout moved to a new revision"),
        step("run", "systemctl is-system-running --wait | grep -Eq '^(running|degraded)$'", timeout=300, what="the updated system is running"),
        step("run", "grep -q Vienna /etc/nixos/machine.toml", what="the setting survived the update"),
        step("run", "test -s /etc/nixos/machine.toml && grep -q . /var/tmp/upgrade-machine-before", what="machine.toml is still there and not empty"),
        step("run", "test \"$(%s)\" -ge \"$(cat /var/tmp/upgrade-schema-before)\"" % ver, what="the state.db schema version did not go back"),
        step("run", "test \"$(%s)\" -ge \"$(cat /var/tmp/upgrade-events-before)\"" % rows, what="state.db kept its events"),
        # a minimal system has no incus, ZFS, restic ...: smoke reports those as failed checks (18 of 97 in run 35), so the exit code says nothing here. What an upgrade can break is a script: smoke has to run through without script errors
        step("run", "hs smoke > /var/tmp/upgrade-smoke 2>&1; grep -q 'Checks:' /var/tmp/upgrade-smoke && ! grep -Eq 'syntax error|Traceback|unbound variable|bad substitution' /var/tmp/upgrade-smoke", timeout=900, what="hs smoke runs through on the updated system without a script error"),
        step("run", "hs health", timeout=120, what="hs health reports no problem"),
    ]
    if app:
        steps += [step("run", "hs pkg list | grep -q %s" % _q(app), what="the app is still installed")]
    return steps


SCENARIOS = {
    "rollback": rollback,
    "backup": backup,
    "restore": restore,
    "pool": pool,
    "poolzfs": poolzfs,
    "unraid": unraid,
    "address": address,
    "upgrade": upgrade_steps,
}
