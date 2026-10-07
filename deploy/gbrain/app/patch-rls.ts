/**
 * Patch gbrain's Supabase-specific RLS privilege gates for managed Postgres
 * (Clever Cloud). Runs at boot, before `gbrain apply-migrations`.
 *
 * Why this is safe here:
 * - gbrain's RLS posture exists because Supabase exposes `public` via
 *   PostgREST to a client-side anon key. Clever Cloud Postgres has no
 *   PostgREST and no anon key — there is nothing for RLS to protect.
 * - Our single role OWNS every table it creates, and Postgres table owners
 *   bypass RLS policies (absent FORCE ROW LEVEL SECURITY). Forcing the
 *   check to true lets the migrations enable RLS everywhere without locking
 *   gbrain out — the same effective posture as Supabase's BYPASSRLS
 *   service role.
 * - CREATE EVENT TRIGGER requires real superuser and cannot work on managed
 *   Postgres; it is wrapped in an insufficient_privilege catch instead.
 * - The v35 all-public-tables RLS backfill must skip tables the role does
 *   not own: Clever Cloud ships PostGIS, whose `spatial_ref_sys` lives in
 *   `public` but is owned by the admin role ("must be owner of table").
 *
 * Each replacement is independently idempotent, so a build-cached, partially
 * patched node_modules self-heals on the next boot. Fails loudly if gbrain's
 * source drifts from the patterns.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const file = process.argv[2] ?? './node_modules/gbrain/src/core/migrate.ts';
const MARKER = 'patched-for-managed-postgres';

let src = readFileSync(file, 'utf8');
let applied = 0;
let skipped = 0;

// patch(name, pattern, replacement, alreadyPatchedProbe)
function patch(name: string, pattern: string, replacement: string, probe: string) {
  if (src.includes(probe)) {
    console.error(`[patch-rls] ${name}: already patched`);
    skipped++;
    return;
  }
  const count = src.split(pattern).length - 1;
  if (count === 0) {
    throw new Error(`[patch-rls] ${name}: pattern not found — gbrain source drifted, review the patch`);
  }
  src = src.replaceAll(pattern, replacement);
  console.error(`[patch-rls] ${name}: ${count} occurrence(s) patched`);
  applied += count;
}

// 1. Force the BYPASSRLS privilege check to true (10 occurrences upstream).
patch(
  'privilege-check',
  "SELECT EXISTS (SELECT 1 FROM pg_roles pr WHERE pg_has_role(current_user, pr.oid, 'USAGE') AND (pr.rolbypassrls OR pr.rolsuper)) INTO has_bypass;",
  `has_bypass := true; -- ${MARKER}: owner bypasses RLS; no PostgREST/anon key on this platform`,
  `has_bypass := true; -- ${MARKER}`,
);

// 2. Guard the superuser-only event trigger (v35).
patch(
  'event-trigger',
  `DROP EVENT TRIGGER IF EXISTS auto_rls_on_create_table;
        CREATE EVENT TRIGGER auto_rls_on_create_table
          ON ddl_command_end
          WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
          EXECUTE FUNCTION auto_enable_rls();`,
  `DO $managed_pg$ BEGIN
          DROP EVENT TRIGGER IF EXISTS auto_rls_on_create_table;
          CREATE EVENT TRIGGER auto_rls_on_create_table
            ON ddl_command_end
            WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
            EXECUTE FUNCTION auto_enable_rls();
        EXCEPTION WHEN insufficient_privilege THEN
          RAISE NOTICE 'skipping auto_rls event trigger (requires superuser; managed Postgres)';
        END $managed_pg$;`,
  'DO $managed_pg$ BEGIN',
);

// 3. v35 backfill: only touch tables the current role owns (PostGIS etc.).
patch(
  'backfill-ownership',
  'AND c.relrowsecurity = false',
  `AND c.relrowsecurity = false
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'USAGE') -- ${MARKER}: skip tables we don't own (PostGIS spatial_ref_sys)`,
  "pg_has_role(current_user, c.relowner, 'USAGE')",
);

writeFileSync(file, src);
console.error(`[patch-rls] done (${applied} replacements applied, ${skipped} already in place)`);
