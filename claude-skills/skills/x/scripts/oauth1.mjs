// oauth1.mjs — OAuth 1.0a user-context signing (HMAC-SHA1) for the X API. No dependencies.
// Follows docs.x.com "Creating a signature": oauth_* params + query params go into the base
// string; a JSON body does not (only form-urlencoded bodies are signed — pass them as `extra`).
import crypto from 'node:crypto';

// RFC 3986 strict: encodeURIComponent leaves ! ' ( ) * unescaped.
export const percentEncode = (s) =>
  encodeURIComponent(String(s)).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());

export function signatureBaseString(method, url, params) {
  const u = new URL(url);
  const all = [...u.searchParams.entries(), ...Object.entries(params)];
  const paramString = all
    .map(([k, v]) => [percentEncode(k), percentEncode(v)])
    .sort(([ak, av], [bk, bv]) => (ak < bk ? -1 : ak > bk ? 1 : av < bv ? -1 : av > bv ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join('&');
  return [method.toUpperCase(), percentEncode(u.origin + u.pathname), percentEncode(paramString)].join('&');
}

export function sign(baseString, consumerSecret, tokenSecret) {
  const key = `${percentEncode(consumerSecret)}&${percentEncode(tokenSecret)}`;
  return crypto.createHmac('sha1', key).update(baseString).digest('base64');
}

// Returns the value of the Authorization header. `nonce` / `timestamp` are only fixed in tests.
export function authorizationHeader(method, url, creds, { extra = {}, nonce, timestamp } = {}) {
  const oauth = {
    oauth_consumer_key: creds.apiKey,
    oauth_nonce: nonce ?? crypto.randomBytes(16).toString('hex'),
    oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: String(timestamp ?? Math.floor(Date.now() / 1000)),
    oauth_token: creds.accessToken,
    oauth_version: '1.0',
  };
  oauth.oauth_signature = sign(signatureBaseString(method, url, { ...oauth, ...extra }), creds.apiSecret, creds.accessSecret);
  return 'OAuth ' + Object.entries(oauth).map(([k, v]) => `${percentEncode(k)}="${percentEncode(v)}"`).join(', ');
}
