#!/usr/bin/env python3
"""Structure of the generated plugins: manifests parse, files are where the
hosts look for them, and the core's text has no leftovers."""
import json
import re
import stat
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CC = ROOT / "hosts" / "claude-code"
AP = ROOT  # the Agent Plugins v1 package is the repository root (Hermes installs a repo root)


def frontmatter(path: Path) -> dict:
    match = re.match(r"---\n(.*?)\n---\n", path.read_text(), re.S)
    assert match, f"{path} has no frontmatter"
    return dict(re.findall(r"^([\w-]+): (.*)$", match.group(1), re.M))


class ClaudeCode(unittest.TestCase):
    def test_manifest(self):
        manifest = json.loads((CC / ".claude-plugin" / "plugin.json").read_text())
        self.assertEqual(manifest["name"], "grove")
        self.assertEqual(manifest["version"], (ROOT / "VERSION").read_text().strip())
        server = manifest["mcpServers"]["leaf"]
        self.assertEqual(server["type"], "stdio")
        self.assertEqual(server["command"], "${CLAUDE_PLUGIN_ROOT}/bin/run")
        # The editor build is named on purpose: write access is never implicit.
        self.assertEqual(server["args"], ["leaf-mcp-editor"])

    def test_marketplace_points_at_the_plugin(self):
        market = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text())
        source = market["plugins"][0]["source"]
        self.assertTrue((ROOT / source / ".claude-plugin" / "plugin.json").is_file())

    def test_skill_and_commands_have_frontmatter(self):
        self.assertEqual(frontmatter(CC / "skills" / "grove" / "SKILL.md")["name"], "grove")
        for name in ["init", "ingest", "query", "lint"]:
            fm = frontmatter(CC / "commands" / f"{name}.md")
            self.assertTrue(fm["description"], name)

    def test_no_placeholder_is_left(self):
        for path in list((CC / "commands").glob("*.md")) + list((ROOT / "skills").rglob("*.md")):
            self.assertNotIn("{{", path.read_text(), str(path))

    def test_commands_use_the_plugin_launcher(self):
        text = (CC / "commands" / "init.md").read_text()
        self.assertIn("${CLAUDE_PLUGIN_ROOT}/bin/run leaf editor init", text)
        self.assertIn("$ARGUMENTS", text)

    def test_scripts_are_executable(self):
        for rel in ["bin/run"]:
            self.assertTrue((CC / rel).stat().st_mode & stat.S_IXUSR, rel)
        self.assertTrue((AP / "bin" / "run").stat().st_mode & stat.S_IXUSR)


class AgentPlugin(unittest.TestCase):
    """Agent Plugins v1 (Hermes): plugin.json, skills/ and mcp.json, from the same core/plugin.json as Claude Code."""

    def test_manifest_and_server(self):
        manifest = json.loads((AP / "plugin.json").read_text())
        self.assertEqual(manifest["$schema"], "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json")
        mcp = json.loads((AP / "mcp.json").read_text())
        server = mcp["mcpServers"]["leaf"]
        # A v1 command is a bare executable or ./path inside the plugin; the editor build is named on purpose.
        self.assertEqual((server["command"], server["args"]), ("./bin/run", ["leaf-mcp-editor"]))
        self.assertTrue((AP / server["command"]).is_file())

    def test_same_identity_as_claude_code(self):
        cc = json.loads((CC / ".claude-plugin" / "plugin.json").read_text())
        ap = json.loads((AP / "plugin.json").read_text())
        for key in ["name", "version", "description", "author", "keywords"]:
            self.assertEqual(cc[key], ap[key], key)
        cc_server = cc["mcpServers"]["leaf"]
        self.assertEqual(cc_server["args"], json.loads((AP / "mcp.json").read_text())["mcpServers"]["leaf"]["args"])

    def test_skill_is_valid_and_carries_the_workflows(self):
        skill = AP / "skills" / "grove" / "SKILL.md"
        self.assertEqual(frontmatter(skill)["name"], "grove")  # Agent Skills: the name is the directory's
        # Plain YAML scalars cannot contain ': ' (Hermes rejects the skill at startup).
        for path in [ROOT / "core" / "skill" / "SKILL.md", skill, CC / "skills" / "grove" / "SKILL.md"]:
            description = frontmatter(path)["description"]
            self.assertFalse(": " in description and not description.startswith(('"', "'", "|", ">")), path)
            self.assertLessEqual(len(description.strip('"')), 60, path)
            self.assertIn("wiki first", description, path)
        self.assertIn("## Workflows", skill.read_text())
        self.assertNotIn("LEAF_WIKI", skill.read_text())
        self.assertIn("./bin/run leaf editor init", skill.read_text())

    def test_skill_routes_ambiguous_questions_to_real_leaf_calls(self):
        for path in [ROOT / "core" / "skill" / "SKILL.md", AP / "skills" / "grove" / "SKILL.md",
                     CC / "skills" / "grove" / "SKILL.md"]:
            text = path.read_text()
            for phrase in ["Who is Coco?", "mcp__leaf__guide", "mcp__leaf__search", "mcp__leaf__cite",
                           "Do not substitute `web_search`", "not** JSON or prose", "cannot force a model"]:
                self.assertIn(phrase, text, f"{path}: {phrase}")


    def test_simple_answers_do_not_require_citations(self):
        for path in [ROOT / "core" / "skill" / "SKILL.md", AP / "skills" / "grove" / "SKILL.md",
                     CC / "skills" / "grove" / "SKILL.md", ROOT / "core" / "commands" / "query.md",
                     CC / "commands" / "query.md"]:
            text = path.read_text()
            self.assertIn("no displayed citation", text, path)
            self.assertIn("consequential or uncertain", text, path)


class Hook(unittest.TestCase):
    def test_pre_commit_hook_builds_and_stages(self):
        hook = ROOT / ".githooks" / "pre-commit"
        self.assertTrue(hook.stat().st_mode & stat.S_IXUSR)
        text = hook.read_text()
        self.assertIn("scripts/build.py", text)
        self.assertIn("git add hosts plugin.json mcp.json skills bin release.env .claude-plugin", text)


class Core(unittest.TestCase):
    def texts(self):
        paths = [ROOT / "core" / "skill" / "SKILL.md"] + sorted((ROOT / "core" / "commands").glob("*.md"))
        return {str(p.relative_to(ROOT)): p.read_text() for p in paths}

    def test_the_agent_is_never_told_where_the_wiki_is(self):
        # Only Leaf knows the folder: the skill and commands must not name it.
        for name, text in self.texts().items():
            for word in ["LEAF_WIKI", "LEAF_DB", "~/wiki", "/home/", "$HOME", "--wiki"]:
                self.assertNotIn(word, text, f"{name} mentions {word}")

    def test_the_skill_enforces_the_tools(self):
        skill = self.texts()["core/skill/SKILL.md"]
        self.assertIn("use the leaf tools, only", skill)
        for tool in ["Read", "Grep", "Glob", "Bash", "Write", "Edit"]:
            self.assertIn(tool, skill.split("## Every session")[0], f"the rule does not name {tool}")
        self.assertIn("Never fall back to files", skill)

    def test_the_skill_does_not_duplicate_what_the_tools_document(self):
        skill = self.texts()["core/skill/SKILL.md"]
        # The batch format and the operation list live in the MCP's own documentation.
        for op in ["add_passage", "create_page", "replace_passage", "declare_value"]:
            self.assertNotIn(op, skill)
        self.assertNotIn("```", skill)

    def test_release_env_is_only_name_value_lines(self):
        for line in (ROOT / "core" / "release.env").read_text().splitlines():
            self.assertTrue(not line.strip() or line.startswith("#") or re.match(r"^[A-Za-z0-9_]+=[^ ]*$", line), line)


if __name__ == "__main__":
    sys.exit(unittest.main(verbosity=1))
