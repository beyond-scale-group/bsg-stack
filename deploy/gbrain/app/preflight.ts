/**
 * Boot preflight for gbrain on Clever Cloud. Idempotent; runs on every boot.
 *
 * 1. Writes ~/.gbrain/config.json — the `storage` block has no env-var
 *    mapping in gbrain, and $HOME is ephemeral on Clever Cloud, so the file
 *    is rebuilt from the Cellar add-on's env vars each time.
 * 2. Ensures the pgvector extension exists (activated automatically on
 *    Clever Cloud Postgres; CREATE EXTENSION is still required once).
 * 3. Ensures the Cellar bucket for attachments exists.
 */
import postgres from 'postgres';
import { S3Client, CreateBucketCommand, HeadBucketCommand } from '@aws-sdk/client-s3';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

function need(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`[preflight] missing env var ${name}`);
  return v;
}

const bucket = process.env.GBRAIN_CELLAR_BUCKET || 'gbrain-media';
const endpoint = `https://${need('CELLAR_ADDON_HOST')}`;
const accessKeyId = need('CELLAR_ADDON_KEY_ID');
const secretAccessKey = need('CELLAR_ADDON_KEY_SECRET');

// 1. file-plane config
const cfgDir = join(homedir(), '.gbrain');
mkdirSync(cfgDir, { recursive: true });
writeFileSync(
  join(cfgDir, 'config.json'),
  JSON.stringify(
    {
      engine: 'postgres',
      storage: { backend: 's3', bucket, endpoint, accessKeyId, secretAccessKey },
    },
    null,
    2,
  ),
);
console.error('[preflight] wrote ~/.gbrain/config.json');

// 2. pgvector
const sql = postgres(need('DATABASE_URL'), { max: 1 });
try {
  await sql`CREATE EXTENSION IF NOT EXISTS vector`;
  console.error('[preflight] pgvector extension present');
} finally {
  await sql.end();
}

// 3. Cellar bucket
const s3 = new S3Client({
  region: 'us-east-1',
  endpoint,
  forcePathStyle: true,
  credentials: { accessKeyId, secretAccessKey },
});
try {
  await s3.send(new HeadBucketCommand({ Bucket: bucket }));
  console.error(`[preflight] Cellar bucket '${bucket}' exists`);
} catch {
  await s3.send(new CreateBucketCommand({ Bucket: bucket }));
  console.error(`[preflight] created Cellar bucket '${bucket}'`);
}
