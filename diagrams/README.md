# Architecture Diagrams

Visual documentation of Alma's system architecture. All diagrams use [Mermaid](https://mermaid.js.org/) and render natively on GitHub.

Designed through a [12-agent multi-agent debate](../docs/process/multi-agent-methodology.md).

## Diagram Index

| # | Diagram | Description |
|---|---------|-------------|
| 1 | [Global Architecture](01-global-architecture.md) | All 6 containers and external connections |
| 2 | [Inter-Service Map](02-inter-service-map.md) | Protocols, ports, and parameters between services |
| 3 | [Agent Internals](03-agent-internals.md) | Inside the FastAPI agent: AlmaChain, APScheduler, post-response work |
| 4 | [MCP Memory](04-mcp-memory.md) | FastMCP server: 6 tools, 4-layer memory, Postgres + pgvector + embeddings |
| 5 | [Proactivity Flow](05-proactivity-flow.md) | End-to-end proactive check-in with safety gates |
| 6 | [Web Chat Flow](06-web-chat-flow.md) | Browser → nginx → agent → Claude → SSE → browser |
| 7 | [Telegram Flow](07-telegram-flow.md) | User → bot → agent → response → user |
| 8 | [Docker Network](08-docker-network.md) | Containers, volumes, env vars, dependencies |
| 9 | [Data Flows](09-data-flows.md) | All data types: real-time, persistent, proactive, identity |
| 10 | [Connection Parameters](10-connection-params.md) | Complete reference for all service connections |

## Rendering

These diagrams render automatically on GitHub. For local rendering:

```bash
# Using mermaid-cli
npm install -g @mermaid-js/mermaid-cli
mmdc -i diagrams/01-global-architecture.md -o assets/01-global-architecture.png
```
