# Alma — Technical Documentation

> Full technical reference for the Alma system. For the project story and demo, see [README.md](README.md).

---

## Table of Contents

- [Claude Opus 4.7 Integration](#claude-opus-4-7-integration)
- [MCP Server — Alma's Memory](#mcp-server--almas-memory)
- [Proactivity — Alma Reaches Out First](#proactivity--alma-reaches-out-first)
- [Multi-Agent Development Methodology](#multi-agent-development-methodology)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Quick Start](#quick-start)
- [Repository Map](#repository-map)

---

## Claude Opus 4.7 Integration

Alma's conversation engine is **AlmaChain** — a LangChain LCEL pipeline wrapping Claude with memory injection, semantic caching, safety guards, and dynamic model routing.

### Pipeline

```
1. is_injection(message)           → block prompt injection attempts
2. semantic_cache.lookup(message)  → rapidfuzz WRatio>88, then cosine>0.92
3. mcp_client.build_context(uid)   → inject 4-layer memory into system prompt
4. router.select_model(state)      → choose Haiku / Sonnet / Opus
5. llm.astream(messages)           → SSE streaming via Anthropic Python SDK
6. asyncio.create_task(post_work)  → non-blocking: crisis eval, memory upsert, cache
```

### Dynamic Model Routing

| Condition | Model | Reason |
|-----------|-------|--------|
| `crisis_score > 0.7` | `claude-opus-4-7` | Most capable for high-stakes conversations |
| `has_image` | `claude-haiku-4-5` | Vision support, cost-efficient |
| `len(message) > 800` | `claude-sonnet-4-6` | Long-form comprehension |
| default | `claude-haiku-4-5` | Fast, low-latency for daily chat |

### Semantic Cache

Two-stage deduplication prevents redundant Claude calls:
1. **Fuzzy match** — `rapidfuzz.WRatio > 88` (near-identical phrasing)
2. **Cosine similarity** — embedding distance `> 0.92` (semantically equivalent)

Cache lives in Redis with 1h TTL. Embeddings via `fastembed` + ONNX (local).

> **Deep dive:** [Architecture — AlmaChain Pipeline](docs/technical/architecture.md)

---

## MCP Server — Alma's Memory

Alma remembers. Every conversation enriches a persistent memory that is injected into Claude's system prompt on every turn.

### 6 MCP Tools

| Tool | Description |
|------|-------------|
| `get_memory` | Retrieve all 4 memory layers for a user |
| `upsert_memory` | Write or update a memory entry (idempotent by `entry_key`) |
| `search_memories` | Semantic search across all layers (cosine, threshold 0.5) |
| `build_context` | Generate markdown for system prompt injection |
| `evaluate_crisis_risk` | Deterministic crisis score 0-1 (no LLM) |
| `link_anonymous_to_account` | Merge anonymous-session memory into a signed-in account |

### 4-Layer Memory

| Layer | Stores |
|-------|--------|
| `mood_history` | Emotional state + numeric score per day |
| `mentioned_events` | Life events: description, resolved flag, emotional weight |
| `habits` | Behavioral patterns: sleep, exercise, eating, social |
| `interaction_prefs` | Communication style preferences |

**Storage:** SQLite (local dev) → Postgres + pgvector (production, Supabase) + fastembed ONNX (`all-MiniLM-L6-v2`) — local embedding inference, no external API calls.

> **Deep dive:** [MCP Server](docs/technical/mcp-server.md) · [Memory System](docs/technical/memory-system.md) · [Crisis Detection](docs/technical/crisis-detection.md)

---

## Proactivity — Alma Reaches Out First

This is Alma's defining feature. Most mental health apps wait. Alma doesn't.

### 3 Daily Check-Ins

| Slot | Time (Lima UTC-5) | Message |
|------|-------------------|---------|
| Breakfast | 08:30 | "¿Ya desayunaste? ☀️ Un buen comienzo importa" |
| Lunch | 13:30 | "¿Ya almorzaste? 🌞 ¿Cómo va tu día?" |
| Dinner | 19:30 | "¿Ya cenaste? 🌙 ¿Hiciste algo de movimiento hoy?" |

### Safety Gates

| Gate | Logic | Why |
|------|-------|-----|
| Crisis gate | `crisis_score > 0.6` → skip | Don't interrupt someone in distress |
| Silence gate | Active in last 2h → skip | Already engaged |
| Slot gate | Already sent today → skip | No double messages |

Delivered via **APScheduler** (inside agent) + **httpx** direct to Telegram Bot API.

> **Deep dive:** [Proactivity System](docs/technical/proactivity.md) · [Proactivity Flow Diagram](diagrams/05-proactivity-flow.md)

---

## Multi-Agent Development Methodology

Before a single line of production code was written, **12 specialized Claude Code agents** debated the system design in 2 rounds (10+ cycles each).

### The 12 Agents

| Agent | Role |
|-------|------|
| `ai-tech-lead` | Architecture decisions, go/no-go gates |
| `senior-mle-engineer` | ML pipeline, model selection |
| `senior-fullstack-engineer` | API design, SSE, nginx |
| `fullstack-lead` | Repo structure, Docker Compose |
| `junior-mle-engineer` | Fresh perspectives, challenges |
| `junior-fullstack-dev` | Browser APIs, modern patterns |
| `ui-ux-designer` | Emotional UX, demo flow |
| `delivery-lead-agile` | Prioritization, risk management |
| `emotional-companion` | Safety principles for proactive messaging |
| `psiquiatria-informativa` | Clinical ethics for mental health AI |
| `stakeholder-arthur` | Non-technical user perspective |
| `stakeholder-maria-usuario` | Non-technical user perspective (LatAm) |

### Key Decisions from Debate

- **nginx trailing slash bug caught before deployment** — would have caused 404 on every request
- **Audio strategy reversed** — from Docker ONNX models (143GB VM crash) to browser-native Web Speech API
- **"Silence as self-regulation"** — crisis gate added to suppress proactive messages during distress

> **Deep dive:** [Multi-Agent Methodology](docs/process/multi-agent-methodology.md) · [Claude Code Skills](docs/process/claude-code-skills.md)

---

## Architecture

```
Browser → nginx:3000 → /api/* → agent:8000 → redis:6379
                                            → mcp:8001 → Postgres + pgvector
Telegram → telegram-bot → agent:8000
Scheduler → httpx → api.telegram.org   (APScheduler local · Cloud Scheduler prod)
```

| Service | Image | Role |
|---------|-------|------|
| `redis` | redis:7-alpine | Sessions, semantic cache, proactivity keys |
| `postgres` | pgvector/pg16 | 4-layer memory, HNSW semantic search (Supabase in prod) |
| `mcp` | custom | FastMCP server, Postgres + pgvector, fastembed ONNX |
| `agent` | custom | FastAPI, AlmaChain, scheduler (APScheduler local / Cloud Scheduler prod) |
| `telegram-bot` | custom | Telegram polling, chat_id registration |
| `web` | nginx:1.25-alpine | Static files + `/api/*` reverse proxy |

> **Deep dive:** [Architecture](docs/technical/architecture.md) · [All 10 diagrams](diagrams/README.md)

---

## Documentation

### Technical

| Document | What it covers |
|----------|---------------|
| [Architecture](docs/technical/architecture.md) | 6-container system, request flows, env vars, security |
| [MCP Server](docs/technical/mcp-server.md) | 6 tools, 4-layer memory, Postgres + pgvector schema, embeddings |
| [Memory System](docs/technical/memory-system.md) | Memory write/read flows, semantic search |
| [Crisis Detection](docs/technical/crisis-detection.md) | Deterministic scoring, escalation path, proactivity gate |
| [Proactivity](docs/technical/proactivity.md) | APScheduler, Redis keys, safety gates, delivery |

### For Users

| Document | What it covers |
|----------|---------------|
| [Getting Started](docs/user/getting-started.md) | How to use Alma on Telegram and web |
| [Privacy](docs/user/privacy.md) | What Alma stores, retention, deletion |

### Development Process

| Document | What it covers |
|----------|---------------|
| [Multi-Agent Methodology](docs/process/multi-agent-methodology.md) | 12 agents, 2 rounds, concrete debate outcomes |
| [Claude Code Skills](docs/process/claude-code-skills.md) | Skills, hooks, CLAUDE.md infrastructure |

### Architecture Diagrams

[10 Mermaid diagrams](diagrams/README.md) covering every component and flow.

---

## Quick Start

```bash
git clone https://github.com/iDeepBrain/claude-hackathon-infra
cd claude-hackathon-infra
cp .env.example .env          # fill in ANTHROPIC_API_KEY and TELEGRAM_BOT_TOKEN
docker compose up --build -d
docker ps                     # should show 6 containers
```

- Web chat: `http://localhost:3000`
- Agent API: `http://localhost:8080`

---

## Repository Map

| Repository | Role | Runtime |
|-----------|------|---------|
| [`claude-hackathon-infra`](https://github.com/iDeepBrain/claude-hackathon-infra) | Docker Compose orchestrator (6 containers) | Start here |
| [`claude-hackathon-agent`](https://github.com/iDeepBrain/claude-hackathon-agent) | FastAPI + AlmaChain + APScheduler | `agent` service |
| [`claude-hackathon-mcp`](https://github.com/iDeepBrain/claude-hackathon-mcp) | FastMCP memory server (Postgres + pgvector + embeddings) | `mcp` service |
| [`claude-hackathon-telegram`](https://github.com/iDeepBrain/claude-hackathon-telegram) | Telegram bot (polling) | `telegram-bot` service |
| [`claude-hackathon-web`](https://github.com/iDeepBrain/claude-hackathon-web) | Frontend HTML/JS + nginx | `web` service |
| [`claude-hackathon-alma`](https://github.com/iDeepBrain/claude-hackathon-alma) | Public documentation (this repo) | Docs only |
| [`claude-hackathon-experiments`](https://github.com/iDeepBrain/claude-hackathon-experiments) | STT/TTS research (5.9 GB) | Local only |
| [`claude-hackathon-planning`](https://github.com/iDeepBrain/claude-hackathon-planning) | Sprints, kanban | Local only |
