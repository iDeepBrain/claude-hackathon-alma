# MCP Server — Alma's Memory Architecture

Alma uses a custom [FastMCP](https://github.com/jlowin/fastmcp) server for persistent, semantic memory. The server runs as a sidecar to the agent and is accessed exclusively via the MCP protocol over HTTP.

## Transport

```
agent → POST http://mcp:8001/mcp  (streamable_http transport)
```

The agent connects via `langchain-mcp-adapters`, which exposes MCP tools as LangChain `BaseTool` objects that can be used in LCEL chains.

## Tools

### `get_memory_tool`
Returns all 4 memory layers for a user.

```python
# Input
{"user_id": "user_123"}

# Output
{
  "mood_history": [{"entry_key": "mood_2026-04-26", "content": {"mood_score": 7.2, "crisis_score": 0.1}, "emotional_weight": 0.8, ...}],
  "mentioned_events": [...],
  "habits": [...],
  "interaction_prefs": [...]
}
```

### `search_memories_tool`
Semantic search over all memory entries using cosine similarity.

```python
# Input
{"user_id": "user_123", "query": "trabajo entrevista", "k": 5}

# Output — scored results across all layers
[{"layer": "mentioned_events", "content": {...}, "score": 0.87, ...}]
```

### `upsert_memory_tool`
Write or update a memory entry. Uses `entry_key` for idempotent upserts.

```python
# Input
{
  "user_id": "user_123",
  "layer": "mood_history",
  "data": {"entry_key": "mood_2026-04-26", "mood_score": 7.5, "crisis_score": 0.0}
}
```

### `build_context_tool`
Builds a human-readable markdown string for injection into the LLM system prompt.

```python
# Input
{"user_id": "user_123"}

# Output (markdown string injected into Claude's system prompt)
"""
## Contexto de user_123

### Estado de ánimo reciente
7.5/10 (↑ 1.3 pts, 3 días)

### Eventos mencionados (sin resolver)
- Job interview at tech company (peso: 0.9)

### Hábitos observados
- Sleeps late on weekends

### Preferencias de interacción
- Prefers short, direct responses
"""
```

### `evaluate_crisis_risk_tool`
**Deterministic crisis detection — no LLM involved.**

```python
# Input
{"user_id": "user_123", "message": "no puedo más con esto"}

# Output
{"score": 0.72, "level": "high", "keywords_matched": ["no puedo más"]}
```

**Why deterministic?** In a mental health context, crisis detection must be:
- **Fast** — not dependent on LLM inference latency
- **Predictable** — reproducible results for the same input
- **Auditable** — human-reviewable keyword list, no black box

This is a safety-first architectural decision. The LLM is used for empathetic conversation; crisis escalation is handled by a deterministic system.

---

## 4-Layer Memory Model

```
┌─────────────────────────────────────────────────────────────────┐
│                  alma_memory_layers (Postgres)                  │
│                                                                 │
│  user_id  | layer            | entry_key | content (JSONB)      │
│  ---------|------------------|-----------|----------------------│
│  u123     | mood_history     | 2026-04-26│ {"mood_score": 7.2}  │
│  u123     | mentioned_events | job_intvw │ {"description": ...} │
│  u123     | habits           | NULL      | {"description": ...} │
│  u123     | interaction_prefs| short_msg │ {"preference": ...}  │
│           |                  |           |                      │
│  + emotional_weight float, created_at, updated_at              │
│  + UNIQUE (user_id, layer, entry_key) ← upsert idempotency      │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
   embedding vector(384)  ← pgvector type
   HNSW index (cosine_ops, m=16, ef_construction=64)
   SQL: ORDER BY embedding <=> $query_vec LIMIT k
```

Each entry stores a **fastembed ONNX embedding** (`sentence-transformers/all-MiniLM-L6-v2`, 384-dim) in a `vector(384)` column. The HNSW index turns semantic search into an `O(log n)` SQL operation — Postgres returns the top-k matches without us loading all rows into memory.

---

## Integration with AlmaChain

```python
# Per-message flow in chain.py:

# 1. Build context (top of every conversation turn)
context = await mcp_client.build_context(user_id)
# → injected into Claude's system prompt

# 2. After response (async, non-blocking):
await mcp_client.upsert_memory(user_id, "mood_history", {...})
await mcp_client.evaluate_crisis_risk(user_id, message)
# → updates memory without blocking the stream
```

## Database

- **Engine**: Postgres 16 + `pgvector` extension (Supabase in prod, `pgvector/pgvector:pg16` locally)
- **Driver**: `asyncpg` via SQLAlchemy 2.0 async sessions (NullPool in tests, pooled in prod)
- **Migrations**: Alembic (`migrations/versions/001_alma_initial_schema.py`)
- **Connection**: Supabase Session Pooler (IPv4-routable, required for Cloud Run egress)

### Schema (5 tables)

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Users (one row per user_id)
CREATE TABLE alma_users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(64) UNIQUE NOT NULL,    -- 'tg_<id>' or web UUID
    channel         VARCHAR(20) DEFAULT 'web',
    name            VARCHAR(200),
    tg_chat_id      BIGINT,
    tg_user_id      BIGINT,
    first_seen_at   TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at    TIMESTAMPTZ DEFAULT NOW(),
    message_count   INTEGER DEFAULT 0,
    metadata        JSONB DEFAULT '{}'
);

-- 2. The 4-layer memory store with semantic embeddings
CREATE TABLE alma_memory_layers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    layer               VARCHAR(50) NOT NULL,        -- mood_history|mentioned_events|habits|interaction_prefs
    entry_key           TEXT,
    content             JSONB NOT NULL,
    embedding           vector(384),                 -- fastembed all-MiniLM-L6-v2
    emotional_weight    FLOAT DEFAULT 0.5,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, layer, entry_key)               -- upsert idempotency
);
CREATE INDEX idx_alma_memory_user_layer ON alma_memory_layers (user_id, layer);
CREATE INDEX idx_alma_memory_hnsw ON alma_memory_layers
    USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64);

-- 3. Conversation sessions (one per user × channel)
CREATE TABLE alma_conversations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    channel             VARCHAR(20) NOT NULL,
    started_at          TIMESTAMPTZ DEFAULT NOW(),
    last_message_at     TIMESTAMPTZ DEFAULT NOW(),
    message_count       INTEGER DEFAULT 0,
    crisis_score_max    FLOAT DEFAULT 0.0
);

-- 4. Per-message audit trail (LLM telemetry)
CREATE TABLE alma_messages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     UUID NOT NULL,
    user_id             VARCHAR(64) NOT NULL,
    role                VARCHAR(20) NOT NULL,        -- user|assistant|system
    content             TEXT NOT NULL,
    crisis_score        FLOAT DEFAULT 0.0,
    llm_provider        VARCHAR(20),                 -- anthropic|gemini
    llm_model           VARCHAR(50),
    tokens_input        INTEGER,
    tokens_output       INTEGER,
    cache_hit           BOOLEAN DEFAULT FALSE,
    response_time_ms    INTEGER,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Cron idempotence (prevents duplicate proactive sends)
CREATE TABLE alma_proactive_log (
    id          BIGSERIAL PRIMARY KEY,
    user_id     VARCHAR(64) NOT NULL,
    slot        VARCHAR(20) NOT NULL,                -- breakfast|lunch|dinner|crisis_followup
    date_lima   DATE NOT NULL,
    sent_at     TIMESTAMPTZ DEFAULT NOW(),
    message_id  UUID,
    UNIQUE (user_id, slot, date_lima)                -- guarantee one send per slot per day
);
```

### Search query example

```python
# tools/memory_tools.py — search_memories()
distance = AlmaMemoryLayer.embedding.cosine_distance(query_vec)
stmt = (
    select(AlmaMemoryLayer, distance.label("distance"))
    .where(AlmaMemoryLayer.user_id == user_id)
    .where(AlmaMemoryLayer.embedding.is_not(None))
    .order_by(distance)             # HNSW index used here
    .limit(k)
)
```

### Why migrate from SQLite to Postgres+pgvector

The v1 design used SQLite (`alma.db`) with embeddings stored as `BLOB` columns. This worked locally but had two showstoppers for Cloud Run:

| Problem | SQLite | Postgres + pgvector |
|---------|--------|---------------------|
| Filesystem persistence | Required volume mount (Cloud Run has none) | External managed DB (Supabase) |
| Multiple replicas | Each replica has its own DB | Shared DB across all replicas |
| Search scalability | `O(n)` cosine in Python | `O(log n)` via HNSW index |
| ACID writes | Yes | Yes |
| Native JSON | No (TEXT only) | JSONB with GIN indexing |

---

## Crisis Gate for Proactivity

`evaluate_crisis_risk_tool` is called by **two independent systems**, not just one:

| Caller | When | Purpose |
|--------|------|---------|
| AlmaChain (`chain.py`) | After every user message, async non-blocking | Update `alma:proactive:crisis_score:{user_id}` in Redis |
| APScheduler (in agent) | Before every scheduled proactive check-in | Read score; suppress message if `> 0.6` |

Before the scheduler sends any check-in (breakfast, lunch, or dinner), it reads the user's last known crisis score:

```python
last_score = redis.get(f"alma:proactive:crisis_score:{user_id}")
if last_score and float(last_score) > 0.6:
    # suppress proactive message — do not disturb
    return
```

This ensures Alma never asks "¿Ya desayunaste? ☀️" to someone who has recently expressed high-risk thoughts.

**Why deterministic, not LLM-based:** The crisis gate runs on the hot path of the scheduler — it must be fast, predictable, and have zero cost per evaluation. A keyword + heuristic score stored in Redis satisfies all three. An LLM call before every suppression decision would add latency, cost, and non-determinism to a safety-critical check.

---

## Why Local Inference

Alma computes sentence embeddings locally using `fastembed` with the `sentence-transformers/all-MiniLM-L6-v2` model via ONNX Runtime.

**How it works:**
- The model is downloaded once at first container boot (not baked into the image)
- Subsequent boots use the cached model from the mounted volume
- All embedding computation happens inside the `mcp` container — no external API call

**Why not an embeddings API:**

| Factor | Local (fastembed) | External API |
|--------|-------------------|--------------|
| Cost | Zero per call | Billed per token |
| Latency | ~50ms warm | ~100–300ms + network |
| Privacy | Messages never leave the container | Sent to third-party |
| Availability | Works offline | Requires internet + API key |

**Trade-off acknowledged:** Pure keyword search would be ~0ms. The 50ms embedding cost is accepted because semantic search meaningfully improves memory retrieval quality — finding "usuario mencionó que no puede dormir" when querying for "sleep problems" is the core value of the memory system.
