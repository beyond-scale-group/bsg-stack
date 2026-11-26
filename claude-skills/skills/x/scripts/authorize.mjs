#!/usr/bin/env node
// One-off OAuth 2.0 (PKCE) authorisation for the X API v2 — read-only scopes.
// Reads X_CLIENT_ID (and optionally X_CLIENT_SECRET) from ~/.env, opens the consent page,
// receives the callback on 127.0.0.1:8765 and stores X_ACCESS_TOKEN / X_REFRESH_TOKEN in ~/.env.
// Tokens are never printed. No dependencies.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const ENV_FILE = path.join(os.homedir(), '.env');
const PORT = 8765;
const REDIRECT = `http://127.0.0.1:${PORT}/callback`;
const SCOPES = [
  'tweet.read', 'tweet.write', 'users.read', 'bookmark.read', 'bookmark.write',
  'like.read', 'like.write', 'follows.read', 'follows.write', 'dm.read', 'dm.write', 'offline.access',
].join(' ');

function readEnv() {
  const out = {};
  if (!fs.existsSync(ENV_FILE)) return out;
  for (const line of fs.readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (m) out[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
  }
  return out;
}

function writeEnv(updates) {
  let lines = fs.existsSync(ENV_FILE) ? fs.readFileSync(ENV_FILE, 'utf8').split('\n') : [];
  for (const [k, v] of Object.entries(updates)) {
    const i = lines.findIndex((l) => new RegExp(`^\\s*(export\\s+)?${k}=`).test(l));
    const entry = `${k}=${v}`;
    if (i >= 0) lines[i] = entry;
    else lines.push(entry);
  }
  lines = lines.filter((l, i, a) => !(l === '' && i === a.length - 1));
  fs.writeFileSync(ENV_FILE, lines.join('\n') + '\n', { mode: 0o600 });
}

const env = readEnv();
const clientId = env.X_CLIENT_ID;
const clientSecret = env.X_CLIENT_SECRET; // only for confidential apps
if (!clientId) {
  console.error('X_CLIENT_ID is missing from ~/.env. Add it, then run this script again.');
  process.exit(1);
}

const b64url = (b) => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const verifier = b64url(crypto.randomBytes(48));
const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
const state = b64url(crypto.randomBytes(16));

const authUrl =
  'https://x.com/i/oauth2/authorize?' +
  new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: REDIRECT,
    scope: SCOPES,
    state,
    code_challenge: challenge,
    code_challenge_method: 'S256',
  });

async function exchange(code) {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: REDIRECT,
    code_verifier: verifier,
    client_id: clientId,
  });
  const headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
  if (clientSecret) {
    headers.Authorization = 'Basic ' + Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  }
  const res = await fetch('https://api.x.com/2/oauth2/token', { method: 'POST', headers, body });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Token exchange failed (HTTP ${res.status}): ${json.error ?? ''} ${json.error_description ?? ''}`.trim());
  return json;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, REDIRECT);
  if (url.pathname !== '/callback') {
    res.writeHead(404).end();
    return;
  }
  const done = (code, msg) => {
    res.writeHead(code, { 'Content-Type': 'text/plain; charset=utf-8' }).end(msg);
  };
  try {
    if (url.searchParams.get('error')) throw new Error(`X refused: ${url.searchParams.get('error')}`);
    if (url.searchParams.get('state') !== state) throw new Error('State mismatch — aborted.');
    const tok = await exchange(url.searchParams.get('code'));
    const updates = { X_ACCESS_TOKEN: tok.access_token };
    if (tok.refresh_token) updates.X_REFRESH_TOKEN = tok.refresh_token;
    writeEnv(updates);
    console.log(`Done. Tokens saved to ~/.env (scopes: ${tok.scope}). Nothing was printed.`);
    done(200, 'Autorisation reçue. Tu peux fermer cet onglet et revenir au terminal.');
  } catch (e) {
    console.error(String(e.message ?? e));
    done(400, 'Échec — voir le terminal.');
  } finally {
    setTimeout(() => server.close(() => process.exit(0)), 200);
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('Open this URL in the browser where you are logged in to X:\n');
  console.log(authUrl + '\n');
  const opener = process.platform === 'darwin' ? 'open' : 'xdg-open';
  try {
    spawn(opener, [authUrl], { stdio: 'ignore', detached: true }).on('error', () => {}).unref();
  } catch {}
  console.log(`Waiting for the callback on ${REDIRECT} (Ctrl+C to cancel)…`);
});
