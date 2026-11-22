#!/usr/bin/env bash
# Dev tool (not an `hs` command): the hardware-test trackers of the GitHub project (hobnix/core).
# Development and hardware testing are tracked apart: a dev issue closes when its pull request is merged (milestone progress = built);
# what still has to run on a real server is a line in ONE tracker issue per milestone, "Hardware test: <milestone title>" (label
# hardware-test, no milestone, board column Testing while a box is open). Nothing here blocks a release: a line that is not ticked
# is postponed and moves on with the next release, listed in the release notes as not verified.
#   hwtest.sh add <issue> [step ...]   put the closed/merged issue into its milestone's tracker (created on first use), one box per step
#   hwtest.sh tick <issue> [note]      tick the issue's line and steps; comment what was seen; the tracker closes when no box is left
#   hwtest.sh list [milestone-text]    the open boxes per tracker: the queue for the next session at the server
#   hwtest.sh migrate [--apply]        one-time: issues in the board column Testing become tracker lines and close (dry run by default)
# Needs gh (logged in) and bash with awk. Output is plain text; this is a dev tool, not part of the hs interface.
# Every call goes through the REST API (gh api), never GraphQL: GraphQL has one hourly budget shared with every tool and agent, and it ran
# dry in the middle of the first migration (2026-11-20). The board is written by board.sh (REST as well).
REPO=hobnix/core
LABEL=hardware-test
here=$(cd "$(dirname "$0")" && pwd)

die() { echo "hwtest.sh: $*" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || die "gh is missing"

issue_field() { gh api "repos/$REPO/issues/$1" --jq "$2" 2>/dev/null | tr -d '\r'; }                  # issue number, jq expression
issue_set_body() { gh api -X PATCH "repos/$REPO/issues/$1" -f body="$(cat "$2")" --silent; }          # issue number, body file
issue_comment() { gh api -X POST "repos/$REPO/issues/$1/comments" -f body="$2" --silent; }
issue_close() { gh api -X PATCH "repos/$REPO/issues/$1" -f state=closed -f state_reason=completed --silent; }

ensure_label() {
  gh api "repos/$REPO/labels/$LABEL" --silent 2>/dev/null ||
    gh api -X POST "repos/$REPO/labels" -f name="$LABEL" -f color=0E8A16 -f description="Tracker of the steps to run on a real server" --silent ||
    die "cannot create the label $LABEL"
}

# milestone title of an issue (empty when none)
milestone_of() { issue_field "$1" '.milestone.title // empty'; }

# open trackers as "number<TAB>title"
trackers() { gh api "repos/$REPO/issues?labels=$LABEL&state=open&per_page=100" --jq '.[] | "\(.number)\t\(.title)"' | tr -d '\r'; }

# number of the open tracker for a milestone title (empty when none)
tracker_of() { trackers | awk -F'\t' -v t="Hardware test: $1" '$2 == t { print $1; exit }'; }

intro() {
  printf '%s\n' "One box per merged change that still has to run on a real server, grouped by issue. Tick a box only for a run somebody saw, and say"
  printf '%s\n' "what was seen in a comment. A box that is not ticked is postponed: it carries over, it never blocks a release. Maintained with"
  printf '%s\n' "\`bash scripts/dev/hwtest.sh\` (add, tick, list); see docs/dev-environment.md, Branches and releases, item 7."
  printf '\n'
}

# Create a tracker for a milestone title; prints its number and puts it on the board in Testing (board.sh adds an issue that is not there).
make_tracker() {
  local ms="$1" n
  ensure_label
  n=$(gh api -X POST "repos/$REPO/issues" -f title="Hardware test: $ms" -f "labels[]=$LABEL" -f body="$(intro)" --jq .number | tr -d '\r') ||
    die "cannot create the tracker"
  bash "$here/board.sh" move "$n" testing >/dev/null 2>&1 || echo "hwtest.sh: could not set #$n to Testing on the board" >&2
  echo "$n"
}

# Add "- [ ] #N title" with sub-boxes to a body held in $1 (a file); idempotent per issue.
add_to_body() {
  local file="$1" n="$2" title="$3"; shift 3
  if grep -q "^- \[[ xX]\] #$n " "$file"; then
    echo "hwtest.sh: #$n is in the tracker already" >&2
    return 0
  fi
  { printf -- '- [ ] #%s %s\n' "$n" "$title"
    for s in "$@"; do printf -- '  - [ ] %s\n' "$s"; done; } >> "$file"
}

cmd_add() {
  local n="${1:-}" title ms t tmp
  [ -n "$n" ] || die "usage: hwtest.sh add <issue> [step ...]"
  shift
  title=$(issue_field "$n" .title); [ -n "$title" ] || die "cannot read issue #$n"
  ms=$(milestone_of "$n"); [ -n "$ms" ] || die "issue #$n has no milestone: set one first"
  t=$(tracker_of "$ms"); [ -n "$t" ] || t=$(make_tracker "$ms")
  tmp=$(mktemp); issue_field "$t" .body > "$tmp" || die "cannot read tracker #$t"
  add_to_body "$tmp" "$n" "$title" "$@"
  issue_set_body "$t" "$tmp" || die "cannot update tracker #$t"
  rm -f "$tmp"
  bash "$here/board.sh" move "$t" testing >/dev/null 2>&1 || true
  echo "#$n -> tracker #$t ($ms)"
}

cmd_tick() {
  local n="${1:-}" note="${2:-}" ms t tmp left
  [ -n "$n" ] || die "usage: hwtest.sh tick <issue> [note]"
  ms=$(milestone_of "$n"); [ -n "$ms" ] || die "issue #$n has no milestone"
  t=$(tracker_of "$ms"); [ -n "$t" ] || die "no open tracker for \"$ms\""
  tmp=$(mktemp); issue_field "$t" .body > "$tmp"
  awk -v n="$n" '
    $0 ~ "^- \\[[ xX]\\] #" n " " { sub(/\[ \]/, "[x]"); on = 1; print; next }
    on && /^  - \[[ xX]\]/ { sub(/\[ \]/, "[x]"); print; next }
    { on = 0; print }' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"
  issue_set_body "$t" "$tmp" || die "cannot update tracker #$t"
  [ -z "$note" ] || issue_comment "$t" "#$n ran on a real server: $note"
  left=$(grep -c '\[ \]' "$tmp" || true)
  rm -f "$tmp"
  if [ "$left" = 0 ]; then
    issue_comment "$t" "Every box is ticked."
    issue_close "$t" && bash "$here/board.sh" move "$t" done >/dev/null 2>&1
    echo "#$n ticked; tracker #$t closed (nothing left)"
  else
    echo "#$n ticked; tracker #$t has $left open box(es)"
  fi
}

cmd_list() {
  local want="${1:-}" t title body
  trackers | while IFS=$'\t' read -r t title; do
    case "$title" in *"$want"*) ;; *) continue ;; esac
    body=$(issue_field "$t" .body)
    printf '#%s %s: %s open, %s ticked\n' "$t" "$title" "$(printf '%s\n' "$body" | grep -c '\[ \]')" "$(printf '%s\n' "$body" | grep -ci '\[x\]')"
    printf '%s\n' "$body" | grep '\[ \]' | sed 's/^/  /'
  done
}

# Issues of the board column Testing that are not trackers, as "number<TAB>milestone<TAB>title" (REST: the Status field is id 437753319).
testing_items() {
  gh api --paginate "orgs/hobnix/projectsV2/1/items?per_page=100&fields=437753319" \
    --jq '.[] | select(.content_type == "Issue") | select(.fields[0].value.name.raw == "Testing") | "\(.content.number)\t\(.content.milestone.title // "-")\t\(.content.title)"' |
    tr -d '\r' | grep -v "Hardware test: " || true
}

cmd_migrate() {
  local apply=false n ms title t state
  export BOARD_CACHE; BOARD_CACHE=$(mktemp)   # the board is listed once, not once per move
  [ "${1:-}" = "--apply" ] && apply=true
  testing_items | sort -t$'\t' -k2,2 -k1,1n | while IFS=$'\t' read -r n ms title; do
    [ "$ms" != "-" ] || { echo "skip  #$n (no milestone): $title"; continue; }
    state=$(issue_field "$n" .state)
    if $apply; then
      if [ "$state" = open ]; then
        cmd_add "$n" >/dev/null || { echo "FAILED #$n"; continue; }
        t=$(tracker_of "$ms")
        issue_comment "$n" "Development is merged. The run on a real server is tracked in #$t (Hardware test: $ms); this issue closes so the milestone shows what is built." &&
          issue_close "$n"
      fi
      bash "$here/board.sh" move "$n" done >/dev/null 2>&1
      echo "moved #$n [$ms]"
    else
      echo "would move #$n [$ms] ($state) $title"
    fi
  done
  $apply || echo "(dry run: nothing changed; run with --apply)"
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  tick) shift; cmd_tick "$@" ;;
  list) shift; cmd_list "$@" ;;
  migrate) shift; cmd_migrate "$@" ;;
  *) echo "usage: hwtest.sh add <issue> [step ...] | tick <issue> [note] | list [milestone] | migrate [--apply]" >&2; exit 2 ;;
esac
