# grove

Your own LLM wiki, as a plugin: a skill that teaches a model to **ingest sources, answer with citations and
keep the wiki healthy**, on top of [Leaf](https://github.com/AmozPay/leaf)'s tools, which read a curated Markdown wiki and
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
/plugin marketplace add AmozPay/grove
/plugin install grove@grove
```

The wiki is `LEAF_WIKI` (default `~/wiki`); the cache is `LEAF_DB`. Create a wiki with
`/grove:init`, then `/grove:ingest <file or URL>`, then ask questions with `/grove:query`.

**Write access is explicit.** The plugin starts `leaf-mcp-editor`, the build that has the `editor_*`
tools. For a read-only server, change the `args` in `hosts/claude-code/.claude-plugin/plugin.json` to
`["leaf-mcp"]`. With it, `/grove:ingest` and `/grove:init` cannot change anything.

## Hermes (and other Agent Plugins v1 hosts)

`hosts/agent-plugin/` is an [Agent Plugins v1](https://agent-plugins.org) package: `plugin.json`, `skills/grove/`
and `mcp.json` (the `leaf` server, run by `./bin/run leaf-mcp-editor`). It is generated from the same
`core/plugin.json` as the Claude Code plugin, so both have the same name, version, description and server.

```sh
cp -r hosts/agent-plugin ~/.hermes/plugins/grove    # a package from a Git repository's root installs with `hermes plugins install` instead
hermes plugins enable grove                         # packages install disabled; MCP servers connect next session
```

- Hermes starts Leaf's server with a filtered environment (`LEAF_WIKI` is **not** passed), so the wiki is
  Leaf's default, `~/wiki`. To use another folder, declare your own `leaf` entry under `mcp_servers:` in
  `config.yaml` (a config entry replaces the package's) with `env: {LEAF_WIKI: ...}` and the absolute path of
  `bin/run`. The agent is still never told the folder.
- The downloaded binaries are cached in the plugin's `PLUGIN_DATA` directory.
- Hermes has no slash commands for packages: the workflows are written into the skill. Creating a wiki is a
  command, not a tool, so the init workflow asks the user to run `./bin/run leaf editor init` themselves.
- Hermes's tools are named `mcp__leaf__guide`, `mcp__leaf__search`, ...
- Checked for real with Hermes's own loader and MCP client, in a temporary `HERMES_HOME` and `HOME` (so the
  default wiki was a temporary one): the package loads without diagnostics, the 12 tools register, and
  `guide` answers. No model session was run with it.

## Developing

`core/` is the source of truth (skill, commands, launcher, release pin). `hosts/` and
`.claude-plugin/marketplace.json` are generated and committed:

Enable the pre-commit hook once per clone; it runs the build and stages `hosts/` and the marketplace:

```sh
git config core.hooksPath .githooks
```

```sh
scripts/build.py            # regenerate
tests/run.sh                # launcher, generated files, structure
LEAF_BIN_DIR=/folder/with/the/binaries tests/run.sh   # also checks the skill against the real tools
scripts/pin-release.sh <BASE_URL> <folder with leaf-<version>-<target>.tar.gz>   # pin a release
```

The tests that use the real binaries check that every tool the skill names exists, that the server documents its own use (instructions, descriptions, the batch format), and that the guide works without revealing where the wiki is. The skill itself must not name the wiki's folder (a test checks), and holds the workflow only: Leaf's tools carry their own documentation.

## Status and limits

Checked for real (Claude Code 2.1.300, a temporary wiki, never a real one):

- The plugin loads (`--plugin-dir`), the launcher starts the editor server, and the tools are named
  `mcp__plugin_grove_leaf__*`, as expected.
- `/grove:query` with `Read`, `Grep`, `Glob` and `Bash` all allowed (and the wiki in the working directory)
  used only `guide`, `search` and `cite`.
- The launcher downloads, hash-checks and runs the real packaged archive (a local `file://` release).

Not verified, or known limits:

- Pinned to Leaf v0.1.0 (Linux and macOS, x86_64 and aarch64): the launcher downloads the archive for your
  platform from the GitHub release once and refuses it unless its sha256 matches `core/release.env`. CI checks this
  download on every push. The macOS archives were built by CI but never run by me.
- Linux and macOS only (the launcher is POSIX shell).
- No license is set: that is for the owner to choose.
