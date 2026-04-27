# Architecture

> **Live:** [https://alma-bot.com](https://alma-bot.com) · See **[Deployment](deployment.md)** for Cloud Run, custom domain, secrets, and Cloud Scheduler.

## Overview

Alma runs in two environments that share the same code and the same managed backing services:

| Environment | Web URL | Agent | MCP | Postgres | Redis | Scheduler |
|-------------|---------|-------|-----|----------|-------|-----------|
| **Local** | `localhost:3000` | container | container | `pgvector/pg16` container (port 5433) | `redis:7-alpine` container | APScheduler in-process |
| **Cloud (dev)** | [alma-bot.com](https://alma-bot.com) | Cloud Run | Cloud Run | Supabase Postgres + pgvector | Upstash Redis (TLS) | Cloud Scheduler → HTTP |

Locally, all 6 services (web, agent, mcp, postgres, redis, telegram-bot) run as Docker containers on a private bridge network (IPv6 disabled). In Cloud Run, each service is a separate managed service; persistent state lives in Supabase + Upstash. The application code is identical — only env vars (`DATABASE_URL`, `REDIS_URL`, `MCP_URL`, `SCHEDULER_ENABLED`) change.

---

## Service Map

```
┌─────────────────────────────────────────────────────────────────────┐
│              Docker Network: hackathon (local dev)                   │
│                                                                     │
│  Browser ──HTTP/SSE──► nginx:3000                                   │
│                            │                                        │
│                       /api/* proxy                                  │
│                            │                                        │
│                            ▼                                        │
│  Telegram ──polling──► telegram-bot ──────────────────────┐        │
│                                                            │        │
│                            ┌───────────────────────────────▼──┐    │
│                            │         agent:8000               │    │
│                            │   FastAPI + AlmaChain            │    │
│                            │   APScheduler (proactivity)      │    │
│                            │   /cron/proactive/{slot}  ← HTTP │    │
│                            └──┬──────────────────────┬────────┘    │
│                               │                      │             │
│                          redis:6379             mcp:8001           │
│                        (sessions,           (FastMCP, fastembed)   │
│                         cache,                       │             │
│                         proactivity)                 ▼             │
│                                              postgres:5432         │
│                                          (pgvector/pg16,           │
│                                           5 alma_* tables,         │
│                                           HNSW vector index)        │
└─────────────────────────────────────────────────────────────────────┘

APScheduler (inside agent) ──httpx──► api.telegram.org (external)

In Cloud Run, the local postgres+redis containers become Supabase + Upstash,
and APScheduler is replaced by Cloud Scheduler hitting /cron/proactive/{slot}
via HTTP. See deployment.md for the full Cloud Run topology.
```

---

## Request Flow — Web Chat

1. **Browser** sends `POST /api/v1/chat` with `{user_id, message}` and opens an SSE connection.
2. **nginx** receives the request on port 3000. The `/api/` location block proxies to `http://agent:8000` (no trailing slash — see Critical Implementation Notes).
3. **Agent** receives `POST /v1/chat`. AlmaChain pipeline begins:
   - `is_injection(message)` — if positive, return blocked response immediately.
   - `semantic_cache.lookup(message)` — if cache hit, stream cached response and return.
   - `mcp_client.build_context(user_id)` — call MCP `get_memory` tool, build system prompt with 4 memory layers.
   - `router.select_model(state)` — select Haiku / Sonnet / Opus based on crisis score, message length, image presence.
   - `llm.astream(messages)` — stream tokens from Anthropic SDK.
4. **SSE tokens** flow back through nginx to the browser. The web frontend appends each token to the chat bubble as it arrives.
5. After the stream ends, `asyncio.create_task(post_response_work)` fires non-blocking:
   - `evaluate_crisis_risk(message)` — update crisis score in Redis.
   - `upsert_mood_history(uid, response)` — write today's mood to MCP.
   - `detect_mentioned_events(response)` — extract and upsert life events to MCP.
   - `cache_response(message, response)` — store embedding + text in Redis for semantic cache.

---

## Request Flow — Telegram

1. **User** sends a message to the Alma Telegram bot.
2. **telegram-bot** service receives it via long polling from `api.telegram.org`.
3. On first message from a user, telegram-bot stores `{tg_user_id → chat_id}` in Redis under key `alma:chat:{tg_user_id}`.
4. telegram-bot constructs `user_id = "tg_{tg_user_id}"` and calls `POST agent:8000/v1/chat`.
5. **Agent** runs the full AlmaChain pipeline (same as web, no SSE — response is returned as a complete string).
6. Agent returns the response JSON to telegram-bot.
7. **telegram-bot** calls Telegram Bot API `sendMessage` with the response text.

---

## Proactivity Flow

1. **APScheduler** fires a job at 08:30, 13:30, or 19:30 Lima time (UTC-5).
2. Agent queries Redis for all known Telegram users: `KEYS alma:chat:*`.
3. For each user, run safety gate checks (all three must pass):
   - **Crisis gate:** `GET alma:proactive:crisis_score:{user_id}` — if `> 0.6`, skip.
   - **Silence gate:** `GET alma:proactive:last:{user_id}` — if timestamp is within last 2 hours, skip.
   - **Slot gate:** `EXISTS alma:proactive:slot:{user_id}:{date}:{slot}` — if key exists, skip.
4. If all gates pass:
   - Retrieve `chat_id` from `alma:chat:{tg_user_id}`.
   - Send message via `httpx.post("https://api.telegram.org/bot{TOKEN}/sendMessage", ...)` directly from the agent process.
   - Set `alma:proactive:slot:{user_id}:{date}:{slot}` with TTL = end of day.
   - Update `alma:proactive:last:{user_id}` with current timestamp.

---

## AlmaChain Pipeline

AlmaChain is a LangChain LCEL chain defined in the agent service. Each step is a runnable that either short-circuits (injection block, cache hit) or passes state to the next step.

```
Step 1: InjectionGuard
        Input:  raw user message (str)
        Check:  pattern matching against known injection signatures
        Output: blocked response (str) | pass-through to Step 2

Step 2: SemanticCache
        Input:  user message (str)
        Check:  rapidfuzz WRatio > 88 → cosine similarity > 0.92
        Output: cached response (str) | pass-through to Step 3

Step 3: MemoryInjector (MCP client)
        Input:  user_id (str)
        Action: call MCP get_memory tool, format 4 layers as system prompt sections
        Output: enriched ChatPromptTemplate with memory context

Step 4: ModelRouter
        Input:  crisis_score (float), has_image (bool), message_len (int)
        Output: selected model ID + token budget

Step 5: AnthropicStreamer
        Input:  messages list, model ID, max_tokens
        Action: llm.astream() via Anthropic Python SDK
        Output: async generator of token chunks → SSE stream

Step 6: PostResponseWorker (asyncio.create_task — non-blocking)
        Input:  full response text, user_id, message
        Actions:
          - evaluate_crisis_risk → update Redis score
          - upsert_mood_history → MCP tool call
          - detect_mentioned_events → MCP tool call
          - cache_response → compute embedding, store in Redis
```

---

## Semantic Cache

The cache prevents redundant Claude API calls for similar questions.

**Stage 1 — Fuzzy string match:**
- `rapidfuzz.fuzz.WRatio(new_message, cached_message) > 88`
- Fast, no embedding needed
- Catches typos and minor rephrasing

**Stage 2 — Cosine similarity:**
- Only runs if Stage 1 passes
- `cosine(embed(new_message), embed(cached_message)) > 0.92`
- Catches semantically equivalent queries with different wording
- Embeddings computed locally via fastembed ONNX (no API call)

**Storage:**
- Redis hash: `alma:cache:{user_id}:{message_hash}` → `{text, embedding, response}`
- TTL: 3600 seconds (1 hour)
- Threshold configurable via `CACHE_THRESHOLD` env var (default: 0.92)

---

## Model Routing

| Priority | Condition | Model | Max Tokens |
|----------|-----------|-------|-----------|
| 1 | `crisis_score > 0.7` | `claude-opus-4-7` | 2048 |
| 2 | `has_image == True` | `claude-haiku-4-5` | 1024 |
| 3 | `len(message) > 800` | `claude-sonnet-4-6` | 2048 |
| 4 | default | `claude-haiku-4-5` | 1024 |

Rules are evaluated in priority order; first match wins. Crisis routing always takes precedence because it requires Opus's deepest reasoning for high-stakes conversations.

---

## Proactivity System

### APScheduler Configuration

The agent runs APScheduler with `AsyncIOScheduler` (in-process, same event loop as FastAPI):

```
Job: proactive_breakfast   cron: hour=8,  minute=30  tz=America/Lima
Job: proactive_lunch       cron: hour=13, minute=30  tz=America/Lima
Job: proactive_dinner      cron: hour=19, minute=30  tz=America/Lima
```

Proactivity is enabled/disabled via `SCHEDULER_ENABLED=true/false` env var.

### Redis Key Patterns

```
alma:chat:{tg_user_id}                       → Telegram chat_id (string)
                                               Set by telegram-bot on first message.
                                               No TTL — permanent.

alma:proactive:last:{user_id}                → Unix timestamp (string)
                                               Updated after every proactive send.
                                               TTL: none (updated in place).

alma:proactive:slot:{user_id}:{date}:{slot}  → "1" (string)
                                               date format: YYYY-MM-DD
                                               slot values: breakfast | lunch | dinner
                                               TTL: set to expire at midnight Lima time.

alma:proactive:crisis_score:{user_id}        → float as string (e.g. "0.75")
                                               Updated after every message evaluation.
                                               TTL: 24 hours.
```

### Safety Gates

All three gates must pass before a proactive message is sent:

| Gate | Redis Key | Condition to SKIP |
|------|-----------|-------------------|
| Crisis gate | `alma:proactive:crisis_score:{user_id}` | value > 0.6 |
| Silence gate | `alma:proactive:last:{user_id}` | now - timestamp < 7200s (2h) |
| Slot gate | `alma:proactive:slot:{user_id}:{date}:{slot}` | key exists |

### Message Delivery

Proactive messages are sent **directly from the agent** via httpx to the Telegram Bot API:

```
httpx.post(
    f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
    json={"chat_id": chat_id, "text": message_text}
)
```

The agent holds `TELEGRAM_BOT_TOKEN` specifically to enable this. The telegram-bot service is not involved in proactive delivery — this avoids adding a 6th network hop and keeps the proactivity logic co-located with the scheduling logic.

---

## Data Persistence

| Data | Storage | TTL | Notes |
|------|---------|-----|-------|
| Conversation history | Redis list | 24 hours | JSON-encoded message list per user_id |
| Semantic cache | Redis hash | 1 hour | Message text + embedding + Claude response |
| Proactivity slot flags | Redis string | End of day | Reset daily at midnight Lima time |
| Proactivity timestamps | Redis string | None | Overwritten on each send |
| Crisis scores | Redis string | 24 hours | Overwritten on each message evaluation |
| Mood history | SQLite (MCP) | Permanent | One row per user per day |
| Mentioned events | SQLite (MCP) | Permanent | Append-only with update support |
| Habits | SQLite (MCP) | Permanent | Upsert by habit type |
| Interaction prefs | SQLite (MCP) | Permanent | Upsert by preference key |

---

## Environment Variables

### agent

```env
ANTHROPIC_API_KEY=sk-ant-...          # Claude API key
REDIS_URL=redis://redis:6379          # Redis connection
MCP_URL=http://mcp:8001               # FastMCP server URL
SESSION_TTL=86400                     # Conversation history TTL (seconds)
CACHE_TTL=3600                        # Semantic cache TTL (seconds)
CACHE_THRESHOLD=0.92                  # Cosine similarity threshold for cache hit

TELEGRAM_BOT_TOKEN=...                # Required for proactive delivery
SCHEDULER_ENABLED=true                # Enable/disable APScheduler
PROACTIVE_TZ=America/Lima             # Timezone for all scheduler jobs
PROACTIVE_BREAKFAST_H=8               # Breakfast check-in hour
PROACTIVE_LUNCH_H=13                  # Lunch check-in hour
PROACTIVE_DINNER_H=19                 # Dinner check-in hour
PROACTIVE_SILENCE_WINDOW_H=2          # Silence gate window (hours)
```

### mcp

```env
DATABASE_URL=sqlite:///./alma.db      # SQLite database path
EMBEDDING_MODEL=all-MiniLM-L6-v2     # fastembed model name
SIMILARITY_THRESHOLD=0.5              # Memory search cosine threshold
```

### telegram-bot

```env
TELEGRAM_BOT_TOKEN=...                # Same token as agent
AGENT_URL=http://agent:8000           # Agent API base URL
REDIS_URL=redis://redis:6379          # For storing chat_id on first message
```

### web (nginx)

```
No application env vars. nginx.conf is the configuration.
proxy_pass http://agent:8000  (no trailing slash)
```

### redis

```
No custom configuration. Uses Redis defaults with redis:7-alpine.
```

---

## Security Decisions

- **No model weights in Docker images.** fastembed ONNX models (all-MiniLM-L6-v2) are downloaded at container boot from a mounted cache volume. Images remain lightweight; CI builds are fast; model updates don't require image rebuilds.
- **IPv6 disabled on Docker network.** `enable_ipv6: false` in Compose network config. Without this, httpx resolves `api.telegram.org` to an IPv6 address that is unreachable from within the Docker bridge network, causing all Telegram API calls to fail with connection errors.
- **COEP / COOP headers on nginx.** `Cross-Origin-Embedder-Policy: require-corp` and `Cross-Origin-Opener-Policy: same-origin` are set on all responses. Required for SharedArrayBuffer (Web Speech API future use) and general isolation.
- **`.env` files never committed.** All secrets are passed via environment variables. `.env.example` contains only placeholder values.
- **Crisis detection is deterministic.** Keyword-based scoring with no LLM dependency. The safety escalation path (MINSA 113) works even if the Anthropic API is unreachable, rate-limited, or the model is misbehaving.
- **Prompt injection guard runs first.** `is_injection()` is Step 1 of AlmaChain — before any memory lookup, model call, or cache write. Injections are blocked with a static response.

---

## Critical Implementation Notes

### nginx proxy_pass trailing slash bug

**Symptom:** All `/api/v1/chat` requests return 404 from the agent.

**Root cause:** When `proxy_pass` is configured with a trailing slash:
```nginx
location /api/ {
    proxy_pass http://agent:8000/;   # WRONG
}
```
nginx strips the `/api/` prefix before forwarding. The agent receives `GET /v1/chat` instead of `GET /api/v1/chat` — the route does not exist, so FastAPI returns 404.

**Fix:** Remove the trailing slash from `proxy_pass`:
```nginx
location /api/ {
    proxy_pass http://agent:8000;    # CORRECT
}
```
nginx now forwards the full path including `/api/`, and FastAPI matches `GET /api/v1/chat` correctly.

This bug was caught during the multi-agent debate (Agent 12, Integration Tester) before any code was written.

---

### IPv6 disabled on Docker network

**Symptom:** httpx calls from the agent to `api.telegram.org` fail with `ConnectError` or `NetworkError`.

**Root cause:** Docker enables IPv6 on bridge networks by default in some configurations. httpx, following RFC 6555 (Happy Eyeballs), prefers IPv6 when DNS resolves to both A and AAAA records. `api.telegram.org` has AAAA records. The Docker bridge network does not route IPv6 traffic to the internet, so the connection fails.

**Fix:** Disable IPv6 on the Compose network:
```yaml
networks:
  alma-net:
    driver: bridge
    enable_ipv6: false
```
This forces DNS resolution to return only A (IPv4) records, which the Docker bridge routes correctly.

---

### TELEGRAM_BOT_TOKEN in both agent and telegram-bot

Both services hold the same token for different purposes:

| Service | Why it needs the token |
|---------|----------------------|
| `telegram-bot` | Polling `getUpdates`, sending `sendMessage` replies to user messages |
| `agent` | Sending proactive `sendMessage` calls from APScheduler jobs |

These are separate concerns. The telegram-bot service handles reactive messaging (user → bot). The agent handles proactive messaging (scheduler → user). Co-locating proactive delivery in the agent avoids inter-service calls on the hot path of scheduled jobs.
