#!/bin/sh
# The session-end hook: off by default, opt-in modes, once per session, never
# recursive. A stub `claude` records how it was called; nothing real runs.
. "$(dirname "$0")/lib.sh"
HOOK="$ROOT/core/hooks/session-end.sh"

mkdir -p "$TMP/bin" "$TMP/data" "$TMP/projects"
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/sh
{ echo "ARGS: $*"; echo "CHILD: ${LLM_WIKI_SYNC_CHILD:-}"; } >> "$STUB_LOG"
STUB
chmod +x "$TMP/bin/claude"
export STUB_LOG="$TMP/calls.log"
export LLM_WIKI_DATA="$TMP/data"
export PATH="$TMP/bin:$PATH"
unset WIKILEAF_SESSION_SYNC LLM_WIKI_SYNC_CHILD

big() { # big <file> [marker]: a transcript above the default size threshold
  { i=0; while [ $i -lt 200 ]; do echo "line $i of a long working session about gardening"; i=$((i + 1)); done; [ -z "${2:-}" ] || echo "$2"; } > "$1"
}
input() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"other"}' "$1" "$2"; }
calls() { [ -f "$STUB_LOG" ] && grep -c '^ARGS' "$STUB_LOG" || echo 0; }
wait_calls() { # the child is detached: wait briefly for its call
  i=0; while [ "$(calls)" -lt "$1" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; calls
}
run() { input "$1" "$2" | "$HOOK"; }

big "$TMP/projects/a.jsonl"
big "$TMP/projects/wiki.jsonl" 'tool_use mcp__plugin_llm-wiki_wikileaf__search'
printf 'tiny' > "$TMP/projects/tiny.jsonl"

run s1 "$TMP/projects/a.jsonl"; sleep 0.3
[ "$(calls)" = 0 ] && ok "does nothing unless enabled" || fail "ran while off"

export WIKILEAF_SESSION_SYNC=bogus
run s1 "$TMP/projects/a.jsonl"; sleep 0.3
[ "$(calls)" = 0 ] && ok "an unknown mode is off" || fail "ran on an unknown mode"

export WIKILEAF_SESSION_SYNC=all
run s1 "$TMP/projects/a.jsonl"
[ "$(wait_calls 1)" = 1 ] && ok "mode all starts one run" || fail "mode all did not start a run"
args="$(grep '^ARGS' "$STUB_LOG" | head -1)"
case "$args" in *"-p /llm-wiki:sync-session $TMP/projects/a.jsonl"*) ok "asks for the sync-session command on the transcript" ;; *) fail "prompt: $args" ;; esac
case "$args" in *"--allowedTools Read mcp__plugin_llm-wiki_wikileaf__guide mcp__plugin_llm-wiki_wikileaf__search "*"mcp__plugin_llm-wiki_wikileaf__editor_apply"*) ok "allows exactly the wiki tools" ;; *) fail "tools: $args" ;; esac
case "$args" in *"--max-budget-usd 0.50"*) ok "caps the spend" ;; *) fail "budget: $args" ;; esac
case "$args" in *"--add-dir $TMP/projects"*) ok "lets the run read the transcript's folder" ;; *) fail "add-dir: $args" ;; esac
grep -q '^CHILD: 1' "$STUB_LOG" && ok "marks the run as a child" || fail "child marker"

run s1 "$TMP/projects/a.jsonl"; sleep 0.3
[ "$(calls)" = 1 ] && ok "a session is synced once" || fail "synced twice"
[ -f "$TMP/data/session-sync/done/s1" ] && ok "records the session in the plugin's own folder" || fail "state file"

LLM_WIKI_SYNC_CHILD=1 run s2 "$TMP/projects/a.jsonl"; sleep 0.3
[ "$(calls)" = 1 ] && ok "a child run never starts another" || fail "recursion"

run s3 "$TMP/projects/tiny.jsonl"; sleep 0.3
[ "$(calls)" = 1 ] && ok "skips a tiny transcript" || fail "tiny transcript"
WIKILEAF_SESSION_SYNC_MIN_BYTES=1 run s3 "$TMP/projects/tiny.jsonl"
[ "$(wait_calls 2)" = 2 ] && ok "the size threshold is configurable" || fail "min bytes"

export WIKILEAF_SESSION_SYNC=wiki
run s4 "$TMP/projects/a.jsonl"; sleep 0.3
[ "$(calls)" = 2 ] && ok "mode wiki skips a session that used no wiki tool" || fail "mode wiki ran without a wiki tool"
run s5 "$TMP/projects/wiki.jsonl"
[ "$(wait_calls 3)" = 3 ] && ok "mode wiki syncs a session that used one" || fail "mode wiki did not run"

run '../evil' "$TMP/projects/a.jsonl"; sleep 0.3
[ "$(calls)" = 3 ] && [ ! -e "$TMP/evil" ] && ok "an unsafe session id is ignored" || fail "unsafe session id"
printf 'not json' | "$HOOK"; echo "{}" | "$HOOK"
ok "bad input exits quietly"

mkdir "$TMP/empty"
PATH="$TMP/empty:/usr/bin:/bin" WIKILEAF_SESSION_SYNC=all sh -c "printf '{}' | '$HOOK'" && ok "no claude on PATH is fine" || fail "no claude"
finish
