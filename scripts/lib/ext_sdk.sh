# shellcheck shell=bash
# shellcheck disable=SC2034  # the EXT_* variables are read by the extension that sources this file
# Shell helper of the extension SDK (hobnix/server#197, docs/extensions-sdk.md). Source it from an extension that speaks the command
# protocol (ADR 0010, docs/api/ext-protocol-v1.schema.json). Needs bash and jq; nothing else.
#
#   . "${HS_SCRIPTS:?}/lib/ext_sdk.sh"
#   ext_init                      # reads the request: EXT_ID EXT_LANG EXT_CALLER EXT_TIMEOUT_MS, arrays EXT_WORDS and EXT_ARGV
#   ext_progress 0.5 "halfway"    # fraction 0..1 or - for none, then a text
#   ext_log info "text"           # debug|info|warn|error
#   ext_event pkg.<name>.<kind> <subject> [text]
#   ext_ok [text] [data-json]     # the result, exits 0
#   ext_fail <code> <message>     # the result, exits 1; code is failed|not_found|bad_request|cancelled
#
# Every line it prints on stdout is one message; print nothing else on stdout (send diagnostics to stderr).

EXT_V=1

ext_init() {
  local line
  IFS= read -r line || line=
  local v
  v=$(jq -r '.v // empty' <<<"$line" 2>/dev/null) || v=
  if [ "$v" != 1 ]; then
    jq -nc '{v:1,type:"result",ok:false,error:{code:"unsupported_version",message:"this extension speaks protocol version 1 only",supported:[1]}}'
    exit 1
  fi
  EXT_ID=$(jq -r '.id' <<<"$line")
  EXT_LANG=$(jq -r '.lang' <<<"$line")
  EXT_CALLER=$(jq -r '.caller' <<<"$line")
  EXT_TIMEOUT_MS=$(jq -r '.timeout_ms' <<<"$line")
  EXT_WORDS=() EXT_ARGV=()
  local x
  while IFS= read -r -d '' x; do EXT_WORDS+=("$x"); done < <(jq -j '.command[] | ., "\u0000"' <<<"$line")
  while IFS= read -r -d '' x; do EXT_ARGV+=("$x"); done < <(jq -j '.argv[] | ., "\u0000"' <<<"$line")
}

ext_progress() {   # [fraction|-] [text]
  jq -nc --arg f "${1:--}" --arg t "${2:-}" \
    '{v:1,type:"progress"} + (if $f == "-" then {} else {fraction:($f|tonumber)} end) + (if $t == "" then {} else {text:$t[0:200]} end)'
}

ext_log() {   # level text
  jq -nc --arg l "${1:?level}" --arg t "${2:-}" '{v:1,type:"log",level:$l,text:$t[0:1000]}'
}

ext_event() {   # kind subject [text]
  jq -nc --arg k "${1:?kind}" --arg s "${2:-}" --arg t "${3:-}" \
    '{v:1,type:"event",kind:$k,subject:$s} + (if $t == "" then {} else {text:$t} end)'
}

ext_ok() {   # [text] [data-json]
  jq -nc --arg t "${1:-}" --argjson d "${2:-null}" \
    '{v:1,type:"result",ok:true} + (if $d == null then {} else {data:$d} end) + (if $t == "" then {} else {text:$t} end)'
  exit 0
}

ext_fail() {   # code message
  jq -nc --arg c "${1:-failed}" --arg m "${2:-failed}" '{v:1,type:"result",ok:false,error:{code:$c,message:($m|gsub("[\n\r]+";" "))}}'
  exit 1
}
