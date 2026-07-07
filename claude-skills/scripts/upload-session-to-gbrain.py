#!/usr/bin/env python3
"""Upload a finished Claude Code session transcript to a personal gbrain.

Registered as a Claude Code ``SessionEnd`` hook by the BSG updater
(``bsg_updater.settings.register_session_end_hook``). Claude Code invokes it
with a JSON payload on stdin::

    {"session_id": "...", "transcript_path": "...", "cwd": "...", ...}

Strictly opt-in: the hook exits silently unless BOTH env vars are set —

    GBRAIN_INGEST_URL   e.g. https://my-brain.cleverapps.io
    GBRAIN_MCP_TOKEN    a gbrain bearer token with write scope

Behavior:
  1. Renders the FULL transcript (user turns, assistant turns, tool calls,
     tool results) to markdown. Tool results are truncated per-block at
     GBRAIN_CAPTURE_TOOL_RESULT_MAX chars (default 2000; 0 = unlimited).
  2. Redacts credential-shaped strings (API keys, bearer tokens, 64-hex
     secrets, connection-string passwords). Redaction is blocking by
     design — transcripts are secret-dense.
  3. Splits into parts if the payload exceeds GBRAIN_CAPTURE_MAX_BYTES
     (default 900000, under gbrain's 1 MB /ingest cap).
  4. POSTs each part to ``$GBRAIN_INGEST_URL/ingest`` as text/markdown with
     a deterministic slug (gbrain dedups on content hash within 24h, so
     re-runs are idempotent).

Never fails the session: every error path logs to
``~/.claude/logs/gbrain-capture.log`` and exits 0. Pure stdlib.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))
LOG_FILE = CLAUDE_DIR / "logs" / "gbrain-capture.log"

TOOL_RESULT_MAX = int(os.environ.get("GBRAIN_CAPTURE_TOOL_RESULT_MAX", "2000"))
MAX_BYTES = int(os.environ.get("GBRAIN_CAPTURE_MAX_BYTES", "900000"))
HTTP_TIMEOUT = 20

# Credential-shaped patterns, applied to the rendered markdown. Ordered:
# specific prefixes first, then structural shapes, then generic assignments.
REDACT_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # Connection-string passwords: keep scheme+user, mask the password.
    (re.compile(r"(\w+://[^:/@\s]+:)[^@\s]+(@)"), r"\1[REDACTED]\2"),
    # Known key prefixes.
    (re.compile(r"\bsk-ant-[A-Za-z0-9_-]{8,}"), "[REDACTED]"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"), "[REDACTED]"),
    (re.compile(r"\bze_[A-Za-z0-9]{8,}"), "[REDACTED]"),
    (re.compile(r"\bgbrain_[A-Za-z0-9_-]{8,}"), "[REDACTED]"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "[REDACTED]"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), "[REDACTED]"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"), "[REDACTED]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED]"),
    # Bearer headers and 64-hex secrets (bootstrap/admin tokens, sha-shaped
    # keys — git SHAs are 40-hex and stay untouched).
    (re.compile(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/=-]{16,}"), r"\1[REDACTED]"),
    (re.compile(r"\b[0-9a-f]{64}\b"), "[REDACTED]"),
    # Generic KEY=value / "token": "value" assignments: keep the name.
    (
        re.compile(
            r"(?i)([\"']?[\w.-]*(?:api[_-]?key|apikey|token|secret|passwd|password)[\"']?"
            r"\s*[:=]\s*[\"']?)(?!\[REDACTED\])[^\s\"',;]{8,}"
        ),
        r"\1[REDACTED]",
    ),
]


def log(msg: str) -> None:
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with LOG_FILE.open("a") as fh:
            fh.write(f"{stamp} {msg}\n")
    except OSError:
        pass


def redact(text: str) -> tuple[str, int]:
    """Mask credential-shaped strings. Returns (clean_text, hit_count)."""
    hits = 0
    for pattern, repl in REDACT_PATTERNS:
        text, n = pattern.subn(repl, text)
        hits += n
    return text, hits


def _truncate(text: str, limit: int) -> str:
    if limit <= 0 or len(text) <= limit:
        return text
    return text[:limit] + f"\n… [truncated, {len(text) - limit} chars omitted]"


def _content_blocks(message: dict) -> list[dict]:
    content = message.get("content")
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    return []


def render_markdown(transcript_path: Path, session_id: str, project: str) -> str:
    """Render a Claude Code JSONL transcript to a full-conversation page."""
    lines: list[str] = []
    turn_count = 0

    with transcript_path.open() as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except json.JSONDecodeError:
                continue
            rec_type = rec.get("type")
            message = rec.get("message")
            if rec_type not in ("user", "assistant") or not isinstance(message, dict):
                continue

            for block in _content_blocks(message):
                btype = block.get("type")
                if btype == "text":
                    text = (block.get("text") or "").strip()
                    if not text:
                        continue
                    turn_count += 1
                    role = "User" if rec_type == "user" else "Assistant"
                    lines.append(f"## {role}\n\n{text}\n")
                elif btype == "tool_use":
                    name = block.get("name", "?")
                    params = json.dumps(block.get("input", {}), ensure_ascii=False)
                    lines.append(f"> 🔧 **{name}** `{_truncate(params, 300)}`\n")
                elif btype == "tool_result":
                    content = block.get("content")
                    if isinstance(content, list):
                        content = "\n".join(
                            b.get("text", "") for b in content if isinstance(b, dict)
                        )
                    text = str(content or "").strip()
                    if text:
                        lines.append(
                            "<details><summary>tool result</summary>\n\n"
                            f"```\n{_truncate(text, TOOL_RESULT_MAX)}\n```\n\n</details>\n"
                        )

    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    header = (
        "---\n"
        "type: source\n"
        f"tags: [claude-code, session, {project}]\n"
        f"project: {project}\n"
        f"session_id: {session_id}\n"
        f"date: {day}\n"
        "---\n\n"
        f"# Claude Code session — {project} — {day}\n\n"
        f"Full transcript ({turn_count} conversation turns), captured "
        "automatically at session end.\n\n"
    )
    return header + "\n".join(lines)


def split_parts(markdown: str, max_bytes: int) -> list[str]:
    """Split on paragraph boundaries so each part stays under max_bytes."""
    if len(markdown.encode("utf-8")) <= max_bytes:
        return [markdown]
    parts: list[str] = []
    current: list[str] = []
    size = 0
    for para in markdown.split("\n\n"):
        chunk = para + "\n\n"
        chunk_len = len(chunk.encode("utf-8"))
        if size + chunk_len > max_bytes and current:
            parts.append("".join(current))
            current, size = [], 0
        current.append(chunk)
        size += chunk_len
    if current:
        parts.append("".join(current))
    return parts


def post_part(
    base_url: str, token: str, body: str, slug: str, source_uri: str
) -> tuple[int, str]:
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/ingest",
        data=body.encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "text/markdown",
            "X-Gbrain-Source-Id": "claude-code-sessions",
            "X-Gbrain-Source-Uri": source_uri,
            "X-Gbrain-Slug": slug,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return resp.status, resp.read(500).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read(500).decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as e:
        return 0, str(e)


def main() -> int:
    base_url = os.environ.get("GBRAIN_INGEST_URL", "").strip()
    token = os.environ.get("GBRAIN_MCP_TOKEN", "").strip()
    if not base_url or not token:
        return 0  # not opted in — stay silent

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        log("skip: no valid hook payload on stdin")
        return 0

    transcript_path = Path(payload.get("transcript_path", ""))
    session_id = str(payload.get("session_id", "unknown"))
    cwd = payload.get("cwd") or os.getcwd()
    project = Path(cwd).name or "unknown-project"

    if not transcript_path.is_file():
        log(f"skip: transcript not found: {transcript_path}")
        return 0

    try:
        markdown = render_markdown(transcript_path, session_id, project)
    except OSError as e:
        log(f"error rendering transcript: {e}")
        return 0

    markdown, redactions = redact(markdown)

    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    slug_base = f"sources/claude-sessions/{day}-{project}-{session_id[:8]}"
    source_uri = f"claude-code:{project}:{session_id}"

    parts = split_parts(markdown, MAX_BYTES)
    ok = 0
    for i, part in enumerate(parts, start=1):
        slug = slug_base if len(parts) == 1 else f"{slug_base}--part-{i}"
        status, detail = post_part(base_url, token, part, slug, source_uri)
        if 200 <= status < 300:
            ok += 1
        else:
            log(f"upload failed ({slug}): HTTP {status} {detail}")

    log(
        f"session {session_id[:8]} ({project}): {ok}/{len(parts)} part(s) uploaded, "
        f"{redactions} redaction(s), {len(markdown)} chars"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
