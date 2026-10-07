"""
Tests for upload-session-to-gbrain.py — the opt-in SessionEnd hook that
uploads a full session transcript to a personal gbrain.

Covers:
1. Redaction masks credential-shaped strings (API keys, bearer tokens,
   64-hex secrets, connection-string passwords) while leaving ordinary
   text and 40-hex git SHAs alone.
2. Transcript rendering includes user turns, assistant turns, tool calls,
   and truncated tool results.
3. Payload splitting stays under the byte limit on paragraph boundaries.
4. The opt-in gate: without GBRAIN_INGEST_URL + GBRAIN_MCP_TOKEN the hook
   exits 0 without reading the transcript or touching the network.
5. The updater registers the SessionEnd hook idempotently.
"""

import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"


def _load_uploader() -> types.ModuleType:
    spec = importlib.util.spec_from_file_location(
        "upload_session_to_gbrain", SCRIPTS_DIR / "upload-session-to-gbrain.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _load_settings() -> types.ModuleType:
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    from bsg_updater import settings  # noqa: WPS433 (deferred import)
    return settings


class TestRedaction(unittest.TestCase):
    def setUp(self):
        self.mod = _load_uploader()

    def test_masks_known_key_prefixes(self):
        for secret in [
            "sk-ant-api03-abcdefghij1234",
            "sk-proj-abcdefghijklmnopqrstuv",
            "ze_FAKEtestKey0000",
            "gbrain_abcdef123456789",
            "ghp_abcdefghijklmnopqrstuv123456",
            "github_pat_11ABCDEFGHIJKLMNOPQRST",
            "xoxb-1234567890-abcdefghijk",
            "AKIAIOSFODNN7EXAMPLE",
        ]:
            clean, hits = self.mod.redact(f"the key is {secret} ok")
            self.assertNotIn(secret, clean, secret)
            self.assertGreaterEqual(hits, 1, secret)

    def test_masks_64_hex_but_not_git_sha(self):
        token64 = "a" * 64
        sha40 = "b" * 40
        clean, _ = self.mod.redact(f"token {token64} commit {sha40}")
        self.assertNotIn(token64, clean)
        self.assertIn(sha40, clean)

    def test_masks_connection_string_password(self):
        clean, _ = self.mod.redact("postgresql://user:s3cretpw@host:5432/db")
        self.assertNotIn("s3cretpw", clean)
        self.assertIn("postgresql://user:[REDACTED]@host:5432/db", clean)

    def test_masks_generic_assignment_keeps_name(self):
        clean, _ = self.mod.redact("OPENAI_API_KEY=abcd1234efgh5678")
        self.assertIn("OPENAI_API_KEY=", clean)
        self.assertNotIn("abcd1234efgh5678", clean)

    def test_leaves_plain_text_alone(self):
        text = "nothing secret here, just a sentence with numbers 12345."
        clean, hits = self.mod.redact(text)
        self.assertEqual(text, clean)
        self.assertEqual(hits, 0)


class TestRendering(unittest.TestCase):
    def setUp(self):
        self.mod = _load_uploader()

    def _write_transcript(self, records) -> Path:
        tmp = tempfile.NamedTemporaryFile(
            "w", suffix=".jsonl", delete=False, dir=tempfile.gettempdir()
        )
        for rec in records:
            tmp.write(json.dumps(rec) + "\n")
        tmp.close()
        return Path(tmp.name)

    def test_renders_full_conversation(self):
        path = self._write_transcript(
            [
                {"type": "user", "message": {"role": "user", "content": "hello brain"}},
                {
                    "type": "assistant",
                    "message": {
                        "role": "assistant",
                        "content": [
                            {"type": "text", "text": "hi there"},
                            {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}},
                        ],
                    },
                },
                {
                    "type": "user",
                    "message": {
                        "role": "user",
                        "content": [
                            {"type": "tool_result", "content": "file-a\nfile-b"}
                        ],
                    },
                },
            ]
        )
        md = self.mod.render_markdown(path, "sess1234", "my-project")
        self.assertIn("## User\n\nhello brain", md)
        self.assertIn("## Assistant\n\nhi there", md)
        self.assertIn("**Bash**", md)
        self.assertIn("file-a", md)
        self.assertIn("type: source", md)
        self.assertIn("session_id: sess1234", md)

    def test_tool_results_truncated(self):
        long_output = "x" * 10000
        path = self._write_transcript(
            [
                {
                    "type": "user",
                    "message": {
                        "role": "user",
                        "content": [{"type": "tool_result", "content": long_output}],
                    },
                }
            ]
        )
        with patch.object(self.mod, "TOOL_RESULT_MAX", 100):
            md = self.mod.render_markdown(path, "s", "p")
        self.assertIn("[truncated", md)
        self.assertNotIn(long_output, md)


class TestSplitting(unittest.TestCase):
    def setUp(self):
        self.mod = _load_uploader()

    def test_small_payload_single_part(self):
        self.assertEqual(len(self.mod.split_parts("short doc", 1000)), 1)

    def test_large_payload_splits_under_limit(self):
        doc = "\n\n".join(f"paragraph {i} " + "words " * 50 for i in range(100))
        parts = self.mod.split_parts(doc, 5000)
        self.assertGreater(len(parts), 1)
        for part in parts:
            self.assertLessEqual(len(part.encode("utf-8")), 5000 + 400)


class TestOptInGate(unittest.TestCase):
    def test_exits_zero_without_env(self):
        mod = _load_uploader()
        with patch.dict("os.environ", {}, clear=True):
            with patch.object(mod, "post_part") as mock_post:
                self.assertEqual(mod.main(), 0)
        mock_post.assert_not_called()


class TestHookRegistration(unittest.TestCase):
    def test_registers_once_and_is_idempotent(self):
        settings_mod = _load_settings()
        with tempfile.TemporaryDirectory() as td:
            settings_file = Path(td) / "settings.json"
            with patch.object(settings_mod, "SETTINGS_FILE", settings_file):
                settings_mod.register_session_end_hook()
                settings_mod.register_session_end_hook()  # second run: no-op
            data = json.loads(settings_file.read_text())
            entries = data["hooks"]["SessionEnd"]
            self.assertEqual(len(entries), 1)
            self.assertIn(
                "upload-session-to-gbrain.py", entries[0]["hooks"][0]["command"]
            )


if __name__ == "__main__":
    unittest.main()
