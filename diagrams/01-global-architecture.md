# Global System Architecture

Alma runs in two parallel environments that share the same code:

- **Local** (this diagram) — six Docker containers on a private `hackathon` bridge network. Postgres+pgvector and Redis run as containers, APScheduler runs in-process inside the agent.
- **Cloud (production)** — same services as Cloud Run instances, fronted by `alma-bot.com` (Cloud Run Domain Mapping). Postgres lives in Supabase, Redis in Upstash, and APScheduler is replaced by Cloud Scheduler firing HTTP POSTs to `/cron/proactive/{slot}`. See **[Deployment](../docs/technical/deployment.md)** for the Cloud Run topology.

External dependencies in both environments: Anthropic API (Claude — primary LLM), Google Gemini API (fallback LLM), Telegram Bot API (push messaging).

```mermaid
graph TB
    subgraph HOST["Host Machine"]
        P3000["Port 3000 (Web)"]
        P8080["Port 8080 (Dev/curl)"]
        P5433["Port 5433 (Postgres for tests)"]
    end

    subgraph DOCKER["Docker Network: hackathon (bridge, IPv6 disabled)"]
        direction TB

        subgraph WEB["web — nginx:1.25-alpine"]
            NGINX["nginx<br>Static files<br>Proxy /api/* → agent:8000"]
        end

        subgraph AGENT["agent — FastAPI :8000"]
            CHAIN["AlmaChain<br>(LangChain LCEL)"]
            SCHED["APScheduler<br>(SCHEDULER_ENABLED=true)"]
            CRON["/cron/proactive/{slot}<br>(Cloud Scheduler endpoint)"]
            CACHE["SemanticCache<br>(2-stage: rapidfuzz + cosine)"]
            ROUTER["ModelRouter<br>(Haiku/Sonnet/Opus + Gemini fallback)"]
            GUARD["InjectionGuard"]
        end

        subgraph MCP["mcp — FastMCP :8001"]
            TOOLS["6 MCP Tools"]
            EMB["fastembed ONNX<br>all-MiniLM-L6-v2 (384-dim)"]
        end

        subgraph PG["postgres :5432 (pgvector/pg16)"]
            TABLES["5 alma_* tables<br>alembic upgrade head"]
            VECT["vector(384) + HNSW<br>cosine_distance search"]
        end

        REDIS["redis:7-alpine :6379<br>Sessions + Semantic Cache<br>Chat ID index"]

        subgraph TG["telegram-bot — python-telegram-bot"]
            BOT["Polling loop<br>Handlers: text/photo/PDF<br>+ stdlib HTTP /health (Cloud Run compat)"]
        end
    end

    subgraph EXTERNAL["External Services"]
        ANTHROPIC["Anthropic API<br>Claude Opus 4.7 / Haiku 4.5"]
        GEMINI["Google Gemini API<br>gemini-2.5-flash-lite (fallback)"]
        TGAPI["Telegram Bot API<br>api.telegram.org"]
    end

    P3000 --> NGINX
    P8080 --> AGENT
    P5433 --> PG

    NGINX -->|"proxy /api/*"| AGENT
    NGINX -.->|"static files"| WEB

    AGENT --> REDIS
    AGENT --> MCP
    AGENT --> ANTHROPIC
    AGENT -.->|"fallback"| GEMINI
    AGENT -->|"proactive send<br>httpx POST"| TGAPI

    TG --> AGENT
    TG --> TGAPI
    TG -->|"SET alma:chat:{tg_id}"| REDIS

    MCP --> PG
    MCP --> EMB

    style DOCKER fill:#f0f7ff,stroke:#4a7fa5
    style AGENT fill:#e8f4e8,stroke:#2d7a2d
    style MCP fill:#fff3e0,stroke:#e65100
    style PG fill:#fff3e0,stroke:#e65100
    style WEB fill:#e8eaf6,stroke:#3f51b5
    style TG fill:#e3f2fd,stroke:#1976d2
```

## Production at `alma-bot.com`

In Cloud Run the topology stays the same but each service runs as its own managed instance, and Postgres + Redis are external managed services:

```
Browser → DNS Cloudflare (alma-bot.com → 216.239.x.x)
       → Google Frontend (SNI alma-bot.com → SSL cert valid)
       → alma-web (Cloud Run)
            nginx /api/* proxy → alma-agent (Host header rewritten via envsubst)
       → alma-agent (Cloud Run)
            FastAPI + AlmaChain + LLM chain
       → alma-mcp (Cloud Run, public for service-to-service)
            ↓ asyncpg
            Supabase Postgres + pgvector (Session Pooler, IPv4)
       → Upstash Redis (TLS, rediss://)
       → Anthropic / Gemini APIs
       → alma-telegram-bot (Cloud Run, polls api.telegram.org)

Cloud Scheduler (3 cron jobs) → POST /cron/proactive/{slot}
                                 X-Cloud-Scheduler-Token header
                                 (verified against CRON_TOKEN secret)
```

## Key Takeaways

- **Same code, two environments**: The application is identical between local Docker and Cloud Run. Only env vars (`DATABASE_URL`, `REDIS_URL`, `MCP_URL`, `SCHEDULER_ENABLED`) change.
- **Postgres + pgvector everywhere**: Local stack mirrors prod by running `pgvector/pg16` as a container with the same `alembic upgrade head` schema. No "works on my SQLite, breaks in prod".
- **Agent is the hub**: The FastAPI agent connects to Redis, MCP, Anthropic, Gemini, and Telegram — single point through which all conversation data flows.
- **LLM dual-provider with auto-fallback**: Anthropic Claude is primary; Gemini auto-takes-over when Anthropic returns errors (e.g. credit exhausted). Configured via 8 `LLM_*` env vars without touching code.
- **APScheduler vs Cloud Scheduler**: APScheduler runs in-process locally (single replica). Cloud Scheduler fires HTTP POSTs in production where multiple agent replicas would otherwise duplicate jobs.
