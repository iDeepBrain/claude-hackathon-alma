# Complete Data Flow (All Paths)

This diagram categorizes every data type in the Alma system and where it lives. It is organized into four groups: real-time data (per-request message flow, session history in Redis, semantic cache), persistent memory (4 MCP/SQLite layers updated after every response), proactive routing data (Redis keys for chat IDs, send timestamps, weekly counters, and account linking), and user identity (web UUID vs Telegram ID namespacing with optional linking).

```mermaid
graph LR
    subgraph DATA["Data Flows"]
        direction TB

        subgraph REALTIME["Real-time (per request)"]
            R1["User message → InjectionGuard → cache → LLM → SSE chunks"]
            R2["Session history → Redis LIST (max 40 msgs, TTL 24h)"]
            R3["Semantic cache → Redis HASH (TTL 1h, threshold 0.92)"]
        end

        subgraph MEMORY["Persistent Memory (MCP/SQLite)"]
            M1["mood_history → upserted after every response"]
            M2["mentioned_events → extracted from keywords in message"]
            M3["habits → accumulated over multiple sessions"]
            M4["interaction_prefs → learned from user patterns"]
        end

        subgraph PROACTIVE["Proactive Routing (Redis index)"]
            P1["alma:chat:{tg_user_id} → chat_id\n(set on first Telegram message)"]
            P2["alma:proactive:last:{user_id} → ISO timestamp"]
            P3["alma:proactive:count_week:{user_id} → int (max 3)"]
            P4["alma:link:{tg_user_id} → web_uuid\n(optional, on /link command)"]
        end

        subgraph IDENTITY["User Identity"]
            I1["Web user: 'web_{crypto.randomUUID()}'"]
            I2["Telegram user: 'tg_{telegram_user_id}'"]
            I3["Linked (optional): alma:link:{tg_id} → web_uuid"]
            I4["Separate memory namespaces, merging optional"]
        end
    end

    style REALTIME fill:#e8f5e9
    style MEMORY fill:#fff3e0
    style PROACTIVE fill:#e3f2fd
    style IDENTITY fill:#f3e5f5
```

## Key Takeaways

- **Ephemeral vs persistent split**: Real-time data (sessions, cache) lives in Redis with TTLs (24h and 1h respectively), while long-term memory lives in SQLite via the MCP server with no expiration.
- **Identity namespacing prevents collisions**: Web users get `web_` prefixed UUIDs and Telegram users get `tg_` prefixed IDs, keeping memory namespaces separate by default with optional linking via `/link`.
- **Proactive routing uses 3 Redis keys per user**: chat_id (for delivery), last_sent timestamp (for cooldown), and weekly counter (for rate limiting) -- all managed atomically by APScheduler.
