// _x_fetch_mock.mjs — preloaded with `node --import` by test_x_skill.sh. Replaces fetch so the
// x skill CLI never reaches the network: answers come from XMOCK_RESPONSES (JSON array, used in
// order) and every request is appended to XMOCK_LOG as one JSON line.
import fs from 'node:fs';

const queue = JSON.parse(process.env.XMOCK_RESPONSES ?? '[]');
globalThis.fetch = async (input, init = {}) => {
  const url = String(input);
  const headers = init.headers ?? {};
  const body = init.body === undefined ? null : String(init.body);
  fs.appendFileSync(process.env.XMOCK_LOG, JSON.stringify({ method: init.method ?? 'GET', url, authorization: headers.Authorization ?? null, body }) + '\n');
  const next = queue.shift();
  if (!next) throw new Error(`unexpected request: ${init.method ?? 'GET'} ${url}`);
  return new Response(JSON.stringify(next.json ?? {}), { status: next.status ?? 200, headers: { 'content-type': 'application/json' } });
};
