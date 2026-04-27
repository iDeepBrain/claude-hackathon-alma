# Docker Network & Volume Map

This diagram shows the complete Docker Compose topology defined in `claude-hackathon-infra/`. It maps all 5 containers with their images, port mappings, environment variables, volume mounts, and dependency chains. The `hackathon` bridge network connects all services internally, while nginx volume mounts serve the static web frontend and its configuration file. Environment variables are loaded from per-service `.env` files in each repository directory.

```mermaid
graph TB
    subgraph COMPOSE["docker-compose.yml (claude-hackathon-infra/)"]
        direction TB

        subgraph NET["Network: hackathon (bridge)"]
            direction LR

            REDIS_C["redis\nimage: redis:7-alpine\nhealthcheck: redis-cli ping"]

            MCP_C["mcp\nbuild: ../claude-hackathon-mcp\nenv_file: ../claude-hackathon-mcp/.env\ndepends_on: (none)"]

            AGENT_C["agent\nbuild: ../claude-hackathon-agent\nenv_file: ../claude-hackathon-agent/.env\nports: 8080:8000\ndepends_on: redis✓ mcp"]

            BOT_C["telegram-bot\nbuild: ../claude-hackathon-telegram\nenv_file: ../claude-hackathon-telegram/.env\ndepends_on: agent"]

            WEB_C["web\nimage: nginx:1.25-alpine\nports: 3000:80\ndepends_on: agent"]
        end

        subgraph VOLS["Volume Mounts"]
            V1["nginx.conf → /etc/nginx/nginx.conf:ro"]
            V2["../claude-hackathon-web → /usr/share/nginx/html:ro"]
        end

        subgraph ENV["Env Variables per Service"]
            direction TB
            E1["agent:\nANTHROPIC_API_KEY\nREDIS_URL=redis://redis:6379\nMCP_URL=http://mcp:8001/mcp\nSESSION_TTL=86400\nCACHE_TTL=3600\nCACHE_THRESHOLD=0.92\nTELEGRAM_BOT_TOKEN ← NEW (proactivity)\nSCHEDULER_ENABLED=true ← NEW\nSCHEDULER_INTERVAL_H=1 ← NEW\nPROACTIVE_SEND_WINDOW=8-21 ← NEW\nMAX_PROACTIVE_PER_WEEK=3 ← NEW"]
            E2["mcp:\nMCP_PORT=8001\nDB_PATH=/app/alma.db"]
            E3["telegram-bot:\nTELEGRAM_BOT_TOKEN\nTELEGRAM_MODE=polling\nAGENT_URL=http://agent:8000"]
        end
    end

    WEB_C --> V1
    WEB_C --> V2
    AGENT_C -.->|depends| REDIS_C
    AGENT_C -.->|depends| MCP_C
    BOT_C -.->|depends| AGENT_C
    WEB_C -.->|depends| AGENT_C
```

## Key Takeaways

- **Ordered startup via depends_on**: Redis and MCP start first (no dependencies), then agent (depends on both), then telegram-bot and web (depend on agent), ensuring services are available before their consumers start.
- **Read-only volume mounts**: Both nginx mounts (config file and web assets) are `:ro`, preventing the container from modifying host files -- a security best practice.
- **Proactivity env vars in agent**: The agent service received 5 new environment variables for the proactivity feature (TELEGRAM_BOT_TOKEN, SCHEDULER_ENABLED, SCHEDULER_INTERVAL_H, PROACTIVE_SEND_WINDOW, MAX_PROACTIVE_PER_WEEK).
