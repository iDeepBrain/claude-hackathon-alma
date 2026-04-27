# Inter-Connection Parameters Summary

This diagram is a complete reference for all service connection parameters in the Alma stack. It documents the exact URLs, libraries, key patterns, payload formats, transport protocols, and trigger conditions for every connection: Agent to Redis, Agent to MCP, Agent to Telegram API (proactive), Telegram-bot to Agent (reactive), and Web/nginx to Agent (proxy). Use this as a lookup table when configuring, debugging, or extending service connections.

```mermaid
graph TB
    subgraph PARAMS["Service Connection Parameters"]
        direction TB

        subgraph A2R["Agent → Redis"]
            AR1["URL: redis://redis:6379\nLib: redis-py async\nKey patterns:\n• session:{user_id} → JSON list (TTL 24h)\n• cache:{hash} → {response, embedding} (TTL 1h)\n• alma:chat:{tg_id} → chat_id\n• alma:proactive:last:{uid} → timestamp\n• alma:proactive:count_week:{uid} → int"]
        end

        subgraph A2M["Agent → MCP"]
            AM1["URL: http://mcp:8001/mcp\nTransport: streamable_http\nLib: langchain-mcp-adapters\nTools: 5 (get_memory, search,\n upsert, build_context,\n evaluate_crisis_risk)\nCall pattern: ainvoke({user_id, ...})"]
        end

        subgraph A2T["Agent → Telegram API (proactive)"]
            AT1["URL: https://api.telegram.org/bot{TOKEN}/sendMessage\nLib: httpx async\nPayload: {chat_id: int, text: str}\nTrigger: APScheduler every 60min\nGates: crisis<0.6, cooldown>20h,\n window 8am-9pm, max 3/week"]
        end

        subgraph B2A["Telegram-bot → Agent"]
            BA1["URL: http://agent:8000/api/v1/chat\nLib: httpx async\nPayload: {user_id, message, language}\nResponse: SSE stream (data: chunk\\n\\n)\nEOF: data: [DONE]\\n\\n\nuser_id format: 'tg_{tg_user_id}'"]
        end

        subgraph W2A["Web (nginx) → Agent"]
            WA1["Proxy: location /api/ { proxy_pass http://agent:8000; }\nSSE: proxy_buffering off, proxy_read_timeout 3600s\nHeaders: COEP/COOP (SharedArrayBuffer ready)\nSame-origin: no CORS needed\nuser_id: crypto.randomUUID() in localStorage\nformat: raw UUID (no prefix)"]
        end
    end
```

## Key Takeaways

- **5 Redis key patterns**: The agent uses Redis for 5 distinct purposes (sessions, cache, chat IDs, proactive timestamps, weekly counters), each with its own key pattern and TTL policy.
- **Async everywhere**: Every outbound connection from the agent uses async libraries (redis-py async, langchain-mcp-adapters with ainvoke, httpx async), ensuring the event loop is never blocked during I/O.
- **SharedArrayBuffer-ready headers**: nginx sends COEP/COOP headers so the web frontend can use SharedArrayBuffer if needed for future WebGPU or audio processing features.
