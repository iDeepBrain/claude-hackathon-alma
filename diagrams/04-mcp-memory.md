# MCP Memory System

This diagram details the internals of the FastMCP semantic memory server (`claude-hackathon-mcp`). It exposes 5 tools over streamable HTTP, stores data in a 4-layer memory model (mood_history, mentioned_events, habits, interaction_prefs) backed by SQLite, and provides semantic search using fastembed ONNX embeddings (all-MiniLM-L6-v2, 384 dimensions). The `build_context_tool` composes all layers into a markdown string injected into the LLM system prompt, giving Alma persistent knowledge about each user.

```mermaid
graph TD
    subgraph MCP["FastMCP Server (server.py :8001)"]
        direction TB

        subgraph TOOLS["Registered Tools"]
            T1["get_memory_tool\nuser_id → all 4 layers\n(dict with lists)"]
            T2["search_memories_tool\nuser_id + query + k\n→ scored results"]
            T3["upsert_memory_tool\nuser_id + layer + data\n→ idempotent write"]
            T4["build_context_tool\nuser_id → markdown string\n(injected into system prompt)"]
            T5["evaluate_crisis_risk_tool\nmessage → score 0-1\n(deterministic, no LLM)"]
        end

        subgraph LAYERS["4-Layer Memory Model"]
            direction LR
            L1["mood_history\n{mood_score: 0-10\n crisis_score: 0-1}"]
            L2["mentioned_events\n{description: str\n resolved: bool\n emotional_weight: float}"]
            L3["habits\n{description: str\n frequency: str}"]
            L4["interaction_prefs\n{preference: str\n value: str}"]
        end

        subgraph STORAGE["Storage Layer"]
            DB["SQLite: alma.db\nmemory_layers table\nINDEX user_id, layer"]
            EMB["fastembed ONNX\nall-MiniLM-L6-v2\n(384-dim embeddings)"]
        end

        subgraph SEARCH["Semantic Search"]
            LOAD["Load all embeddings\nfor user (in-memory)"]
            COS["Cosine similarity\n(numpy)"]
            FILTER["threshold: 0.5\ntop-k results"]
        end
    end

    T1 & T3 --> DB
    T2 --> LOAD --> COS --> FILTER
    T3 --> EMB
    T4 --> T1
    DB --> EMB
```

## Key Takeaways

- **4-layer memory model**: User memory is structured into mood_history, mentioned_events, habits, and interaction_prefs -- each with its own schema, enabling targeted retrieval and context building.
- **Crisis detection is deterministic**: The `evaluate_crisis_risk_tool` uses keyword matching (no LLM) to produce a 0-1 score, ensuring fast, predictable, and cost-free safety evaluations.
- **Semantic search with low overhead**: Embeddings are generated via fastembed ONNX (all-MiniLM-L6-v2) and searched in-memory with cosine similarity, avoiding the need for a vector database.
