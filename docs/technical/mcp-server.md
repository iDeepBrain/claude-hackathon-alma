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
┌────────────────────────────────────────────────────────┐
│                    memory_layers table                  │
│                                                        │
│  user_id | layer            | entry_key | content (JSON)│
│  --------|------------------|-----------|---------------│
│  u123    | mood_history     | mood_2026-│ {score: 7.2}  │
│  u123    | mentioned_events | evt_job   | {desc: "..."}  │
│  u123    | habits           | habit_001 | {desc: "..."}  │
│  u123    | interaction_prefs| pref_001  | {pref: "..."}  │
└────────────────────────────────────────────────────────┘
         │
         ▼
   embedding BLOB (float32 bytes)
   cosine similarity at query time
   threshold: 0.5
```

Each entry stores a **fastembed ONNX embedding** (`sentence-transformers/all-MiniLM-L6-v2`) alongside the JSON content. Search loads all embeddings for a user into memory and computes cosine similarity in-process with numpy — fast enough for typical user memory sizes (<1000 entries).

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

- **Engine**: SQLite (`alma.db`) via `aiosqlite`
- **Size**: ~20KB per 100 user interactions
- **Location in Docker**: `/app/alma.db` (should be mounted as a volume in production)

```sql
CREATE TABLE memory_layers (
    id              INTEGER PRIMARY KEY,
    user_id         TEXT,
    layer           TEXT,
    entry_key       TEXT,
    content         TEXT,        -- JSON
    embedding       BLOB,        -- float32 bytes
    emotional_weight REAL,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_memory_user_layer ON memory_layers(user_id, layer);
```

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
