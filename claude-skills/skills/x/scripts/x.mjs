#!/usr/bin/env node
// x.mjs — small CLI over the official X API v2. No dependencies.
// Auth: X_ACCESS_TOKEN / X_REFRESH_TOKEN / X_CLIENT_ID in ~/.env (see authorize.mjs).
// READ commands run directly. WRITE commands are a DRY RUN unless --yes is passed.
// Output is JSON on stdout. Tokens are never printed.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ENV_FILE = path.join(os.homedir(), '.env');
const API = 'https://api.x.com/2';

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
  const lines = fs.readFileSync(ENV_FILE, 'utf8').split('\n');
  for (const [k, v] of Object.entries(updates)) {
    const i = lines.findIndex((l) => new RegExp(`^\\s*(export\\s+)?${k}=`).test(l));
    if (i >= 0) lines[i] = `${k}=${v}`;
    else lines.push(`${k}=${v}`);
  }
  fs.writeFileSync(ENV_FILE, lines.join('\n').replace(/\n*$/, '\n'), { mode: 0o600 });
}

let env = readEnv();
if (!env.X_ACCESS_TOKEN) fail('No X_ACCESS_TOKEN in ~/.env. Run scripts/authorize.mjs first.');

function fail(msg, extra) {
  console.error(JSON.stringify({ error: msg, ...extra }));
  process.exit(1);
}

async function refresh() {
  if (!env.X_REFRESH_TOKEN || !env.X_CLIENT_ID) fail('Token expired and no refresh token — run authorize.mjs again.');
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
  writeEnv(upd);
  env = readEnv();
}

async function call(method, p, { query, body } = {}, retried = false, legacyFields = false) {
  const url = new URL(API + p);
  for (const [k, v] of Object.entries(query ?? {})) {
    // The current docs name the parameter `post.fields`; older v2 deployments said `tweet.fields`.
    const key = legacyFields && k === 'post.fields' ? 'tweet.fields' : k;
    if (v !== undefined && v !== '') url.searchParams.set(key, v);
  }
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${env.X_ACCESS_TOKEN}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401 && !retried) { await refresh(); return call(method, p, { query, body }, true, legacyFields); }
  const json = await res.json().catch(() => ({}));
  if (res.status === 400 && query?.['post.fields'] && !legacyFields) return call(method, p, { query, body }, retried, true);
  if (res.status === 429) fail('Rate limited', { resetAt: res.headers.get('x-rate-limit-reset') });
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

const commands = {
  // ---------- read ----------
  async me() { out((await call('GET', '/users/me', { query: { 'user.fields': USER_FIELDS } })).data); },
  async user() { out(await resolveUser(needArg(pos[0], '<username>'))); },
  async likes() {
    const u = flags.user ? await resolveUser(flags.user) : await me();
    out(await call('GET', `/users/${u.id}/liked_tweets`, { query: { max_results: Math.max(max, 5), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name', pagination_token: flags.next } }));
  },
  async bookmarks() {
    const u = await me();
    out(await call('GET', `/users/${u.id}/bookmarks`, { query: { max_results: Math.max(max, 5), 'post.fields': POST_FIELDS, expansions: 'author_id', 'user.fields': 'username,name', pagination_token: flags.next } }));
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
Read : me | user <u> | likes [--user u] | bookmarks | timeline | mentions | search "<q>" | following [--user u] | dms [<u>]
Write: post "<text>" [--reply <tweet_id>] | like|unlike|bookmark|unbookmark <tweet_id> | follow|unfollow <u> | dm <u> "<text>"
Writes are a dry run unless --yes is given.`);
  process.exit(cmd ? 1 : 0);
}
await commands[cmd]();
