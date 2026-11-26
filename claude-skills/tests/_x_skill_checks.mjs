// _x_skill_checks.mjs — assertions for the x skill, run by test_x_skill.sh. Offline: the CLI is
// spawned with _x_fetch_mock.mjs preloaded, so no request ever leaves the machine. All keys
// below are fake or the published docs.x.com example values.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = path.join(here, '../skills/x/scripts');
const CLI = path.join(scripts, 'x.mjs');
const MOCK = path.join(here, '_x_fetch_mock.mjs');
const { percentEncode, signatureBaseString, sign, authorizationHeader } = await import(path.join(scripts, 'oauth1.mjs'));

let failed = 0;
const check = (name, ok, info = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !info ? '' : `\n      ${info}`}`);
  if (!ok) failed++;
};

// ---- 1. signature: docs.x.com "Creating a signature" -----------------------------------
// https://docs.x.com/fundamentals/authentication/oauth-1-0a/creating-a-signature
const DOC = {
  apiKey: 'xvz1evFS4wEEPTGEFPHBog',
  apiSecret: 'kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw',
  accessToken: '370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb',
  accessSecret: 'LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE',
  nonce: 'kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg',
  timestamp: 1318622958,
  // form-urlencoded body parameter of the example request, so it is signed
  status: 'Hello Ladies + Gentlemen, a signed OAuth request!',
};
const docParams = {
  status: DOC.status, oauth_consumer_key: DOC.apiKey, oauth_nonce: DOC.nonce, oauth_signature_method: 'HMAC-SHA1',
  oauth_timestamp: String(DOC.timestamp), oauth_token: DOC.accessToken, oauth_version: '1.0',
};
const docUrl = 'https://api.x.com/1.1/statuses/update.json?include_entities=true';
const docBase = signatureBaseString('POST', docUrl, docParams);
check('signature base string matches the docs', docBase === 'POST&https%3A%2F%2Fapi.x.com%2F1.1%2Fstatuses%2Fupdate.json&include_entities%3Dtrue%26oauth_consumer_key%3Dxvz1evFS4wEEPTGEFPHBog%26oauth_nonce%3DkYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg%26oauth_signature_method%3DHMAC-SHA1%26oauth_timestamp%3D1318622958%26oauth_token%3D370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb%26oauth_version%3D1.0%26status%3DHello%2520Ladies%2520%252B%2520Gentlemen%252C%2520a%2520signed%2520OAuth%2520request%2521', docBase);
check('signature matches the docs (Ls93hJiZbQ3akF3HF3x1Bz8/zU4=)', sign(docBase, DOC.apiSecret, DOC.accessSecret) === 'Ls93hJiZbQ3akF3HF3x1Bz8/zU4=');
check('signature matches the historical api.twitter.com example (hCtSmYh+iHYCEqBWrE7C7hYmtUk=)',
  sign(signatureBaseString('POST', docUrl.replace('api.x.com', 'api.twitter.com'), docParams), DOC.apiSecret, DOC.accessSecret) === 'hCtSmYh+iHYCEqBWrE7C7hYmtUk=');
const docHeader = authorizationHeader('POST', docUrl, DOC, { extra: { status: DOC.status }, nonce: DOC.nonce, timestamp: DOC.timestamp });
check('Authorization header carries the encoded doc signature', docHeader.startsWith('OAuth ') && docHeader.includes('oauth_signature="Ls93hJiZbQ3akF3HF3x1Bz8%2FzU4%3D"'), docHeader);
check('percent-encoding is RFC 3986 strict', percentEncode("a b+c!*'()~") === 'a%20b%2Bc%21%2A%27%28%29~');

// ---- 2. CLI with mocked fetch --------------------------------------------------------
const OAUTH1_ENV = { X_API_KEY: 'fake-api-key', X_API_SECRET: 'fake-api-secret', X_OAUTH1_ACCESS_TOKEN: 'fake-oauth1-token', X_OAUTH1_ACCESS_SECRET: 'fake-oauth1-secret' };
const FAKE_SECRETS = ['fake-api-secret', 'fake-oauth1-secret', 'fake-refresh-file', 'fake-refresh-env', 'fake-access-file', 'fake-access-env'];

const homes = [];
function run(args, { env = {}, envFile, responses = [], readOnlyHome = false } = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'x-skill-test-'));
  homes.push(home);
  if (envFile !== undefined) fs.writeFileSync(path.join(home, '.env'), envFile, { mode: readOnlyHome ? 0o400 : 0o600 });
  const log = path.join(os.tmpdir(), `${path.basename(home)}.log`);
  homes.push(log);
  fs.writeFileSync(log, '');
  if (readOnlyHome) fs.chmodSync(home, 0o500);
  // Drop any real X_* variable of the caller so the test never sees real credentials.
  const base = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('X_')));
  const r = spawnSync(process.execPath, ['--import', MOCK, CLI, ...args], {
    env: { ...base, ...env, HOME: home, XMOCK_LOG: log, XMOCK_RESPONSES: JSON.stringify(responses) }, encoding: 'utf8',
  });
  const requests = fs.readFileSync(log, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const envAfter = fs.existsSync(path.join(home, '.env')) ? fs.readFileSync(path.join(home, '.env'), 'utf8') : null;
  if (readOnlyHome) fs.chmodSync(home, 0o700);
  return { ...r, requests, home, envAfter };
}
const json = (s) => { try { return JSON.parse(s); } catch { return null; } };
const ME = { status: 200, json: { data: { id: '42', username: 'someone', name: 'Someone' } } };
const FILE_ENV = 'X_CLIENT_ID=fake-client-id\nX_ACCESS_TOKEN=fake-access-file\nX_REFRESH_TOKEN=fake-refresh-file\n';

// OAuth 2.0 keeps reading ~/.env
let r = run(['auth'], { envFile: FILE_ENV });
let a = json(r.stdout);
check('auth: OAuth 2.0 read from ~/.env', r.status === 0 && a?.mode === 'oauth2' && a.variables.X_ACCESS_TOKEN === '~/.env' && a.refresh === 'possible', r.stdout + r.stderr);
check('auth prints no secret', !FAKE_SECRETS.some((s) => r.stdout.includes(s)));

r = run(['me'], { envFile: FILE_ENV, responses: [ME] });
check('OAuth 2.0: bearer token taken from ~/.env', r.status === 0 && r.requests.length === 1 && r.requests[0].authorization === 'Bearer fake-access-file', JSON.stringify(r.requests) + r.stderr);

r = run(['me'], { envFile: FILE_ENV, env: { X_ACCESS_TOKEN: 'fake-access-env' }, responses: [ME] });
check('process env wins over ~/.env', r.status === 0 && r.requests[0]?.authorization === 'Bearer fake-access-env', JSON.stringify(r.requests));

r = run(['me'], { envFile: FILE_ENV, responses: [{ status: 401 }, { status: 200, json: { access_token: 'new-access', refresh_token: 'new-refresh' } }, ME] });
check('OAuth 2.0: 401 -> refresh -> retry with the new token',
  r.status === 0 && r.requests.length === 3 && r.requests[1].url.endsWith('/oauth2/token') && r.requests[2].authorization === 'Bearer new-access', JSON.stringify(r.requests) + r.stderr);
check('OAuth 2.0: rotated tokens saved to ~/.env (mode 600)',
  r.envAfter?.includes('X_ACCESS_TOKEN=new-access') && r.envAfter.includes('X_REFRESH_TOKEN=new-refresh') && r.envAfter.includes('X_CLIENT_ID=fake-client-id')
  && (fs.statSync(path.join(r.home, '.env')).mode & 0o777) === 0o600, r.envAfter);

r = run(['me'], { env: { X_CLIENT_ID: 'fake-client-id', X_ACCESS_TOKEN: 'fake-access-env', X_REFRESH_TOKEN: 'fake-refresh-env' }, responses: [{ status: 401 }] });
check('OAuth 2.0 from read-only env: no refresh attempted, clear message',
  r.status === 1 && r.requests.length === 1 && /cannot be refreshed: X_REFRESH_TOKEN comes from the process environment/.test(r.stderr), r.stderr);

if (process.getuid?.() !== 0) { // root can write anyway
  r = run(['me'], { envFile: FILE_ENV, responses: [{ status: 401 }], readOnlyHome: true });
  check('OAuth 2.0 with unwritable ~/.env: no refresh attempted, clear message',
    r.status === 1 && r.requests.length === 1 && /cannot be refreshed: ~\/\.env is not writable/.test(r.stderr), r.stderr);
}

// OAuth 1.0a
r = run(['auth'], { env: OAUTH1_ENV });
a = json(r.stdout);
check('auth: OAuth 1.0a from env, no ~/.env needed', r.status === 0 && a?.mode === 'oauth1' && a.envFile.exists === false && a.variables.X_API_SECRET === 'process env', r.stdout + r.stderr);
check('auth (OAuth 1.0a) prints no secret', !FAKE_SECRETS.some((s) => r.stdout.includes(s)));

r = run(['auth'], { envFile: FILE_ENV, env: { X_API_KEY: 'k', X_API_SECRET: 's' } });
a = json(r.stdout);
check('incomplete OAuth 1.0a set falls back to OAuth 2.0 and says what is missing',
  a?.mode === 'oauth2' && a.oauth1Incomplete?.missing.join() === 'X_OAUTH1_ACCESS_TOKEN,X_OAUTH1_ACCESS_SECRET', r.stdout);

// Recompute the signature of a logged request from its own nonce/timestamp.
function verifyOAuth1(req, extra = {}) {
  const h = req.authorization ?? '';
  if (!h.startsWith('OAuth ')) return false;
  const p = Object.fromEntries([...h.slice(6).matchAll(/(\w+)="([^"]*)"/g)].map(([, k, v]) => [k, decodeURIComponent(v)]));
  const { oauth_signature: got, ...oauth } = p;
  const want = sign(signatureBaseString(req.method, req.url, { ...oauth, ...extra }), OAUTH1_ENV.X_API_SECRET, OAUTH1_ENV.X_OAUTH1_ACCESS_SECRET);
  return got === want && oauth.oauth_consumer_key === OAUTH1_ENV.X_API_KEY && oauth.oauth_token === OAUTH1_ENV.X_OAUTH1_ACCESS_TOKEN;
}

r = run(['search', 'from:someone hello world', '--max', '10'], { env: OAUTH1_ENV, responses: [{ status: 200, json: { data: [] } }] });
check('OAuth 1.0a: GET signed with query params, spaces sent as %20',
  r.status === 0 && r.requests.length === 1 && verifyOAuth1(r.requests[0]) && r.requests[0].url.includes('from%3Asomeone%20hello%20world') && !r.requests[0].url.includes('+'), JSON.stringify(r.requests) + r.stderr);

r = run(['post', 'hello from a test', '--yes'], { env: OAUTH1_ENV, responses: [{ status: 201, json: { data: { id: '1' } } }] });
check('OAuth 1.0a: JSON body excluded from the signature',
  r.status === 0 && r.requests.length === 1 && r.requests[0].body === '{"text":"hello from a test"}' && verifyOAuth1(r.requests[0]) && !verifyOAuth1(r.requests[0], { text: 'hello from a test' }), JSON.stringify(r.requests) + r.stderr);

for (const c of [['bookmark', '123'], ['unbookmark', '123'], ['bookmark', '123', '--yes']]) {
  r = run(c, { env: OAUTH1_ENV });
  check(`OAuth 1.0a: \`${c.join(' ')}\` refused up front, nothing sent`, r.status === 1 && r.requests.length === 0 && /needs OAuth 2.0/.test(r.stderr), r.stderr);
}

r = run(['bookmarks'], { env: OAUTH1_ENV, responses: [ME, { status: 403, json: { title: 'Forbidden' } }] });
check('OAuth 1.0a: refused bookmarks read gives an explicit message', r.status === 1 && /X serves bookmarks to OAuth 2.0 tokens/.test(r.stderr), r.stderr);

r = run(['me'], { env: OAUTH1_ENV, responses: [{ status: 401 }] });
check('OAuth 1.0a: 401 -> no refresh, clear message', r.status === 1 && r.requests.length === 1 && /OAuth 1.0a keys/.test(r.stderr), JSON.stringify(r.requests) + r.stderr);

r = run(['me'], {});
check('no credentials at all: clear message, nothing sent', r.status === 1 && r.requests.length === 0 && /No X credentials/.test(r.stderr), r.stderr);

for (const h of homes) fs.rmSync(h, { recursive: true, force: true });
console.log(failed ? `\n${failed} check(s) failed` : '\nAll x skill checks passed');
process.exit(failed ? 1 : 0);
