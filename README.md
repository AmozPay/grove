# grove

Your own LLM wiki, as a plugin: a skill that teaches a model to **ingest sources, answer with citations and
keep the wiki healthy**, on top of [Leaf](../wikileaf)'s tools, which read a curated Markdown wiki and
change it only through validated, all-or-nothing batches. A change that breaks the wiki's conventions is
rejected with a message that says what to fix, so even a small model cannot erode the wiki.

It follows Karpathy's LLM-wiki pattern (raw sources never change; the model compiles them into linked, cited
pages; `index.md` and `log.md` are kept for you) but replaces the "edit the files yourself" workflow of the
upstream skill with Leaf's editor.

## What is in it

| | |
|---|---|
| **MCP server** (`leaf`) | Leaf's tools, which document themselves (server instructions, tool descriptions, the batch format): read and search, and the editor |
| **Skill** `grove` | the workflow (resume, answer, ingest, lint) and the rule that the wiki is only ever touched through the tools |
| **Commands** | `/grove:init`, `/grove:ingest`, `/grove:query`, `/grove:lint` |

The plugin runs Leaf's prebuilt binaries: a launcher (`bin/run`) downloads the release pinned in
`release.env` once, checks its sha256 against the pinned value, caches it, and runs it.

## Install (Claude Code)

```
/plugin marketplace add /path/to/grove
/plugin install grove@grove
```

The wiki is `LEAF_WIKI` (default `~/wiki`); the cache is `LEAF_DB`. Create a wiki with
`/grove:init`, then `/grove:ingest <file or URL>`, then ask questions with `/grove:query`.

**Write access is explicit.** The plugin starts `leaf-mcp-editor`, the build that has the `editor_*`
tools. For a read-only server, change the `args` in `hosts/claude-code/.claude-plugin/plugin.json` to
`["leaf-mcp"]`. With it, `/grove:ingest` and `/grove:init` cannot change anything.

## Hermes

`hosts/hermes/` has the skill (with the workflows written out, as Hermes has no slash commands) and a
`mcp_servers` snippet. **Not tested against a running Hermes**; see its README.

## Developing

`core/` is the source of truth (skill, commands, launcher, release pin). `hosts/` and
`.claude-plugin/marketplace.json` are generated and committed:

```sh
scripts/build.py            # regenerate
tests/run.sh                # launcher, generated files, structure
LEAF_BIN_DIR=/folder/with/the/binaries tests/run.sh   # also checks the skill against the real tools
scripts/pin-release.sh <BASE_URL> <folder with leaf-<version>-<target>.tar.gz>   # pin a release
```

The tests that use the real binaries check that every tool the skill names exists, that the server documents its own use (instructions, descriptions, the batch format), and that the guide works without revealing where the wiki is. The skill itself must not name the wiki's folder (a test checks), and holds the workflow only: Leaf's tools carry their own documentation.

## Status and limits

Checked for real (Claude Code 2.1.300, a temporary wiki, never `~/wiki`):

- The plugin loads (`--plugin-dir`), the launcher starts the editor server, and the tools are named
  `mcp__plugin_grove_leaf__*`, as expected.
- `/grove:query` with `Read`, `Grep`, `Glob` and `Bash` all allowed (and the wiki in the working directory)
  used only `guide`, `search` and `cite`.
- The launcher downloads, hash-checks and runs the real packaged archive (a local `file://` release).

Not verified, or known limits:

- **No release is published.** `core/release.env` has no `BASE_URL` and no hashes, so the launcher stops with a
  message. Until one exists, point `LEAF_BIN_DIR` at a folder with `leaf`, `leaf-mcp` and
  `leaf-mcp-editor` (`scripts/package-release.sh` in Leaf builds them).
- Leaf's release workflow has not been run (there is no remote); only the host target was packaged.
- Hermes: not tested. Linux and macOS only (the launcher is POSIX shell).
- No license is set: that is for the owner to choose.
