#!/usr/bin/env python3
"""Pennylane firm-level API connector (stdlib only).

Multi-company OAuth 2.0 client for the Pennylane External API v2. Handles the
authorization-code flow, refresh-token *rotation* (critical: each refresh
invalidates the previous refresh token), a persisted token store, cursor
pagination, and the v2 JSON filter syntax.

Credentials are read from the environment, never written to disk:
  PENNYLANE_CLIENT_ID       OAuth app client id (required for auth/refresh)
  PENNYLANE_CLIENT_SECRET   OAuth app client secret (required for auth/refresh)
  PENNYLANE_REDIRECT_URI    Registered callback URL (required for auth-url/exchange)
  PENNYLANE_SCOPES          Space-separated scopes (default: a broad read+write set)
  PENNYLANE_TOKEN_STORE     Token JSON path (default: ~/.config/pennylane/tokens.json)

Only the access/refresh tokens are persisted to PENNYLANE_TOKEN_STORE (0600).

Usage:
  pennylane.py auth-url [--scopes "a b c"] [--state XYZ]
  pennylane.py exchange <authorization_code>
  pennylane.py refresh
  pennylane.py token                       # prints a valid access token (auto-refresh)
  pennylane.py get <path> [--filter JSON] [--limit N] [--cursor C] [--all] [--query k=v ...]
  pennylane.py post <path> --data JSON
  pennylane.py companies [--all]           # firm token: list connected structures
  pennylane.py me                          # whoami: id, email, role
  pennylane.py revoke [--token TOKEN]
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import urllib.error

AUTHORIZE_URL = "https://app.pennylane.com/oauth/authorize"
TOKEN_URL = "https://app.pennylane.com/oauth/token"
REVOKE_URL = "https://app.pennylane.com/oauth/revoke"
API_BASE = "https://app.pennylane.com/api/external/v2"

DEFAULT_SCOPES = (
    "companies:read customer_invoices:all supplier_invoices:all "
    "customers:all suppliers:all ledger_entries:read ledger_accounts:read "
    "products:all categories:all"
)


def _store_path():
    return os.path.expanduser(
        os.environ.get("PENNYLANE_TOKEN_STORE", "~/.config/pennylane/tokens.json")
    )


def load_tokens():
    path = _store_path()
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def save_tokens(tokens):
    """Persist tokens atomically with 0600 perms (refresh-token rotation safe)."""
    path = _store_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(tokens, f, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)  # atomic — a crash never loses the only valid refresh token


def _require(name):
    val = os.environ.get(name)
    if not val:
        sys.exit(f"error: ${name} is not set")
    return val


def _post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        sys.exit(f"error: HTTP {e.code} from {url}\n{body}")


def cmd_auth_url(args):
    client_id = _require("PENNYLANE_CLIENT_ID")
    redirect = _require("PENNYLANE_REDIRECT_URI")
    scopes = args.scopes or os.environ.get("PENNYLANE_SCOPES", DEFAULT_SCOPES)
    params = {
        "client_id": client_id,
        "redirect_uri": redirect,
        "response_type": "code",
        "scope": scopes,
    }
    if args.state:
        params["state"] = args.state
    print(AUTHORIZE_URL + "?" + urllib.parse.urlencode(params))


def cmd_exchange(args):
    out = _post_form(
        TOKEN_URL,
        {
            "client_id": _require("PENNYLANE_CLIENT_ID"),
            "client_secret": _require("PENNYLANE_CLIENT_SECRET"),
            "code": args.code,
            "redirect_uri": _require("PENNYLANE_REDIRECT_URI"),
            "grant_type": "authorization_code",
        },
    )
    _persist_token_response(out)
    print("ok: tokens stored at " + _store_path())


def _persist_token_response(out):
    expires_in = int(out.get("expires_in", 86400))
    save_tokens(
        {
            "access_token": out["access_token"],
            "refresh_token": out["refresh_token"],
            # refresh a minute early to avoid edge-of-expiry 401s
            "expires_at": int(time.time()) + expires_in - 60,
        }
    )


def do_refresh():
    tokens = load_tokens()
    if not tokens.get("refresh_token"):
        sys.exit("error: no refresh_token stored — run `exchange` first")
    out = _post_form(
        TOKEN_URL,
        {
            "grant_type": "refresh_token",
            "refresh_token": tokens["refresh_token"],
            "client_id": _require("PENNYLANE_CLIENT_ID"),
            "client_secret": _require("PENNYLANE_CLIENT_SECRET"),
        },
    )
    _persist_token_response(out)  # rotation: old refresh token is now dead
    return load_tokens()


def cmd_refresh(args):
    do_refresh()
    print("ok: tokens refreshed")


def valid_access_token():
    tokens = load_tokens()
    if not tokens:
        sys.exit("error: no tokens stored — run `auth-url` then `exchange`")
    if int(time.time()) >= tokens.get("expires_at", 0):
        tokens = do_refresh()
    return tokens["access_token"]


def cmd_token(args):
    print(valid_access_token())


def _api_request(method, path, query=None, body=None):
    url = API_BASE + "/" + path.lstrip("/")
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + valid_access_token())
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_txt = e.read().decode(errors="replace")
        sys.exit(f"error: HTTP {e.code} {method} {url}\n{body_txt}")


def _build_query(args):
    query = {}
    for kv in args.query or []:
        if "=" not in kv:
            sys.exit(f"error: --query expects key=value, got {kv!r}")
        k, v = kv.split("=", 1)
        query[k] = v
    if args.filter:
        # Accept raw JSON; re-dump to normalize and validate.
        query["filter"] = json.dumps(json.loads(args.filter), separators=(",", ":"))
    if args.limit:
        query["limit"] = args.limit
    if getattr(args, "cursor", None):
        query["cursor"] = args.cursor
    return query


def _paginate(path, query):
    """Follow cursor pagination, yielding each item across all pages."""
    items = []
    q = dict(query)
    while True:
        page = _api_request("GET", path, query=q)
        items.extend(page.get("items", page.get("data", [])))
        nxt = page.get("next_cursor") or (page.get("pagination") or {}).get("next_cursor")
        has_more = page.get("has_more")
        if not nxt or has_more is False:
            break
        q["cursor"] = nxt
    return items


def cmd_get(args):
    query = _build_query(args)
    if args.all:
        print(json.dumps(_paginate(args.path, query), indent=2, ensure_ascii=False))
    else:
        print(json.dumps(_api_request("GET", args.path, query=query), indent=2, ensure_ascii=False))


def cmd_post(args):
    body = json.loads(args.data)
    print(json.dumps(_api_request("POST", args.path, body=body), indent=2, ensure_ascii=False))


def cmd_companies(args):
    # Firm-scoped tokens expose every connected structure here.
    if args.all:
        print(json.dumps(_paginate("companies", {}), indent=2, ensure_ascii=False))
    else:
        print(json.dumps(_api_request("GET", "companies"), indent=2, ensure_ascii=False))


def cmd_me(args):
    print(json.dumps(_api_request("GET", "me"), indent=2, ensure_ascii=False))


def cmd_revoke(args):
    token = args.token or load_tokens().get("access_token")
    if not token:
        sys.exit("error: no token to revoke")
    _post_form(
        REVOKE_URL,
        {
            "client_id": _require("PENNYLANE_CLIENT_ID"),
            "client_secret": _require("PENNYLANE_CLIENT_SECRET"),
            "token": token,
        },
    )
    print("ok: token revoked")


def main():
    p = argparse.ArgumentParser(description="Pennylane firm API connector")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("auth-url", help="print the OAuth authorization URL")
    a.add_argument("--scopes")
    a.add_argument("--state")
    a.set_defaults(func=cmd_auth_url)

    e = sub.add_parser("exchange", help="exchange an authorization code for tokens")
    e.add_argument("code")
    e.set_defaults(func=cmd_exchange)

    sub.add_parser("refresh", help="force a token refresh").set_defaults(func=cmd_refresh)
    sub.add_parser("token", help="print a valid access token").set_defaults(func=cmd_token)
    sub.add_parser("me", help="whoami (id, email, role)").set_defaults(func=cmd_me)

    g = sub.add_parser("get", help="GET an API v2 path")
    g.add_argument("path")
    g.add_argument("--filter", help="v2 filter as a JSON array")
    g.add_argument("--limit", type=int)
    g.add_argument("--cursor")
    g.add_argument("--query", nargs="*", help="extra key=value query params")
    g.add_argument("--all", action="store_true", help="follow cursor pagination")
    g.set_defaults(func=cmd_get)

    po = sub.add_parser("post", help="POST JSON to an API v2 path")
    po.add_argument("path")
    po.add_argument("--data", required=True, help="request body as JSON")
    po.set_defaults(func=cmd_post)

    c = sub.add_parser("companies", help="list connected structures (firm token)")
    c.add_argument("--all", action="store_true")
    c.set_defaults(func=cmd_companies)

    r = sub.add_parser("revoke", help="revoke a token")
    r.add_argument("--token")
    r.set_defaults(func=cmd_revoke)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
