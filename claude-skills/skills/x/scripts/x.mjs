#!/usr/bin/env node
// x.mjs — small CLI over the official X API v2. No dependencies.
// Auth, two modes (`x.mjs auth` says which one is active):
//  - OAuth 1.0a user context when X_API_KEY, X_API_SECRET, X_OAUTH1_ACCESS_TOKEN and
//    X_OAUTH1_ACCESS_SECRET are all set. Keys do not expire, nothing is ever rewritten.
//  - otherwise OAuth 2.0: X_ACCESS_TOKEN / X_REFRESH_TOKEN / X_CLIENT_ID (see authorize.mjs),
//    refreshed and re-saved to ~/.env when the 2 h access token expires.
// X_* variables of the process environment win over ~/.env, which is optional.
// READ commands run directly. WRITE commands are a DRY RUN unless --yes is passed.
// Output is JSON on stdout. Tokens and keys are never printed.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { authorizationHeader } from './oauth1.mjs';

const ENV_FILE = path.join(os.homedir(), '.env');
const API = 'https://api.x.com/2';
const OAUTH1_VARS = ['X_API_KEY', 'X_API_SECRET', 'X_OAUTH1_ACCESS_TOKEN', 'X_OAUTH1_ACCESS_SECRET'];
const OAUTH2_VARS = ['X_ACCESS_TOKEN', 'X_REFRESH_TOKEN', 'X_CLIENT_ID', 'X_CLIENT_SECRET'];
// OAuth 2.0 only, per the docs.x.com OpenAPI spec (checked 2026-11-26): POST and DELETE
// /2/users/{id}/bookmarks list only OAuth2UserToken.
const OAUTH2_ONLY = { bookmark: 'POST /2/users/{id}/bookmarks', unbookmark: 'DELETE /2/users/{id}/bookmarks/{tweet_id}' };
const OAUTH1_RETIREMENT = '2027-01-31'; // docs.x.com, "Migrate from OAuth 1.0a to OAuth 2.0"

function readEnvFile() {
  const out = {};
  if (!fs.existsSync(ENV_FILE)) return out;
  for (const line of fs.readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (m) out[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
  }
  return out;
}
const fromProcess = () => Object.fromEntries(Object.entries(process.env).filter(([k, v]) => k.startsWith('X_') && v));
const readEnv = () => ({ ...readEnvFile(), ...fromProcess() });
function writeEnv(updates) {
  const lines = fs.existsSync(ENV_FILE) ? fs.readFileSync(ENV_FILE, 'utf8').split('\n') : [];
  for (const [k, v] of Object.entries(updates)) {
    const i = lines.findIndex((l) => new RegExp(`^\\s*(export\\s+)?${k}=`).test(l));
    if (i >= 0) lines[i] = `${k}=${v}`;
    else lines.push(`${k}=${v}`);
  }
  fs.writeFileSync(ENV_FILE, lines.join('\n').replace(/\n*$/, '\n'), { mode: 0o600 });
}

function fail(msg, extra) {
  console.error(JSON.stringify({ error: msg, ...extra }));
  process.exit(1);
}

let env = readEnv();
const mode = OAUTH1_VARS.every((k) => env[k]) ? 'oauth1' : env.X_ACCESS_TOKEN ? 'oauth2' : 'none';

// Why a refresh cannot be saved, or null if it can. Checked BEFORE refreshing: X rotates the
// refresh token, so refreshing without being able to store the new one would lose access.
function refreshBlocker() {
  const proc = fromProcess();
  if (proc.X_REFRESH_TOKEN && proc.X_REFRESH_TOKEN !== readEnvFile().X_REFRESH_TOKEN)
    return 'X_REFRESH_TOKEN comes from the process environment, so the rotated token could not replace it';
  try {
    fs.accessSync(fs.existsSync(ENV_FILE) ? ENV_FILE : path.dirname(ENV_FILE), fs.constants.W_OK);
  } catch (e) {
    return `~/.env is not writable (${e.code})`;
  }
  return null;
}

async function refresh() {
  if (!env.X_REFRESH_TOKEN || !env.X_CLIENT_ID) fail('Token expired and no refresh token — run authorize.mjs again.');
  const blocker = refreshBlocker();
  if (blocker) fail(`Access token expired and cannot be refreshed: ${blocker}. Nothing was refreshed, the refresh token is still valid. On a server whose secrets are read-only, use the OAuth 1.0a mode (see references/setup.md).`);
  const headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
  if (env.X_CLIENT_SECRET) headers.Authorization = 'Basic ' + Buffer.from(`${env.X_CLIENT_ID}:${env.X_CLIENT_SECRET}`).toString('base64');
  const res = await fetch(`${API}/oauth2/token`, {
    method: 'POST',
    headers,
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: env.X_REFRESH_TOKEN, client_id: env.X_CLIENT_ID }),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) fail('Token refresh failed — run authorize.mjs again.', { status: res.status });
  const upd = { X_ACCESS_TOKEN: j.access_token };
  if (j.refresh_token) upd.X_REFRESH_TOKEN = j.refresh_token; // refresh tokens rotate
  try {
    writeEnv(upd);
  } catch (e) {
    fail(`Token refreshed but could not be saved to ~/.env (${e.code}): the old refresh token is now spent — run authorize.mjs again.`);
  }
  env = { ...env, ...upd };
}

function authHeader(method, url) {
  if (mode === 'oauth2') return `Bearer ${env.X_ACCESS_TOKEN}`;
  return authorizationHeader(method, url.href, {
    apiKey: env.X_API_KEY, apiSecret: env.X_API_SECRET, accessToken: env.X_OAUTH1_ACCESS_TOKEN, accessSecret: env.X_OAUTH1_ACCESS_SECRET,
  });
}

async function call(method, p, opts = {}, retried = false, legacyFields = false) {
  const { query, body, oauth1Denied } = opts;
  const url = new URL(API + p);
  for (const [k, v] of Object.entries(query ?? {})) {
    // The current docs name the parameter `post.fields`; older v2 deployments said `tweet.fields`.
    const key = legacyFields && k === 'post.fields' ? 'tweet.fields' : k;
    if (v !== undefined && v !== '') url.searchParams.set(key, v);
  }
  // URLSearchParams writes spaces as '+'; OAuth 1.0a signs them as %20, so send them that way.
  if (mode === 'oauth1') url.search = url.search.replace(/\+/g, '%20');
  const res = await fetch(url, {
    method,
    headers: { Authorization: authHeader(method, url), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401 && !retried && mode === 'oauth2') { await refresh(); return call(method, p, opts, true, legacyFields); }
  const json = await res.json().catch(() => ({}));
  if (res.status === 400 && query?.['post.fields'] && !legacyFields) return call(method, p, opts, retried, true);
  if (res.status === 429) fail('Rate limited', { resetAt: res.headers.get('x-rate-limit-reset') });
  if ((res.status === 401 || res.status === 403) && mode === 'oauth1' && oauth1Denied) fail(oauth1Denied, { status: res.status });
  if (res.status === 401 && mode === 'oauth1') fail(`HTTP 401 with OAuth 1.0a keys: they were regenerated or revoked, or are wrong. X retires OAuth 1.0a on ${OAUTH1_RETIREMENT}.`, { detail: json });
  if (!res.ok) fail(`HTTP ${res.status}`, { detail: json });
  return json;
}

// ---- args ------------------------------------------------------------------------------
const argv = process.argv.slice(2);
const cmd = argv.shift();
const flags = {};
const pos = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) {
    const k = argv[i].slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) flags[k] = true;
    else { flags[k] = next; i++; }
  } else pos.push(argv[i]);
}
const max = Math.min(Number(flags.max ?? 20), 100);
const POST_FIELDS = 'created_at,author_id,public_metrics,entities,referenced_tweets,conversation_id';
const USER_FIELDS = 'username,name,description,public_metrics,verified,created_at';

let meCache;
const me = async () => (meCache ??= (await call('GET', '/users/me')).data);
const out = (o) => console.log(JSON.stringify(o, null, 2));
const handle = (h) => String(h).replace(/^@/, '');
const resolveUser = async (h) => (await call('GET', `/users/by/username/${handle(h)}`, { query: { 'user.fields': USER_FIELDS } })).data;

// A write is a dry run unless --yes. The caller (Claude) must show the exact payload to the user first.
async function write(summary, exec) {
  if (!flags.yes) return out({ dryRun: true, wouldDo: summary, note: 'Nothing sent. Re-run with --yes only after the user confirmed this exact action.' });
  out({ done: true, did: summary, result: await exec() });
}

const needArg = (v, name) => v ?? fail(`Missing ${name}`);

// Which mode is active and where each variable comes from — names only, never values.
function authReport() {
  const file = readEnvFile(); const proc = fromProcess();
  const source = (k) => (proc[k] ? 'process env' : file[k] ? '~/.env' : 'missing');
  const report = { mode, envFile: { path: ENV_FILE, exists: fs.existsSync(ENV_FILE) } };
  if (mode === 'oauth1') {
    Object.assign(report, {
      variables: Object.fromEntries(OAUTH1_VARS.map((k) => [k, source(k)])),
      refresh: 'not needed (OAuth 1.0a keys do not expire)',
      unavailable: Object.keys(OAUTH2_ONLY),
      mayBeRefused: ['bookmarks'],
      retiresOn: OAUTH1_RETIREMENT,
    });
  } else {
    const partial = OAUTH1_VARS.filter((k) => env[k]);
    Object.assign(report, {
      variables: Object.fromEntries(OAUTH2_VARS.map((k) => [k, source(k)])),
      refresh: mode === 'oauth2' ? (refreshBlocker() ?? (env.X_REFRESH_TOKEN && env.X_CLIENT_ID ? 'possible' : 'impossible: X_REFRESH_TOKEN or X_CLIENT_ID missing')) : undefined,
      ...(partial.length ? { oauth1Incomplete: { missing: OAUTH1_VARS.filter((k) => !env[k]) } } : {}),
    });
    if (mode === 'none') report.hint = 'Set the 4 OAuth 1.0a variables, or run scripts/authorize.mjs — see references/setup.md.';
  }
  return report;
}

const commands = {
  async auth() {
    out(authReport());
    if (mode === 'none') process.exit(1);
  },
  // ---------- read ----------
  async me() { out((await call('GET', '/users/me', { query: { 'user.fields': USER_FIELDS } })).data); },
  async user() { out(await resolveUser(needArg(pos[0], '<username>'))); },
  async likes() {
    const u = flags.user ? await resolveUser(flags.user) : await me();
    out(await call('GET', `/users/${u.id}/liked_tweets`, { query: { max_results: Math.max(max, 5), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name', pagination_token: flags.next } }));
  },
  async bookmarks() {
    const u = await me();
    // The OpenAPI spec lists OAuth 1.0a for this GET, but the guides document OAuth 2.0 PKCE and
    // OAuth 1.0a permissions do not cover the bookmark.read scope: try it, explain a refusal.
    const oauth1Denied = 'Reading bookmarks was refused with the OAuth 1.0a keys: X serves bookmarks to OAuth 2.0 tokens (bookmark.read scope). Use the OAuth 2.0 mode for bookmarks.';
    out(await call('GET', `/users/${u.id}/bookmarks`, { query: { max_results: Math.max(max, 5), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name', pagination_token: flags.next }, oauth1Denied }));
  },
  async timeline() {
    const u = await me();
    out(await call('GET', `/users/${u.id}/timelines/reverse_chronological`, { query: { max_results: Math.max(max, 5), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name', pagination_token: flags.next } }));
  },
  async mentions() {
    const u = await me();
    out(await call('GET', `/users/${u.id}/mentions`, { query: { max_results: Math.max(max, 5), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name' } }));
  },
  async search() {
    out(await call('GET', '/tweets/search/recent', { query: { query: needArg(pos[0], '<query>'), max_results: Math.max(max, 10), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name' } }));
  },
  async following() {
    const u = flags.user ? await resolveUser(flags.user) : await me();
    out(await call('GET', `/users/${u.id}/following`, { query: { max_results: Math.min(Math.max(max, 1), 1000), 'user.fields': USER_FIELDS, pagination_token: flags.next } }));
  },
  async dms() {
    if (pos[0]) {
      const u = await resolveUser(pos[0]);
      out(await call('GET', `/dm_conversations/with/${u.id}/dm_events`, { query: { max_results: Math.max(max, 1), 'dm_event.fields': 'created_at,sender_id,text,dm_conversation_id' } }));
    } else {
      out(await call('GET', '/dm_events', { query: { max_results: Math.max(max, 1), 'dm_event.fields': 'created_at,sender_id,text,dm_conversation_id' } }));
    }
  },

  // ---------- write (dry run unless --yes) ----------
  async post() {
    const text = needArg(pos[0], '"<text>"');
    const body = { text, ...(flags.reply ? { reply: { in_reply_to_tweet_id: String(flags.reply) } } : {}) };
    await write({ action: flags.reply ? 'reply' : 'post', text, inReplyTo: flags.reply ?? null }, () => call('POST', '/tweets', { body }));
  },
  async like() {
    const id = needArg(pos[0], '<tweet_id>'); const u = await me();
    await write({ action: 'like', tweetId: id }, () => call('POST', `/users/${u.id}/likes`, { body: { tweet_id: id } }));
  },
  async unlike() {
    const id = needArg(pos[0], '<tweet_id>'); const u = await me();
    await write({ action: 'unlike', tweetId: id }, () => call('DELETE', `/users/${u.id}/likes/${id}`));
  },
  async follow() {
    const t = await resolveUser(needArg(pos[0], '<username>')); const u = await me();
    await write({ action: 'follow', username: t.username, name: t.name }, () => call('POST', `/users/${u.id}/following`, { body: { target_user_id: t.id } }));
  },
  async unfollow() {
    const t = await resolveUser(needArg(pos[0], '<username>')); const u = await me();
    await write({ action: 'unfollow', username: t.username }, () => call('DELETE', `/users/${u.id}/following/${t.id}`));
  },
  async bookmark() {
    const id = needArg(pos[0], '<tweet_id>'); const u = await me();
    await write({ action: 'bookmark', tweetId: id }, () => call('POST', `/users/${u.id}/bookmarks`, { body: { tweet_id: id } }));
  },
  async unbookmark() {
    const id = needArg(pos[0], '<tweet_id>'); const u = await me();
    await write({ action: 'unbookmark', tweetId: id }, () => call('DELETE', `/users/${u.id}/bookmarks/${id}`));
  },
  async dm() {
    // One recipient per call, on purpose: no batch sending.
    const t = await resolveUser(needArg(pos[0], '<username>')); const text = needArg(pos[1], '"<text>"');
    await write({ action: 'dm', to: t.username, name: t.name, text }, () => call('POST', `/dm_conversations/with/${t.id}/messages`, { body: { text } }));
  },
};

if (!cmd || !commands[cmd]) {
  console.error(`Usage: x.mjs <command> [args] [--max N] [--next TOKEN] [--user NAME] [--yes]
Auth : auth (which mode is active; prints no secret)
Read : me | user <u> | likes [--user u] | bookmarks | timeline | mentions | search "<q>" | following [--user u] | dms [<u>]
Write: post "<text>" [--reply <tweet_id>] | like|unlike|bookmark|unbookmark <tweet_id> | follow|unfollow <u> | dm <u> "<text>"
Writes are a dry run unless --yes is given.`);
  process.exit(cmd ? 1 : 0);
}
if (cmd !== 'auth') {
  if (mode === 'none') fail('No X credentials: set X_API_KEY, X_API_SECRET, X_OAUTH1_ACCESS_TOKEN and X_OAUTH1_ACCESS_SECRET (OAuth 1.0a), or run scripts/authorize.mjs (OAuth 2.0). See references/setup.md.');
  if (mode === 'oauth1' && OAUTH2_ONLY[cmd]) fail(`\`${cmd}\` needs OAuth 2.0: X accepts only OAuth 2.0 user tokens on ${OAUTH2_ONLY[cmd]}. Nothing was sent. Use the OAuth 2.0 mode for this command.`);
}
await commands[cmd]();
