# Web Chat Request Flow (Reactive)

This sequence diagram traces a complete web chat interaction from browser to Alma and back. The browser generates a UUID for user identity (stored in localStorage), sends the message through nginx (same-origin proxy, no CORS), and receives the response as an SSE stream. The diagram covers both cache hit and cache miss paths, the full LLM streaming loop with chunk-by-chunk delivery, and the async post-response work (crisis evaluation, memory upserts, cache storage). It also shows the memory panel fetch that populates the UI sidebar.

```mermaid
sequenceDiagram
    participant BROWSER as 🌐 Browser
    participant NGINX as nginx (web:3000)
    participant AGENT as FastAPI Agent
    participant REDIS as Redis
    participant MCP as MCP Server
    participant LLM as Anthropic API

    BROWSER->>BROWSER: getUserId()<br/>(UUID from localStorage)

    BROWSER->>NGINX: POST /api/v1/chat<br/>{user_id, message, language}
    NGINX->>AGENT: proxy → POST /api/v1/chat<br/>(same path, no CORS)

    AGENT->>AGENT: InjectionGuard(message)

    AGENT->>REDIS: semantic_cache.lookup(message)
    alt cache hit (cosine > 0.92)
        REDIS-->>AGENT: cached response
        AGENT->>NGINX: SSE: data: {cached}\ndata: [DONE]
        NGINX->>BROWSER: SSE stream
    else cache miss
        AGENT->>REDIS: get session history
        AGENT->>MCP: build_context_tool(user_id)
        MCP-->>AGENT: markdown context string

        AGENT->>AGENT: ModelRouter → select Haiku/Sonnet/Opus

        AGENT->>LLM: stream(messages + context)
        loop SSE chunks
            LLM-->>AGENT: token chunk
            AGENT->>NGINX: data: chunk\n\n
            NGINX->>BROWSER: data: chunk\n\n
            BROWSER->>BROWSER: append to chat bubble
        end
        AGENT->>NGINX: data: [DONE]

        Note over AGENT: asyncio.create_task (non-blocking)
        AGENT->>REDIS: save session history
        AGENT->>MCP: evaluate_crisis_risk
        AGENT->>MCP: upsert mood_history
        AGENT->>MCP: upsert mentioned_events
        AGENT->>REDIS: cache response
    end

    BROWSER->>NGINX: GET /api/v1/memory/{user_id}
    NGINX->>AGENT: proxy
    AGENT->>MCP: get_memory_tool(user_id)
    MCP-->>AGENT: {mood_history, events, habits, prefs}
    AGENT-->>BROWSER: JSON memory → render panel
```

## Key Takeaways

- **Two-stage cache with high threshold**: The semantic cache uses a 0.92 cosine similarity threshold, meaning only near-identical questions get cached responses -- avoiding stale or mismatched answers for nuanced emotional conversations.
- **True SSE streaming end-to-end**: Tokens flow chunk-by-chunk from the Anthropic API through the agent and nginx to the browser, giving users real-time typing feedback without waiting for the full response.
- **Post-response work is fully async**: After the `[DONE]` signal, 5 background tasks (session save, crisis evaluation, mood upsert, event extraction, cache storage) run via `asyncio.create_task` without blocking the user experience.
