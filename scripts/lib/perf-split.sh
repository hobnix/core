# shellcheck shell=bash
# shellcheck disable=SC2034  # the ps_ results are for the script that sources this file
# Where the time of one read goes (hs timing --split, issue #1333); sourced by read-timing.sh. Nothing on the system changes: for the measured process
# only, PATH gets two private folders of stand-ins that are removed afterwards.
#   - tools/: one stand-in per external tool that is installed. It runs the real tool with the same arguments and notes its start, end and CPU time.
#     Only the tool's name is written down, never its arguments or its output.
#   - bash/: a stand-in for the first `bash` the dispatcher starts, which is the hand-over to the read's script. A process keeps its CPU time across
#     exec, so at that moment it has the dispatcher's own CPU time and that of everything the dispatcher waited for.
# Parts of one read: dispatcher (start to hand-over), tools, rest (all else: the script, its shells, Python, jq, awk ...).
# Not seen: CPU of a daemon a tool talks to (incusd, smbd, systemd), a tool called by its full path (it counts as rest), a process nobody waits for.
#   perf_split_setup <folder>   write the stand-ins into an empty private folder
#   perf_split_run <command...> run it with the stand-ins; sets ps_rc and (seconds, `-` = unknown) ps_disp_wall ps_disp_cpu ps_tool_wall
#                               ps_tool_cpu ps_tool_calls ps_rest_wall ps_rest_cpu ps_total_wall
# Knob: HS_PERF_TOOLS (space separated names of the external tools).
perf_tools_default="zpool zfs incus docker smartctl lsblk blkid findmnt df du systemctl systemd-run journalctl loginctl timedatectl networkctl resolvectl restic rsync snapraid mergerfs cryptsetup dmsetup hdparm nvme udevadm sensors nvidia-smi upsc smbstatus smbcontrol testparm pdbedit wbinfo samba-tool net ip ss nft iptables tailscale curl ssh ping nix nix-env nix-store nixos-version nixos-rebuild git sqlite3 btrfs xfs_admin lspci lsusb dmidecode"

perf_split_setup() {   # perf_split_setup <folder>
  ps_dir=$1
  ps_bash=$BASH
  mkdir -p "$ps_dir/tools" "$ps_dir/bash" "$ps_dir/calls" || return 1
  local name real q_calls q_tools
  printf -v q_calls '%q' "$ps_dir/calls"
  printf -v q_tools '%q' "$ps_dir/tools:"
  for name in ${HS_PERF_TOOLS:-$perf_tools_default}; do
    [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] && real=$(type -P "$name") && [ -n "$real" ] || continue
    case "$real" in /*) ;; *) continue ;; esac
    # the real tool runs without this folder in PATH, so a tool that starts another one is counted once
    {
      printf '#!%s\n' "$ps_bash"
      printf 't0=$EPOCHREALTIME\n'
      printf 'out=%s\n' "$q_tools"
      printf 'PATH=${PATH//"$out"/} %q "$@"\n' "$real"
      printf 'rc=$?\n'
      printf '{ printf "%%s %%s\\n" "$t0" "$EPOCHREALTIME"; times; } > %s/"$$.$RANDOM" 2>/dev/null\n' "$q_calls"
      printf 'exit "$rc"\n'
    } > "$ps_dir/tools/$name"
    chmod +x "$ps_dir/tools/$name"
  done
  local q_hand q_bashdir q_real
  printf -v q_hand '%q' "$ps_dir/handoff"
  printf -v q_bashdir '%q' "$ps_dir/bash:"
  printf -v q_real '%q' "$ps_bash"
  {
    printf '#!%s\n' "$ps_bash"
    printf '[ -e %s ] || { printf "%%s\\n" "$EPOCHREALTIME"; times; } > %s 2>/dev/null\n' "$q_hand" "$q_hand"
    printf 'out=%s\n' "$q_bashdir"
    printf 'PATH=${PATH//"$out"/}\n'
    printf 'exec %s "$@"\n' "$q_real"
  } > "$ps_dir/bash/bash"
  chmod +x "$ps_dir/bash/bash"
}

perf_split_run() {   # perf_split_run <command...>
  local t0 t1 line TIMEFORMAT='%3U %3S'
  rm -f "$ps_dir/handoff" "$ps_dir"/calls/* 2>/dev/null
  ps_rc=0
  t0=$EPOCHREALTIME
  # the command itself must not be looked up in the new PATH: the caller gives full paths
  { time PATH="$ps_dir/bash:$ps_dir/tools:$PATH" "$@" >/dev/null 2>&1 </dev/null; } 2>"$ps_dir/total" || ps_rc=$?
  t1=$EPOCHREALTIME
  # one line per call: name-free "start end", then the two lines of `times` (the shell, its children)
  local calls=("$ps_dir"/calls/*)
  [ -e "${calls[0]}" ] || calls=()
  line=$( {
      printf 'T %s %s %s\n' "$t0" "$t1" "$(tail -n 1 "$ps_dir/total")"
      if [ -f "$ps_dir/handoff" ]; then printf 'H %s\n' "$(tr '\n' ' ' < "$ps_dir/handoff")"; fi
      if [ ${#calls[@]} -gt 0 ]; then awk 'FNR == 1 { if (l != "") print l; l = "C " $0; next } FNR == 3 { l = l " " $0 } END { if (l != "") print l }' "${calls[@]}" | LC_ALL=C sort -k2,2n; fi
    } | tr ',' '.' | LC_ALL=C awk '
      function secs(v,   p) { split(v, p, /[ms]/); return p[1] * 60 + p[2] }
      $1 == "T" { start = $2; total_wall = $3 - $2; total_cpu = $4 + $5 }
      $1 == "H" { hand = 1; dw = $2 - start; dc = secs($3) + secs($4) + secs($5) + secs($6) }
      $1 == "C" {   # sorted by start: the wall time of the tools is the time at least one of them ran
        n++; tc += secs($4) + secs($5)
        if (n == 1) { from = $2; to = $3 } else if ($2 > to) { tw += to - from; from = $2; to = $3 } else if ($3 > to) to = $3
      }
      function nn(v) { return v > 0 ? v : 0 }
      END {
        if (n) tw += to - from
        d_w = hand ? sprintf("%.3f", nn(dw)) : "-"; d_c = hand ? sprintf("%.3f", nn(dc)) : "-"
        printf "%s %s %.3f %.3f %d %.3f %.3f %.3f\n", d_w, d_c, tw, tc, n, nn(total_wall - (hand ? dw : 0) - tw), nn(total_cpu - (hand ? dc : 0) - tc), total_wall
      }')
  read -r ps_disp_wall ps_disp_cpu ps_tool_wall ps_tool_cpu ps_tool_calls ps_rest_wall ps_rest_cpu ps_total_wall <<<"$line"
}
