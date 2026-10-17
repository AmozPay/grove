#!/bin/sh
# SessionEnd hook: record what a finished session taught, in the wiki.
#
# OFF BY DEFAULT. It starts a background `claude -p` run that reads the
# session's transcript and edits the wiki through Wikileaf's editor, which
# costs tokens and writes files, so it only runs when asked for:
#
#   WIKILEAF_SESSION_SYNC=wiki   sessions that used a wiki tool
#   WIKILEAF_SESSION_SYNC=all    every session (of every project)
#
# Other settings (all optional):
#   WIKILEAF_SESSION_SYNC_MIN_BYTES  skip transcripts smaller than this (default 4000)
#   LLM_WIKI_SYNC_BUDGET_USD         spending cap of one run (default 0.50)
#   LLM_WIKI_TOOL_PREFIX             prefix of the wiki tools' names
#                                    (default mcp__plugin_llm-wiki_wikileaf__)
#   LLM_WIKI_DATA                    state and logs (default $CLAUDE_PLUGIN_DATA,
#                                    else ~/.local/share/llm-wiki)
#   WIKILEAF_WIKI                    the wiki (default ~/wiki), as for the server
#
# State lives in the plugin's own folder, never in the wiki (a wiki may be
# synced by another tool too). The child run sets LLM_WIKI_SYNC_CHILD, which
# makes this hook a no-op: otherwise the run's own end would trigger it again.
set -u

case "${WIKILEAF_SESSION_SYNC:-off}" in
  wiki | all) ;;
  *) exit 0 ;;
esac
[ -z "${LLM_WIKI_SYNC_CHILD:-}" ] || exit 0
command -v claude >/dev/null 2>&1 || exit 0

input="$(cat)"
field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$input" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
}
session="$(field session_id)"
transcript="$(field transcript_path)"
[ -n "$session" ] && [ -f "$transcript" ] || exit 0
# A session id is a file name below: keep it to safe characters.
case "$session" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

min="${WIKILEAF_SESSION_SYNC_MIN_BYTES:-4000}"
size="$(wc -c < "$transcript" | tr -d ' ')"
[ "$size" -ge "$min" ] || exit 0

prefix="${LLM_WIKI_TOOL_PREFIX:-mcp__plugin_llm-wiki_wikileaf__}"
if [ "${WIKILEAF_SESSION_SYNC}" = "wiki" ]; then
  grep -q "wikileaf__" "$transcript" || exit 0
fi

data="${LLM_WIKI_DATA:-${CLAUDE_PLUGIN_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/llm-wiki}}/session-sync"
mkdir -p "$data/done" || exit 0
# Once per session.
[ ! -e "$data/done/$session" ] || exit 0
: > "$data/done/$session"

tools="Read"
for tool in guide search cite metadata people stats editor_page editor_metadata editor_suggest editor_check editor_apply editor_conformance; do
  tools="$tools $prefix$tool"
done
prompt="/llm-wiki:sync-session $transcript"

# Detached, so the end of this session is not held up (or killed) by it.
(
  export LLM_WIKI_SYNC_CHILD=1
  # shellcheck disable=SC2086
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup claude -p "$prompt" --allowedTools $tools \
      --add-dir "$(dirname "$transcript")" \
      --max-budget-usd "${LLM_WIKI_SYNC_BUDGET_USD:-0.50}" \
      > "$data/$session.log" 2>&1 < /dev/null &
  else
    nohup claude -p "$prompt" --allowedTools $tools \
      --add-dir "$(dirname "$transcript")" \
      --max-budget-usd "${LLM_WIKI_SYNC_BUDGET_USD:-0.50}" \
      > "$data/$session.log" 2>&1 < /dev/null &
  fi
)
exit 0
