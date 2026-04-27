# claude-hackathon-alma

Public documentation repository for the Claude Opus 4.7 hackathon. No runtime, no Docker, no server — documentation only.

## Repository Structure

```
claude-hackathon-alma/
├── README.md                           # Hero — entry point for judges
├── CLAUDE.md                           # This file (agent navigation)
├── LICENSE
├── docs/
│   ├── technical/                      # System architecture & implementation
│   │   ├── architecture.md             # 5-service system, request flows, env vars
│   │   ├── mcp-server.md             # FastMCP: 5 tools, 4-layer memory, SQLite
│   │   ├── memory-system.md          # Memory write/read/search flows
│   │   ├── crisis-detection.md       # Deterministic safety, proactivity gate
│   │   └── proactivity.md            # 3 daily check-ins, APScheduler, gates
│   ├── user/                          # End-user documentation
│   │   ├── getting-started.md        # How to use Alma on Telegram & web
│   │   └── privacy.md               # Data storage, retention, deletion
│   └── process/                       # Development methodology
│       ├── multi-agent-methodology.md # 12 agents, 2 rounds, debate outcomes
│       └── claude-code-skills.md     # Skills, hooks, CLAUDE.md infrastructure
├── diagrams/                          # Mermaid architecture diagrams
│   ├── README.md                      # Index of all 10 diagrams
│   ├── 01-global-architecture.md
│   ├── 02-inter-service-map.md
│   ├── 03-agent-internals.md
│   ├── 04-mcp-memory.md
│   ├── 05-proactivity-flow.md
│   ├── 06-web-chat-flow.md
│   ├── 07-telegram-flow.md
│   ├── 08-docker-network.md
│   ├── 09-data-flows.md
│   └── 10-connection-params.md
└── assets/                            # Screenshots, PNGs (future)
    └── .gitkeep
```

## Convention

All documentation is in **English** (international hackathon rubric).

## How to Update

Edit .md files directly. No build, no deploy. Mermaid diagrams render on GitHub.

## Pendiente

| Item | Story | Sprint | Estado |
|------|-------|--------|--------|
| URLs placeholder en README.md | STORY-009 | Sprint 02 | ✅ Reemplazado con `github.com/iDeepBrain/` |
| Grabar 4 demo videos | STORY-017 | Sprint 05 | ❌ Después de que todo funcione |

## Qué ya está completo

- README.md hero document con TOC y deep-dive links
- 5 docs técnicos, 2 docs usuario, 2 docs proceso
- 10 diagramas Mermaid individuales + index
- CLAUDE.md con tree completo
- Todos los cross-references validados (0 links rotos)

## DO NOT

- Add source code (code lives in the other 7 repos)
- Add binary files or models
- Add `.env` or secrets
- Delete or rename the directory structure without updating README.md links
