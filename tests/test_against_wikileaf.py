#!/usr/bin/env python3
"""The plugin against the real Wikileaf binaries, so the skill cannot drift
from what the tools do. Needs WIKILEAF_BIN_DIR: a folder with wikileaf,
wikileaf-mcp and wikileaf-mcp-editor (an unpacked release, or target/debug
after building them). Skipped without it."""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = os.environ.get("WIKILEAF_BIN_DIR")
RUN = ROOT / "core" / "bin" / "run"


def mcp(binary: str, wiki: Path, calls: list[tuple[str, dict]]) -> list[dict]:
    """Talk to a server over stdio: initialize, then the given tool calls."""
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    ]
    for i, (name, arguments) in enumerate(calls):
        messages.append({"jsonrpc": "2.0", "id": 10 + i, "method": "tools/call", "params": {"name": name, "arguments": arguments}})
    env = {**os.environ, "WIKILEAF_WIKI": str(wiki), "WIKILEAF_DB": str(wiki.parent / "cache.db")}
    proc = subprocess.Popen([str(RUN), binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    for message in messages:
        proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()
    replies = {}
    while len(replies) < len(messages) - 1:  # one notification has no reply
        line = proc.stdout.readline()
        if not line:
            break
        reply = json.loads(line)
        replies[reply["id"]] = reply
    proc.stdin.close()
    proc.wait(timeout=10)
    proc.stdout.close()
    proc.stderr.close()
    return [replies[k] for k in sorted(replies)]


def cli(*args: str, wiki: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "WIKILEAF_WIKI": str(wiki), "WIKILEAF_DB": str(wiki.parent / "cli.db")}
    return subprocess.run([str(RUN), "wikileaf", *args], capture_output=True, text=True, env=env)


def skill_text() -> str:
    return (ROOT / "core" / "skill" / "SKILL.md").read_text()


@unittest.skipUnless(BIN and (Path(BIN) / "wikileaf-mcp-editor").exists(), "WIKILEAF_BIN_DIR not set")
class AgainstWikileaf(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["WIKILEAF_BIN_DIR"] = BIN
        cls.tmp = tempfile.TemporaryDirectory()
        cls.wiki = Path(cls.tmp.name) / "wiki"

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_a_tool_the_skill_names_exists(self):
        wiki = Path(self.tmp.name) / "tools" / "wiki"
        wiki.parent.mkdir()
        self.assertEqual(cli("editor", "init", wiki=wiki).returncode, 0)
        replies = mcp("wikileaf-mcp-editor", wiki, [])
        tools = {t["name"]: t for t in replies[1]["result"]["tools"]}
        named = set(re.findall(r"`((?:editor_)?[a-z]+)`", skill_text())) & ({"guide", "search", "cite", "metadata", "people", "stats"} | {n for n in tools if n.startswith("editor_")})
        self.assertTrue({"guide", "search", "cite", "editor_check", "editor_apply", "editor_conformance"} <= named)
        for name in named:
            self.assertIn(name, tools, f"the skill names {name}, which the server does not have")
        # The read-only build has no editor tools.
        read_only = mcp("wikileaf-mcp", wiki, [])
        self.assertFalse([t for t in read_only[1]["result"]["tools"] if t["name"].startswith("editor_")])

    def test_the_server_documents_its_own_use(self):
        # The skill leaves the tool catalogue and the batch format to the server.
        wiki = Path(self.tmp.name) / "docs" / "wiki"
        wiki.parent.mkdir()
        cli("editor", "init", wiki=wiki)
        replies = mcp("wikileaf-mcp-editor", wiki, [])
        result = replies[0]["result"]
        self.assertIn("guide", result["instructions"])
        tools = {t["name"]: t for t in replies[1]["result"]["tools"]}
        for name, tool in tools.items():
            self.assertTrue(tool.get("description"), f"{name} has no description")
        schema = json.dumps(tools["editor_apply"]["inputSchema"])
        self.assertIn("create_page", schema)
        self.assertIn("Example", schema)

    def test_the_guide_works_without_telling_the_location(self):
        wiki = Path(self.tmp.name) / "guide" / "wiki"
        wiki.parent.mkdir()
        cli("editor", "init", "--domain", "Greenhouse", wiki=wiki)
        replies = mcp("wikileaf-mcp-editor", wiki, [("guide", {})])
        text = replies[2]["result"]["content"][0]["text"]
        self.assertIn("Greenhouse", json.loads(text)["schema"])
        self.assertNotIn(str(wiki), text)


if __name__ == "__main__":
    sys.exit(unittest.main(verbosity=1))
