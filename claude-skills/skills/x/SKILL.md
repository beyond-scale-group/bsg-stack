---
name: x
description: >-
  Manage the user's personal X (Twitter) account through the official X API v2: read likes,
  bookmarks, timeline, mentions, search, profiles and DMs; and — only after explicit
  confirmation — post, reply, like, follow, bookmark and send DMs. Use when the user says
  "mes bookmarks", "mes likes", "mon twitter", "tweet", "poste sur X", "DM sur X", "relance sur
  X", "check my X", "search X", or asks to set up the X app / X API access.
version: 0.1.0
---

# X skill

Wraps the official X API v2 for the user's **personal account**. No third-party service, no
scraping, no browser: a browser run against x.com hits X's "confirm you are human" wall.

- Setup (X developer app, OAuth token): [`references/setup.md`](references/setup.md) — read it
  first if `~/.env` has no `X_ACCESS_TOKEN`, or when the user asks to set up or fix access.
- CLI: `node ~/.claude/skills/x/scripts/x.mjs <command>` (JSON on stdout, no dependencies).
- Credentials live in `~/.env` (`X_CLIENT_ID`, `X_ACCESS_TOKEN`, `X_REFRESH_TOKEN`). Never print,
  paste or commit them. The CLI refreshes the token itself when it expires.

## Commands

```bash
# read — run freely
x.mjs me
x.mjs user <username>
x.mjs likes [--user <u>] [--max 20] [--next <token>]
x.mjs bookmarks [--max 20] [--next <token>]
x.mjs timeline | mentions
x.mjs search "<query>" [--max 20]
x.mjs following [--user <u>]
x.mjs dms [<username>]

# write — DRY RUN unless --yes
x.mjs post "<text>" [--reply <tweet_id>]
x.mjs like|unlike|bookmark|unbookmark <tweet_id>
x.mjs follow|unfollow <username>
x.mjs dm <username> "<text>"
```

## Rules for writes

Posting, replying, liking, following, bookmarking and DMs act **in the user's own name** and
cannot be taken back once seen. So:

1. Run the command **without `--yes`** first. It sends nothing and prints the exact payload.
2. Show the user the exact text and recipient and **wait for an explicit yes** for that action.
   An earlier approval does not cover a different message or a different person.
3. Only then re-run the same command with `--yes`.
4. **One recipient per DM, no loops.** For several people, show each message and get a yes per
   person, and space them out — never send a batch in one go. Reading DMs and bookmarks is
   private data: summarise what is needed, do not paste it into other tools or repos.
5. Writing as someone else, impersonation, spam, or mass unsolicited DMs: refuse.

## Typical uses

- **Find guests / leads:** `bookmarks` and `likes`, then group the authors that come up often.
- **Personalise an outreach:** `search "from:<handle>"` or `user <handle>` to find something
  real to refer to, then draft the message and send it only after the user approves.
- **Follow up:** `dms <username>` to see whether the person already answered before nudging.

## Cost

On the documented pay-per-usage plan every call is billed per resource returned or per request
(see the table in `references/setup.md`). Keep `--max` small (default 20), do not page through
everything without a reason, and mention it to the user before a large read — e.g. 1,000
bookmarks is about $1, but reading DMs is ten times dearer per item.

## Limits

- Endpoints, parameters and scopes were checked against docs.x.com on 2026-11-23. The current
  docs call the field parameter `post.fields`; the CLI falls back to `tweet.fields` if X
  answers 400. Replies use `reply.in_reply_to_tweet_id`; text is capped at 280 characters unless
  the account has X Premium.
- What each endpoint returns, and how much, depends on the user's X API plan. A `403` usually
  means the plan or the app permissions do not include it — see Troubleshooting in
  `references/setup.md`.
- Pagination: pass the `next_token` from `meta` as `--next`.
- `--max` is clamped to 100 (5 minimum on likes/bookmarks/timeline, 10 on search).

## How to improve this skill

This file is a cached copy of `claude-skills/skills/x/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — local copies are overwritten by
the BSG install flow. To improve the skill: clone bsg-stack, edit on a
branch, open a PR against `main`.
