# MCP Memory System

This diagram details the internals of the FastMCP semantic memory server (`claude-hackathon-mcp`). It exposes 5 tools over streamable HTTP, stores data in a 4-layer memory model (mood_history, mentioned_events, habits, interaction_prefs) backed by **Postgres + pgvector**, and provides semantic search using fastembed ONNX embeddings (all-MiniLM-L6-v2, 384 dimensions) with an HNSW index for `O(log n)` retrieval. The `build_context_tool` composes all layers into a markdown string injected into the LLM system prompt, giving Alma persistent knowledge about each user.

> **v1 → v2 migration:** Originally backed by SQLite (`alma.db` with `BLOB` embeddings + Python in-memory cosine). Migrated to Postgres + pgvector to make the MCP stateless and Cloud-Run-friendly. See [Deployment](../docs/technical/deployment.md) for the migration story.

```mermaid
graph TD
    subgraph MCP["FastMCP Server (server.py :8001)"]
        direction TB

        subgraph TOOLS["Registered Tools"]
            T1["get_memory_tool<br>user_id → all 4 layers"]
            T2["search_memories_tool<br>user_id + query + k<br>→ scored results"]
            T3["upsert_memory_tool<br>user_id + layer + data<br>→ idempotent (UNIQUE)"]
            T4["build_context_tool<br>user_id → markdown string<br>(injected into system prompt)"]
            T5["evaluate_crisis_risk_tool<br>message → score 0-1<br>(deterministic, no LLM)"]
        end

        subgraph LAYERS["4-Layer Memory Model"]
            direction LR
            L1["mood_history<br>{mood_score: 0-10<br>crisis_score: 0-1}"]
            L2["mentioned_events<br>{description, resolved,<br>emotional_weight}"]
            L3["habits<br>{description,<br>frequency}"]
            L4["interaction_prefs<br>{preference,<br>value}"]
        end

        subgraph EMBED["Embedding Layer"]
            EMB["fastembed ONNX<br>all-MiniLM-L6-v2<br>(384-dim, L2-normalized)"]
        end
    end

    subgraph PG["Postgres + pgvector (Supabase prod, container local)"]
        direction TB

        subgraph SCHEMA["alma_memory_layers"]
            COL_USR["user_id VARCHAR(64)"]
            COL_LAY["layer VARCHAR(50)"]
            COL_KEY["entry_key TEXT"]
            COL_CON["content JSONB"]
            COL_VEC["embedding vector(384)"]
            COL_W["emotional_weight FLOAT"]
            UNIQ["UNIQUE (user_id, layer, entry_key)<br>← upsert idempotency"]
        end

        subgraph IDX["Indexes"]
            IDX1["idx_alma_memory_user_layer<br>BTREE (user_id, layer)"]
            IDX2["idx_alma_memory_hnsw<br>HNSW (embedding vector_cosine_ops)<br>m=16, ef_construction=64"]
        end

        subgraph SEARCH["SQL Semantic Search"]
            QRY["SELECT *,<br>embedding ⟨=⟩ $query_vec AS distance<br>FROM alma_memory_layers<br>WHERE user_id = $1<br>ORDER BY distance LIMIT k"]
        end
    end

    T1 -->|"SELECT"| SCHEMA
    T3 -->|"INSERT ... ON CONFLICT DO UPDATE"| SCHEMA
    T3 --> EMB
    T2 --> EMB
    T2 --> QRY
    QRY --> IDX2
    T4 --> T1
    SCHEMA --> EMB

    style MCP fill:#fff3e0,stroke:#e65100
    style PG fill:#e8f4e8,stroke:#2d7a2d
    style IDX2 fill:#ffd54f,stroke:#f57c00
```

## Key Takeaways

- **4-layer memory model**: User memory is structured into `mood_history`, `mentioned_events`, `habits`, and `interaction_prefs` — each with its own JSON schema, enabling targeted retrieval and context building.
- **Crisis detection is deterministic**: `evaluate_crisis_risk_tool` uses keyword matching (no LLM) to produce a 0-1 score, ensuring fast, predictable, cost-free safety evaluations.
- **Semantic search via SQL HNSW**: Embeddings live in `vector(384)` columns. The HNSW index makes top-k cosine search an `O(log n)` SQL query — no Python loop, no in-memory load. Same indexed query works against the local Docker Postgres or Supabase via the Session Pooler.
- **Idempotent upserts**: A `UNIQUE (user_id, layer, entry_key)` constraint plus `INSERT ... ON CONFLICT DO UPDATE` means re-sending the same fact yields the same row (with updated content + new embedding).
