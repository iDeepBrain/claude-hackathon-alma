# Global System Architecture

All five Docker services run in a single Docker Compose on a private `hackathon` bridge network (IPv6 disabled). Only two ports are exposed to the host: port 3000 for the web frontend served by nginx, and port 8080 for direct developer access to the FastAPI agent. External dependencies are the Anthropic API (for Claude LLM calls) and the Telegram Bot API (for proactive messaging). Internal communication flows through Redis for sessions/cache and the MCP server for persistent semantic memory.

```mermaid
graph TB
    subgraph HOST["Host Machine"]
        P3000["Port 3000 (Web)"]
        P8080["Port 8080 (Dev/curl)"]
    end

    subgraph DOCKER["Docker Network: hackathon (bridge, IPv6 disabled)"]
        direction TB

        subgraph WEB["web — nginx:1.25-alpine"]
            NGINX["nginx\nServes static files\nProxy /api/* → agent:8000"]
        end

        subgraph AGENT["agent — FastAPI :8000"]
            CHAIN["AlmaChain\n(LangChain LCEL)"]
            SCHED["APScheduler\n(proactivity jobs)"]
            CACHE["SemanticCache\n(2-stage: rapidfuzz + cosine)"]
            ROUTER["ModelRouter\n(Haiku/Sonnet/Opus)"]
            GUARD["InjectionGuard"]
        end

        subgraph MCP["mcp — FastMCP :8001"]
            TOOLS["5 MCP Tools"]
            DB["SQLite: alma.db"]
            EMB["fastembed ONNX\nall-MiniLM-L6-v2"]
        end

        REDIS["redis:7-alpine :6379\nSessions + Cache\nChat ID index"]

        subgraph TG["telegram-bot — python-telegram-bot"]
            BOT["Polling loop\nHandlers: text/photo/PDF"]
        end
    end

    subgraph EXTERNAL["External Services"]
        ANTHROPIC["Anthropic API\nClaude Opus/Sonnet/Haiku"]
        TGAPI["Telegram Bot API\napi.telegram.org"]
    end

    P3000 --> NGINX
    P8080 --> AGENT

    NGINX -->|"proxy /api/*"| AGENT
    NGINX -.->|"static files"| WEB

    AGENT --> REDIS
    AGENT --> MCP
    AGENT --> ANTHROPIC
    AGENT -->|"proactive send\nhttpx POST"| TGAPI

    TG --> AGENT
    TG --> TGAPI
    TG -->|"SET alma:chat:{tg_id}"| REDIS

    MCP --> DB
    MCP --> EMB

    style DOCKER fill:#f0f7ff,stroke:#4a7fa5
    style AGENT fill:#e8f4e8,stroke:#2d7a2d
    style MCP fill:#fff3e0,stroke:#e65100
    style WEB fill:#e8eaf6,stroke:#3f51b5
    style TG fill:#e3f2fd,stroke:#1976d2
```

## Key Takeaways

- **Single Compose, minimal exposure**: All 5 services share one bridge network with only 2 host ports (3000 for users, 8080 for dev), keeping the attack surface small.
- **Agent is the hub**: The FastAPI agent is the central orchestrator — it connects to Redis, MCP, Anthropic API, and Telegram API, making it the single point through which all data flows.
- **Two external dependencies**: The system relies on exactly two external APIs (Anthropic for LLM inference, Telegram for push messaging), with everything else running locally in Docker.
