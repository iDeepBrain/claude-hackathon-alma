# Inter-Service Communication Map

This diagram details the protocols, ports, and specific parameters for every service-to-service connection in the Alma stack. Each arrow is annotated with the transport protocol, URL paths, key configuration values, and data formats exchanged. This serves as a quick reference for developers needing to understand how services discover and communicate with each other.

```mermaid
graph LR
    subgraph PARAMS["Connection Parameters"]
        direction TB

        WEB["web (nginx)\nPort: 3000→80\nImage: nginx:1.25-alpine"]
        AGENT["agent (FastAPI)\nPort: 8080→8000 (dev)\nInternal: agent:8000"]
        MCP["mcp (FastMCP)\nInternal: mcp:8001\nTransport: streamable_http"]
        REDIS["redis\nInternal: redis:6379\nMax: 256MB LRU"]
        BOT["telegram-bot\nNo external port\nMode: polling"]
    end

    WEB -->|"HTTP proxy\nProxy-pass: http://agent:8000\nSSE: proxy_read_timeout 3600s\nHeaders: COEP/COOP"| AGENT

    AGENT -->|"HTTP/JSON + SSE\nPOST /api/v1/chat\nGET /api/v1/memory/{user_id}\nPOST /api/v1/trigger"| AGENT

    AGENT -->|"Redis protocol\nSET/GET/JSON\nTTL: 24h sessions\nTTL: 1h cache"| REDIS

    AGENT -->|"MCP streamable_http\nPOST http://mcp:8001/mcp\nTools: get_memory, search,\nupsert, build_context,\nevaluate_crisis_risk"| MCP

    BOT -->|"HTTP/SSE\nPOST http://agent:8000/api/v1/chat\nSSE stream parsing"| AGENT

    BOT -->|"Redis SET\nalma:chat:{tg_user_id} = chat_id\n(on first message)"| REDIS

    AGENT -->|"httpx POST\napi.telegram.org/bot{TOKEN}/sendMessage\n{chat_id, text}\n(proactive only)"| EXT["Telegram API"]
```

## Key Takeaways

- **Same-origin proxy eliminates CORS**: nginx proxies `/api/*` to the agent on the same origin, so the browser never triggers CORS preflight requests.
- **SSE requires special nginx config**: The proxy uses `proxy_buffering off` and a 3600s read timeout to support long-lived SSE streams without premature disconnection.
- **MCP uses streamable HTTP transport**: The agent communicates with the MCP server via `streamable_http` (not stdio), posting to `http://mcp:8001/mcp` for all 5 memory tools.
