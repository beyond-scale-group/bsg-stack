# Deploy gbrain on Clever Cloud

Automated deployment of [gbrain](https://github.com/garrytan/gbrain) — Garry
Tan's Postgres-native personal knowledge brain — onto Clever Cloud, using:

| gbrain need | Clever Cloud piece |
|---|---|
| Bun + TypeScript runtime | Node app with `CC_NODE_BUILD_TOOL=bun` (native Bun support) |
| Postgres + pgvector | `postgresql-addon` (pgvector is activated automatically; the boot preflight runs `CREATE EXTENSION IF NOT EXISTS vector`) |
| S3 storage for big files / attachments | `cellar-addon` — gbrain's S3 backend supports custom endpoints with path-style addressing, which is exactly Cellar's shape |
| Persistent disk for the brain repo | `fs-bucket` mounted at `/data` via `CC_FS_BUCKET` |
| Job queue (Minions) | Postgres-native — no Redis add-on needed |

```
┌─────────────────────────── Clever Cloud ───────────────────────────┐
│  Node app (Bun runtime, pinned to 1 instance)                      │
│  └─ gbrain serve --http --port 8080 --bind 0.0.0.0                 │
│       --public-url https://<app>.cleverapps.io                     │
│     ├── Postgres add-on ── pgvector, pages, embeddings, job queue  │
│     ├── Cellar add-on ──── S3 bucket for attachments / media       │
│     └── FS Bucket add-on ─ /data: persistent brain git repo        │
└────────────────────────────────────────────────────────────────────┘
```

## Layout

```
deploy/gbrain/
├── README.md            # this file
├── install.sh           # provisions app + add-ons, sets env, deploys, verifies
├── gbrain.env.example   # operator-supplied secrets (copy to gbrain.env, gitignored)
└── app/                 # the wrapper app that gets pushed to Clever Cloud
    ├── package.json     # depends on github:garrytan/gbrain
    ├── boot.sh          # boot sequence: config → preflight → migrations → serve
    └── preflight.ts     # writes ~/.gbrain/config.json, ensures pgvector + Cellar bucket
```

The wrapper app is copied to a standalone git repo outside this repository
(`~/gbrain-clever-deploy` by default) because `clever deploy` pushes a git
repo — bsg-stack itself is never pushed to Clever Cloud.

## Prerequisites

- `clever` CLI ≥ 4.11 installed and logged in (`clever profile`)
- An embedding provider API key: ZeroEntropy (gbrain's default) or OpenAI.
  Without one, only keyword search works — no vector search.

## Usage

```bash
cd deploy/gbrain
cp gbrain.env.example gbrain.env   # fill in your API keys
./install.sh                       # idempotent — re-run safely after any failure
```

Options (env vars or flags):

```bash
./install.sh --org my-org --name gbrain --region par
# or: APP_NAME=gbrain REGION=par ORG=orga_xxx PG_PLAN=xs_sml ./install.sh
```

`install.sh` runs these phases, each idempotent:

1. **Workdir** — copies `app/` to `$GBRAIN_DEPLOY_DIR` (default
   `~/gbrain-clever-deploy`), commits it as its own git repo
2. **App** — `clever create --type node` (skipped when already linked)
3. **Add-ons** — creates + links `postgresql-addon`, `cellar-addon`,
   `fs-bucket` (skipped when already linked)
4. **Env** — wires `CC_NODE_BUILD_TOOL=bun`, `CC_FS_BUCKET=/data:<host>`,
   `GBRAIN_PUBLIC_URL`, trust-proxy/CORS, a generated admin bootstrap
   token, and your keys from `gbrain.env`
5. **Scale** — pins the scaler to exactly 1 instance (gbrain's server
   assumes a single writer; FS Bucket is NFS-backed so this also avoids
   write contention)
6. **Deploy** — `clever deploy`, then polls `/health` until green

## What happens at boot (`app/boot.sh`)

1. `DATABASE_URL` is exported from `POSTGRESQL_ADDON_URI` — gbrain infers
   `engine: postgres` from it
2. `preflight.ts` writes `~/.gbrain/config.json` (the `storage` block has no
   env-var mapping, and `$HOME` is ephemeral, so it is rebuilt every boot from
   the Cellar add-on's env vars), runs `CREATE EXTENSION IF NOT EXISTS vector`,
   and creates the Cellar bucket if missing
3. The brain repo is initialised at `$APP_HOME/data/brain` (the FS Bucket
   mount — `CC_FS_BUCKET` paths are relative to the app folder — survives
   redeploys) and registered as the `default` source
4. `gbrain apply-migrations --yes` — Bun blocks gbrain's postinstall hook on
   install ([gbrain #218](https://github.com/garrytan/gbrain/issues/218)), so
   migrations run explicitly here
5. `gbrain export --restore-only` repopulates any `db_only` files missing
   from disk (the documented container-restart recovery path)
6. `gbrain serve --http --port 8080 --bind 0.0.0.0 --public-url $GBRAIN_PUBLIC_URL`

## After the install

Register your first OAuth client and connect Claude Code:

```bash
clever ssh --alias gbrain
# inside the instance:
cd /home/bas/app_* && ./node_modules/.bin/gbrain auth register-client me \
  --grant-types client_credentials --scopes read,write,admin
exit

# locally:
gbrain connect https://<app>.cleverapps.io/mcp --token <token>
```

Admin dashboard: `https://<app>.cleverapps.io/admin` — log in with the
`GBRAIN_ADMIN_BOOTSTRAP_TOKEN` printed by `install.sh`.

## Costs & caveats

- **~€25–35/month**: Postgres XS is the dominant cost; app XS, Cellar and
  FS Bucket are per-GB cents at this scale.
- **Search mode**: gbrain's cost spread between `conservative` and `tokenmax`
  is ~25× per query. The installer defaults to `balanced`
  (`GBRAIN_SEARCH_MODE` in `gbrain.env` to override).
- **Single instance only** — do not scale horizontally.
- Secrets live in Clever Cloud env vars and `gbrain.env` (gitignored) —
  nothing sensitive is committed here or pushed in the wrapper repo.
