# shellcheck shell=bash
# shellcheck disable=SC2034  # adopt_why is read by the caller when adopt_claim refuses
# The names of the shares that adopting a disk makes (hs pool <pool> add --role adopt, scripts/manage-pool.sh). Sourced, not run; needs
# lib/bulkpath.sh and lib/sharepath.sh, and merge_folders=true|false (--merge).
#
#   adopt_reserved <folder>              the share code keeps this name for itself
#   adopt_reset <merged pool folder>     call once before the plan, before anything moves: it notes the long shares that exist
#   adopt_target <label> <folder>        the folder it becomes inside shares/: per disk <disk>-<folder> ("Media" on data-02 ->
#                                        data-02-media), with --merge the same name (a reserved one gets -adopted, docs/PLAN-storage-nas.md D10)
#   adopt_name_note <label> <folder>     the plan line about the length, nothing for a name that fits
#   adopt_claim <label> <folder> <target>   exit 1 (reason in adopt_why) when another folder or an existing share has that name
#
# A name is never longer than a new share may be (41 characters, scripts/web-serve.py SHARE; issue 1245): a longer one is cut and ends in
# 6 hex digits of the sha256 of the whole name, so the same folder always gets the same name (with --merge on every disk) and two long
# folders stay apart. adopt_own: the folders the disk being looked at has in its shares/ and sensitive/ already.
ADOPT_NAME_MAX=41
declare -gA adopt_long=() adopt_by=() adopt_by_text=() adopt_by_renamed=()
adopt_own=()
adopt_why=""
: "${merge_folders:=false}"   # the caller's --merge

adopt_reserved() { case "$(tr 'A-Z' 'a-z' <<<"$1")" in shares|sensitive|global|homes|printers) return 0 ;; esac; return 1; }

adopt_reset() {   # adopt_reset <merged pool folder>
  local d n
  adopt_long=() adopt_by=() adopt_by_text=() adopt_by_renamed=()
  adopt_own=()
  for d in "$(disks_root)"/data-*/shares/*/ "$1"/shares/*/; do
    [ -d "$d" ] || continue
    d=${d%/}; n=${d##*/}
    [ ${#n} -le $ADOPT_NAME_MAX ] || adopt_long[$n]=1
  done
}

_adopt_full_name() {   # the name before the length limit
  if $merge_folders; then
    if adopt_reserved "$2"; then printf '%s-adopted\n' "$2"; else printf '%s\n' "$2"; fi
  else printf '%s-%s\n' "${1#bulk-}" "$(tr 'A-Z ' 'a-z-' <<<"$2")"; fi
}

_adopt_short() {   # _adopt_short <name>
  local LC_ALL=C.UTF-8 head hash   # count and cut characters, not bytes
  if [ ${#1} -le $ADOPT_NAME_MAX ]; then printf '%s\n' "$1"; return; fi
  hash=$(printf '%s' "$1" | sha256sum)
  head=${1:0:ADOPT_NAME_MAX-7}
  while [[ $head == *[-._\ ] ]]; do head=${head%?}; done
  printf '%s-%s\n' "$head" "${hash:0:6}"
}

adopt_target() {   # adopt_target <label> <folder>
  local full
  full=$(_adopt_full_name "$1" "$2")
  # --merge into a long share that exists (made before the limit): the same name, never a second, shortened share beside it
  if $merge_folders && [ -n "${adopt_long[$full]:-}" ]; then printf '%s\n' "$full"; else _adopt_short "$full"; fi
}

adopt_name_note() {   # adopt_name_note <label> <folder>
  local full t
  full=$(_adopt_full_name "$1" "$2"); t=$(adopt_target "$1" "$2")
  if [ "$t" != "$full" ]; then
    printf "      shortened: '%s' is too long for a share name (at most %s characters), it becomes '%s'\n" "$2" "$ADOPT_NAME_MAX" "$t"
  elif [ "$(LC_ALL=C.UTF-8; printf '%s' "${#t}")" -gt $ADOPT_NAME_MAX ]; then
    printf "      note: '%s' is longer than %s characters and a share of that name exists already: it is merged into that share\n" "$2" "$ADOPT_NAME_MAX"
  fi
}

_adopt_exists() {   # a share (or a folder that would be one) of that name is there already
  local f
  for f in ${adopt_own[@]+"${adopt_own[@]}"}; do [ "${f,,}" != "${1,,}" ] || return 0; done
  for f in "$(disks_root)"/data-*/shares/* "$(disks_root)"/data-*/sensitive/*; do
    [ -e "$f" ] || continue
    f=${f##*/}
    [ "${f,,}" != "${1,,}" ] || return 0
  done
  share_name_taken "$1"
}

adopt_claim() {   # adopt_claim <label> <folder> <target>: not in $(...), it keeps what it saw
  local disk=${1#bulk-} folder=$2 t=$3 key=${3,,} src renamed=false
  adopt_why=""
  # with --merge the same folder name on several disks is one source: that is what gets merged
  if $merge_folders; then src=$folder; else src="$disk/$folder"; fi
  [ "$t" = "$folder" ] || renamed=true
  if [ -n "${adopt_by[$key]:-}" ] && [ "${adopt_by[$key]}" != "$src" ]; then
    # with --merge, two folders that keep their own names (they differ in case) stay as they always did
    if ! $merge_folders || $renamed || ${adopt_by_renamed[$key]}; then
      adopt_why="the folder '$folder' on $disk would become the share '$t', which ${adopt_by_text[$key]} becomes already"
      return 1
    fi
  fi
  if ! $merge_folders && _adopt_exists "$t"; then
    adopt_why="the folder '$folder' on $disk would become the share '$t', which exists already"
    return 1
  fi
  adopt_by[$key]=$src; adopt_by_text[$key]="'$folder' on $disk"; adopt_by_renamed[$key]=$renamed
}
