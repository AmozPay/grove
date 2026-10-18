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


def frontmatter(path: Path) -> dict:
    match = re.match(r"---\n(.*?)\n---\n", path.read_text(), re.S)
    assert match, f"{path} has no frontmatter"
    return dict(re.findall(r"^([\w-]+): (.*)$", match.group(1), re.M))


class ClaudeCode(unittest.TestCase):
    def test_manifest(self):
        manifest = json.loads((CC / ".claude-plugin" / "plugin.json").read_text())
        self.assertEqual(manifest["name"], "llm-wiki")
        self.assertEqual(manifest["version"], (ROOT / "VERSION").read_text().strip())
        server = manifest["mcpServers"]["wikileaf"]
        self.assertEqual(server["type"], "stdio")
        self.assertEqual(server["command"], "${CLAUDE_PLUGIN_ROOT}/bin/run")
        # The editor build is named on purpose: write access is never implicit.
        self.assertEqual(server["args"], ["wikileaf-mcp-editor"])

    def test_marketplace_points_at_the_plugin(self):
        market = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text())
        source = market["plugins"][0]["source"]
        self.assertTrue((ROOT / source / ".claude-plugin" / "plugin.json").is_file())

    def test_skill_and_commands_have_frontmatter(self):
        self.assertEqual(frontmatter(CC / "skills" / "llm-wiki" / "SKILL.md")["name"], "llm-wiki")
        for name in ["init", "ingest", "query", "lint"]:
            fm = frontmatter(CC / "commands" / f"{name}.md")
            self.assertTrue(fm["description"], name)

    def test_no_placeholder_is_left(self):
        for path in list((CC / "commands").glob("*.md")) + list((ROOT / "hosts" / "hermes").rglob("*.md")):
            self.assertNotIn("{{", path.read_text(), str(path))

    def test_commands_use_the_plugin_launcher(self):
        text = (CC / "commands" / "init.md").read_text()
        self.assertIn("${CLAUDE_PLUGIN_ROOT}/bin/run wikileaf editor init", text)
        self.assertIn("$ARGUMENTS", text)

    def test_scripts_are_executable(self):
        for rel in ["bin/run"]:
            self.assertTrue((CC / rel).stat().st_mode & stat.S_IXUSR, rel)
        self.assertTrue((ROOT / "hosts" / "hermes" / "bin" / "run").stat().st_mode & stat.S_IXUSR)


class Hermes(unittest.TestCase):
    def test_skill_and_config(self):
        skill = ROOT / "hosts" / "hermes" / "skills" / "research" / "llm-wiki" / "SKILL.md"
        fm = frontmatter(skill)
        self.assertEqual(fm["name"], "llm-wiki")
        self.assertIn("## Workflows", skill.read_text())
        snippet = (ROOT / "hosts" / "hermes" / "config.yaml.snippet").read_text()
        self.assertIn("mcp_servers:", snippet)
        self.assertIn("wikileaf-mcp-editor", snippet)


class Core(unittest.TestCase):
    def texts(self):
        paths = [ROOT / "core" / "skill" / "SKILL.md"] + sorted((ROOT / "core" / "commands").glob("*.md"))
        return {str(p.relative_to(ROOT)): p.read_text() for p in paths}

    def test_the_agent_is_never_told_where_the_wiki_is(self):
        # Only Wikileaf knows the folder: the skill and commands must not name it.
        for name, text in self.texts().items():
            for word in ["WIKILEAF_WIKI", "WIKILEAF_DB", "~/wiki", "/home/", "$HOME", "--wiki"]:
                self.assertNotIn(word, text, f"{name} mentions {word}")

    def test_the_skill_enforces_the_tools(self):
        skill = self.texts()["core/skill/SKILL.md"]
        self.assertIn("use the wikileaf tools, only", skill)
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
            self.assertTrue(not line.strip() or line.startswith("#") or re.match(r"^[A-Z0-9_]+=[^ ]*$", line), line)


if __name__ == "__main__":
    sys.exit(unittest.main(verbosity=1))
