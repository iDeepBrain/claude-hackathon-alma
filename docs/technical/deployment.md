# Deployment — Alma on Google Cloud

Alma runs on **Google Cloud Run** with a custom domain at [`alma-bot.com`](https://alma-bot.com). Persistent state lives in managed services outside of Cloud Run: Postgres at Supabase (with `pgvector` for semantic search), Redis at Upstash (TLS), and Telegram Bot API for push messaging. This page documents the production-grade architecture, the deploy scripts, secret handling, and how a custom domain is mapped via Cloud Run's domain mapping (not Cloudflare proxy).

---

## Live URL

- 🌸 **Public**: [https://alma-bot.com](https://alma-bot.com)
- ⚙️ **Cloud Run direct (dev)**: `https://alma-web-dev-<project-hash>-uc.a.run.app/`

---

## Service Topology in Cloud Run

```
                 alma-bot.com (Cloudflare DNS, DNS-only)
                           │
                           ▼
              Google Cloud Frontend (SNI routing)
                           │
                           ▼
        ┌──────────────────────────────────────────┐
        │  alma-web (Cloud Run, public)            │
        │    nginx:1.25-alpine                     │
        │    /api/*  →  proxy_pass alma-agent      │
        └──────────────────────────────────────────┘
                  │ (nginx proxy with SNI override)
                  ▼
        ┌──────────────────────────────────────────┐
        │  alma-agent (Cloud Run, public)          │
        │    FastAPI + AlmaChain + LLM chain       │
        │    /api/v1/chat                          │
        │    /api/v1/memory/{user_id}              │
        │    /cron/proactive/{slot}  ← X-Cloud-... │
        └──────────────────────────────────────────┘
                  │            │              │
                  ▼            ▼              ▼
            alma-mcp       Upstash         Anthropic /
          (Cloud Run,       Redis           Gemini API
           public)          (TLS)
                  │
                  ▼
            Supabase Postgres (Session Pooler)
              + pgvector (HNSW)


        ┌──────────────────────────────────────────┐
        │  alma-telegram-bot (Cloud Run, private)  │
        │    polls api.telegram.org                │
        │    POSTs to alma-agent on each message   │
        └──────────────────────────────────────────┘

        ┌──────────────────────────────────────────┐
        │  Cloud Scheduler (3 jobs, Lima time)     │
        │    08:30  alma-proactive-breakfast       │
        │    13:30  alma-proactive-lunch           │
        │    19:30  alma-proactive-dinner          │
        │      → POST agent /cron/proactive/{slot} │
        │        with X-Cloud-Scheduler-Token      │
        └──────────────────────────────────────────┘
```

### Why this shape

- **MCP and Postgres outside the container**: the container can scale to zero or restart without losing memory. State lives in Supabase (relational + pgvector for embeddings).
- **Redis is external (Upstash)**: Cloud Run can have multiple replicas of the agent — they all share one Redis for sessions and the semantic cache.
- **Telegram bot is a separate service**: it runs polling continuously (`min-instances=1, max-instances=1` to satisfy Telegram's "one polling client per token" rule).
- **Cloud Scheduler instead of in-process APScheduler**: APScheduler in a multi-replica Cloud Run service would fire each job N times. Cloud Scheduler fires once and HTTP-POSTs to the agent — exactly once per slot.

---

## Project layout (the 8 repos)

| Repo | Service in Cloud Run | Build context |
|------|----------------------|---------------|
| `claude-hackathon-mcp` | `alma-mcp` | Dockerfile, `alembic upgrade head` runs at container start |
| `claude-hackathon-agent` | `alma-agent` | Dockerfile, FastAPI + LangChain |
| `claude-hackathon-telegram` | `alma-telegram-bot` | Dockerfile, polling worker + stdlib HTTP health server |
| `claude-hackathon-web` | `alma-web` | Dockerfile, nginx:1.25-alpine with `nginx.template.conf` (envsubst) |
| `claude-hackathon-infra` | (local only) | docker-compose.yml with `postgres` (pgvector/pg16), redis, agent, mcp, web, telegram-bot |

---

## Secrets in Google Secret Manager

All sensitive values live in **GCP Secret Manager** and are mounted into Cloud Run as env vars at runtime via `--set-secrets`. None of these are baked into the Docker images.

| Secret name | Used by | Description |
|-------------|---------|-------------|
| `ANTHROPIC_API_KEY` | alma-agent | Claude API key (primary LLM) |
| `GOOGLE_API_KEY` | alma-agent | Gemini API key (fallback LLM) |
| `TELEGRAM_BOT_TOKEN` | alma-agent, alma-telegram-bot | BotFather token |
| `ALMA_DATABASE_URL` | alma-mcp, alma-agent | `postgresql+asyncpg://...@aws-1-us-east-1.pooler.supabase.com:5432/postgres` (Session Pooler — IPv4) |
| `ALMA_REDIS_URL` | alma-agent, alma-telegram-bot | `rediss://default:...@<host>.upstash.io:6379` |
| `ALMA_CRON_TOKEN` | alma-agent | Random 32-char shared secret. Cloud Scheduler sends this in `X-Cloud-Scheduler-Token`; the agent rejects requests without it. |
| `ALMA_SUPABASE_ANON_KEY` | (reserved) | Supabase REST API key (not used by MCP, kept for future SaaS API) |
| `ALMA_SUPABASE_SERVICE_KEY` | (reserved) | Supabase service-role key |

`./setup-gcp-auto.sh` reads `.env.secrets` (gitignored) and pushes each value as a new version into Secret Manager. Updating a value: edit `.env.secrets`, re-run the script — `gcloud secrets versions add` is idempotent.

---

## Deploy scripts

The repo root contains 3 deploy entry points:

```
setup-gcp-auto.sh         # one-shot: APIs + SA + secrets + 4 services + cron jobs (prod)
setup-gcp-auto-dev.sh     # same as above, deploys -dev variants, cron jobs PAUSED
deploy-ordered.sh         # re-deploy 4 services in order (mcp → agent → telegram → web)
deploy-manual.sh [svc]    # re-deploy ONE service (mcp|agent|telegram|web|all)
```

### Why dev + prod variants?

The dev variant deploys services with `-dev` suffix (`alma-mcp-dev`, `alma-agent-dev`, etc.) sharing the same Supabase + Upstash. This gives the team a staging environment to iterate without touching prod traffic. Cron jobs in dev are created **paused** so they don't spam Telegram users on test data.

### Build pipeline

`gcloud run deploy --source=DIR` is used in all scripts. Behind the scenes Google Cloud Build:
1. Uploads the source directory (respects `.gcloudignore`)
2. Detects the `Dockerfile` and runs `docker build`
3. Pushes the image to Artifact Registry: `us-central1-docker.pkg.dev/proyectosia-423918/cloud-run-source-deploy/alma-{svc}:latest`
4. Deploys a new Cloud Run revision pointing at that image
5. Routes traffic to the new revision once healthy

The MCP image **bakes the fastembed ONNX model** into the layer (`RUN python -c "from fastembed import TextEmbedding; TextEmbedding(...)"`). This adds ~110MB to the image but means Cloud Run cold starts don't have to download the model.

---

## Custom domain — `alma-bot.com`

Used **Cloud Run Domain Mapping** (the official path), not Cloudflare proxy with Origin Rules. Reasons:
- SSL is provisioned by Google (no cert mismatch problems)
- Host header is routed natively (no Origin Rule workaround)
- Cloudflare Free tier doesn't support Host header override in Origin Rules (Enterprise-only)

### Setup steps

1. **Verify domain ownership** in Google Search Console (one click via Cloudflare's "Authorize DNS records from Google" button — adds the TXT record automatically).
2. **Create domain mapping** in Cloud Run:
   ```
   gcloud beta run domain-mappings create \
       --service=alma-web-dev \
       --domain=alma-bot.com \
       --region=us-central1
   ```
   Cloud Run returns 4 A records (`216.239.32.21`, `.34.21`, `.36.21`, `.38.21`) and 4 AAAA records (`2001:4860:4802:{32,34,36,38}::15`).
3. **Add DNS records in Cloudflare** with proxy disabled (DNS-only / 🔘 grey cloud). The grey cloud is required during SSL provisioning — Cloudflare proxy would intercept the ACME challenge.
4. **Wait ~15-60 minutes** for Google's CA to issue the certificate. Status moves: `DomainRoutable=True` → `CertificateProvisioned=True` → `Ready=True`.
5. After SSL is ready, the proxy can optionally be re-enabled (🟠 orange cloud) for DDoS protection and caching. Not required.

### What the user types vs what hits the origin

```
Browser                                                        Cloud Run
─────────────────────────────────────────────────────────────────────
GET https://alma-bot.com/demo.html
  Host: alma-bot.com         ──[DNS Cloudflare]──>  216.239.32.21
                             ──[TLS, SNI: alma-bot.com]──>  Google Frontend
                                Google Frontend looks up SNI in
                                domain-mappings table:
                                "alma-bot.com → alma-web (us-central1)"
                                presents Google-issued cert for alma-bot.com
                             ──[HTTP, Host: alma-bot.com]──> alma-web
```

`alma-web` accepts the request because Cloud Run's domain mapping registered `alma-bot.com` as a valid hostname for that service.

---

## Local development still works

`claude-hackathon-infra/docker-compose.yml` mirrors the prod stack with local containers:

```
postgres (pgvector/pgvector:pg16, port 5433 exposed for tests)
redis (redis:7-alpine, internal only)
mcp (Dockerfile build, depends_on postgres healthy)
agent (Dockerfile build, depends_on redis & mcp healthy)
telegram-bot (Dockerfile build, depends_on agent)
web (nginx:1.25-alpine + nginx.conf with /api proxy to agent:8000)
```

Local dev uses the same Postgres schema (alembic migrations) but a local Postgres instance — not Supabase. The agent uses `SCHEDULER_ENABLED=true` to run APScheduler in-process (since there's no Cloud Scheduler in dev).

```bash
cd claude-hackathon-infra
docker compose up -d --build
curl http://localhost:8080/health
```

---

## Cost (Cloud Run dev environment, ~$45/month)

| Resource | Configuration | Monthly |
|----------|---------------|---------|
| `alma-mcp-dev` | 1 vCPU, 1Gi, min-instances=1 | ~$15 |
| `alma-agent-dev` | 1 vCPU, 1Gi, min-instances=1 | ~$15 |
| `alma-telegram-bot-dev` | 1 vCPU, 512Mi, min-instances=1 | ~$10 |
| `alma-web-dev` | 1 vCPU, 256Mi, min-instances=0 | ~$1 (egress only) |
| Artifact Registry images | 4 × ~250MB | <$1 |
| Secret Manager | 8 secrets | <$0.50 |
| Cloud Scheduler | 3 jobs/day | $0 (free tier) |
| Supabase | Free tier (500MB) | $0 |
| Upstash Redis | Free tier (10k cmds/day) | $0 |
| **Total** | | **~$45/mo** |

All resources can be deleted with:
```bash
gcloud run services delete alma-{mcp,agent,telegram-bot,web}-dev --region=us-central1
gcloud scheduler jobs delete alma-proactive-dev-{breakfast,lunch,dinner} --location=us-central1
```

---

## Verification suite

The repo root has `test-cloud-integration.sh` — runs ~16 assertions against the deployed services:

```
✅ MCP /health = 200
✅ Agent /health = 200
✅ Web / = 200
✅ Telegram service Ready=True
✅ Agent SSE stream (real LLM)
✅ Supabase: rows written from chat
✅ Redis: session written
✅ Memory endpoint returns 4 layers
✅ Web nginx proxy → agent
✅ Cron endpoint with valid token = 200
✅ Cron endpoint with invalid slot = 422
✅ Telegram bot: no recent errors
```

Run with:
```
ENV=dev ./test-cloud-integration.sh
```

---

## Migration notes (v1 → v2 "GCP-deployed")

The `v2.0.0` tag across all repos marks the GCP deployment milestone. The major architectural changes from v1 (local Docker only) to v2:

| v1 | v2 |
|----|----|
| MCP storage: SQLite (`alma.db`) | Postgres + pgvector (Supabase) |
| Embeddings: `BLOB` columns | `vector(384)` with HNSW index |
| Search: Python loop (`numpy cosine`) | SQL `<->` operator (HNSW) |
| Scheduler: in-process APScheduler | Cloud Scheduler → HTTP endpoint |
| Stack: `docker compose` only | Cloud Run (4 services) + custom domain |
| Web URL: `localhost:3000` | `https://alma-bot.com` |
| Local dev DB | Supabase (shared between local + cloud dev) |

See repo `v2.0.0` tags for the changeset:
- [iDeepBrain/claude-hackathon-mcp](https://github.com/iDeepBrain/claude-hackathon-mcp/releases/tag/v2.0.0)
- [iDeepBrain/claude-hackathon-agent](https://github.com/iDeepBrain/claude-hackathon-agent/releases/tag/v2.0.0)
- [iDeepBrain/claude-hackathon-web](https://github.com/iDeepBrain/claude-hackathon-web/releases/tag/v2.0.0)
- [iDeepBrain/claude-hackathon-telegram](https://github.com/iDeepBrain/claude-hackathon-telegram/releases/tag/v2.0.0)
- [iDeepBrain/claude-hackathon-infra](https://github.com/iDeepBrain/claude-hackathon-infra/releases/tag/v2.0.0)
