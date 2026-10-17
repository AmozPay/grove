# llm-wiki

Your own LLM wiki, as a plugin: a skill that teaches a model to **ingest sources, answer with citations and
keep the wiki healthy**, on top of [Wikileaf](../wikileaf)'s tools, which read a curated Markdown wiki and
change it only through validated, all-or-nothing batches. A change that breaks the wiki's conventions is
rejected with a message that says what to fix, so even a small model cannot erode the wiki.

It follows Karpathy's LLM-wiki pattern (raw sources never change; the model compiles them into linked, cited
pages; `index.md` and `log.md` are kept for you) but replaces the "edit the files yourself" workflow of the
upstream skill with Wikileaf's editor.

## What is in it

| | |
|---|---|
| **MCP server** (`wikileaf`) | Wikileaf's tools, which document themselves (server instructions, tool descriptions, the batch format): read and search, and the editor |
| **Skill** `llm-wiki` | the workflow (resume, answer, ingest, lint) and the rule that the wiki is only ever touched through the tools |
| **Commands** | `/llm-wiki:init`, `/llm-wiki:ingest`, `/llm-wiki:query`, `/llm-wiki:lint` (and `/llm-wiki:sync-session`, used by the hook) |
| **Session-end hook** | optional, **off by default**: records what a finished session taught |

The plugin runs Wikileaf's prebuilt binaries: a launcher (`bin/run`) downloads the release pinned in
`release.env` once, checks its sha256 against the pinned value, caches it, and runs it.

## Install (Claude Code)

```
/plugin marketplace add /path/to/llm-wiki
/plugin install llm-wiki@llm-wiki
```

The wiki is `WIKILEAF_WIKI` (default `~/wiki`); the cache is `WIKILEAF_DB`. Create a wiki with
`/llm-wiki:init`, then `/llm-wiki:ingest <file or URL>`, then ask questions with `/llm-wiki:query`.

**Write access is explicit.** The plugin starts `wikileaf-mcp-editor`, the build that has the `editor_*`
tools. For a read-only server, change the `args` in `hosts/claude-code/.claude-plugin/plugin.json` to
`["wikileaf-mcp"]`. With it, `/llm-wiki:ingest` and `/llm-wiki:init` cannot change anything.

## The session-end hook

When enabled, a session that ends starts a background `claude -p` run that reads the transcript and, through
the editor, records the durable facts in the wiki (as an immutable `raw/transcripts/` note, cited by the pages
it updates). It **costs tokens and writes files**, so nothing happens unless you set:

```sh
export WIKILEAF_SESSION_SYNC=wiki   # only sessions that used a wiki tool
export WIKILEAF_SESSION_SYNC=all    # every session, in every project
```

Safeguards: a session is synced once; transcripts under 4,000 bytes are skipped
(`WIKILEAF_SESSION_SYNC_MIN_BYTES`); one run is capped at $0.50 (`LLM_WIKI_SYNC_BUDGET_USD`); the run may only use
`Read` and the wiki's tools; the run's own end does not trigger the hook again (`LLM_WIKI_SYNC_CHILD`); its
state and logs are in the plugin's data folder (`LLM_WIKI_DATA`), never in the wiki, so another sync tool can
share the wiki. The run is told to leave out anything that looks like a secret, but a transcript is sent to the
model like any other conversation: do not enable this for sessions you would not put in the wiki.

## Hermes

`hosts/hermes/` has the skill (with the workflows written out, as Hermes has no slash commands) and a
`mcp_servers` snippet. **Not tested against a running Hermes**; see its README.

## Developing

`core/` is the source of truth (skill, commands, launcher, hook, release pin). `hosts/` and
`.claude-plugin/marketplace.json` are generated and committed:

```sh
scripts/build.py            # regenerate
tests/run.sh                # launcher, hook, generated files, structure
WIKILEAF_BIN_DIR=/folder/with/the/binaries tests/run.sh   # also checks the skill against the real tools
scripts/pin-release.sh <BASE_URL> <folder with wikileaf-<version>-<target>.tar.gz>   # pin a release
```

The tests that use the real binaries check that every tool the skill names exists, that the server documents its own use (instructions, descriptions, the batch format), and that the guide works without revealing where the wiki is. The skill itself must not name the wiki's folder (a test checks), and holds the workflow only: Wikileaf's tools carry their own documentation.

## Status and limits

Checked for real (Claude Code 2.1.300, a temporary wiki, never `~/wiki`):

- The plugin loads (`--plugin-dir`), the launcher starts the editor server, and the tools are named
  `mcp__plugin_llm-wiki_wikileaf__*`, as the hook's allow-list expects.
- `/llm-wiki:sync-session` on a synthetic transcript created three interlinked pages and a cited raw note in one
  batch, left out a password, and the wiki stayed conformant.
- `/llm-wiki:query` with `Read`, `Grep`, `Glob` and `Bash` all allowed (and the wiki in the working directory)
  used only `guide`, `search` and `cite`.
- The SessionEnd hook fires, receives the session id and transcript, and finds the plugin's data folder.
- The launcher downloads, hash-checks and runs the real packaged archive (a local `file://` release).

Not verified, or known limits:

- **No release is published.** `core/release.env` has no `BASE_URL` and no hashes, so the launcher stops with a
  message. Until one exists, point `WIKILEAF_BIN_DIR` at a folder with `wikileaf`, `wikileaf-mcp` and
  `wikileaf-mcp-editor` (`scripts/package-release.sh` in Wikileaf builds them).
- Wikileaf's release workflow has not been run (there is no remote); only the host target was packaged.
- The hook's background run finds `/llm-wiki:sync-session` only when the plugin is **installed**; under
  `--plugin-dir` it does not (seen in the run's log), so it records nothing.
- The hook was not run to completion through a real session end followed by a full sync (its two halves were
  checked separately).
- Hermes: not tested. Linux and macOS only (the launcher is POSIX shell).
- No license is set: that is for the owner to choose.
