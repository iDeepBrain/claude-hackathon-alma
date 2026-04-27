# Claude Code Skills, Tools & Integrations

This document describes every Claude Code feature, plugin, MCP server, and external tool used to design and build Alma — demonstrating deep integration with the Claude Code ecosystem.

---

## Superpowers Skills

Superpowers is a Claude Code skill plugin that provides structured workflows for common development tasks. Alma used 6 skills extensively:

| Skill | Purpose | How It Was Used in Alma |
|-------|---------|------------------------|
| `superpowers:brainstorming` | Structured idea → design → spec flow with visual companion | Full architecture exploration before any implementation. Generated 2-3 approaches for each subsystem, debated trade-offs, produced validated specs |
| `superpowers:writing-plans` | Convert designs into step-by-step implementation plans | Translated debate outcomes into ordered task lists with time estimates (e.g., the 74-minute P0+P1 execution plan) |
| `superpowers:dispatching-parallel-agents` | Run multiple agents in parallel on independent tasks | Core of the 12-agent debate methodology — dispatched 6-12 agents simultaneously per cycle, each with focused scope and specific output expectations |
| `superpowers:systematic-debugging` | Root cause investigation workflow | Every bug treated as a root cause investigation, not a patch. Example: the nginx trailing slash bug was traced to `proxy_pass` URI stripping behavior |
| `superpowers:verification-before-completion` | End-to-end validation checklist | Sanity check before marking any implementation task done — caught issues like missing `.db` in `.gitignore` |
| `superpowers:requesting-code-review` | Post-implementation review with specific criteria | After each implementation phase, reviewed against the plan and coding standards |

---

## MCP Servers

Claude Code connects to MCP (Model Context Protocol) servers that extend its capabilities. Alma's development used 4 MCP servers:

### 1. Puppeteer MCP — Browser Automation

```
Server: @anthropic/mcp-puppeteer (npx)
Purpose: Automated browser testing and screenshot verification
```

| Tool | How It Was Used |
|------|----------------|
| `puppeteer_navigate` | Navigate to `localhost:3000` to verify web UI rendering |
| `puppeteer_screenshot` | Capture screenshots of chat interface, memory panel, demo flow |
| `puppeteer_click` | Test interactive elements: send button, chat input, memory panel toggle |
| `puppeteer_evaluate` | Execute JavaScript in browser to verify SSE streaming, localStorage UUID persistence |

Used to validate that the web chat (nginx → agent SSE) worked end-to-end before marking UI tasks complete.

### 2. Figma MCP — Design System Integration

```
Server: https://mcp.figma.com/mcp (HTTP-based)
Purpose: Read Figma designs, extract design tokens, generate code from mockups
```

Used during the UI/UX design phase to:
- Read the Alma web interface design from Figma
- Extract color tokens and typography for the chat UI
- Generate HTML/CSS from Figma frames for the landing page

### 3. Pixel MCP (Aseprite) — Mascot Art

```
Server: pixel-mcp (local binary)
Purpose: Create pixel art for the Alma colibrí mascot
```

| Tool | How It Was Used |
|------|----------------|
| `create_canvas` | Create sprite canvases for the hummingbird mascot |
| `draw_pixels` / `draw_contour` | Draw the colibrí character in pixel art style |
| `apply_shading` / `apply_auto_shading` | Add depth and shading to sprites |
| `get_palette` / `set_palette` | Manage color palettes matching Alma's brand |
| `export_sprite` / `export_spritesheet` | Export PNG/GIF for web assets |
| `add_frame` / `create_tag` | Create animation frames for the typing indicator |

The Alma mascot is a hummingbird (colibrí) inspired by the Nazca Lines of Peru — connecting the AI companion to Latin American cultural identity.

### 4. Claude Memory MCP (mcp-search) — Cross-Session Context

```
Server: claude-mem/mcp-search (plugin)
Purpose: Persistent observation tracking across Claude Code sessions
```

| Tool | How It Was Used |
|------|----------------|
| `get_observations` | Recall architectural decisions from previous sessions |
| `smart_outline` | Get file structure summaries without reading full files |
| `smart_search` | Find relevant past decisions by semantic query |
| `timeline` | View chronological history of all project decisions |

This is what enabled multi-session continuity — when a new Claude Code session started, the memory MCP provided context about all prior architectural debates, closed decisions, and implementation progress. Without this, each session would have started from zero.

---

## Figma CLI (`figma-ds-cli`)

A CLI tool for controlling Figma Desktop directly from Claude Code.

```bash
figma-ds-cli connect --safe          # Connect to Figma Desktop
figma-ds-cli canvas info             # Inspect canvas contents
figma-ds-cli render '<Frame>...</Frame>'  # Render JSX to Figma
figma-ds-cli tokens preset shadcn    # Apply design tokens
figma-ds-cli verify                  # Screenshot for verification
```

Used to design the Alma web interface directly from Claude Code — the AI agent could render UI components in Figma, verify them visually, and iterate without leaving the terminal.

---

## HyperFrames Skills

HyperFrames (`heygen-com/hyperframes`) provides video composition and animation creation within Claude Code.

| Skill | Purpose |
|-------|---------|
| `hyperframes` | Video composition and animation |
| `hyperframes-cli` | CLI for rendering HyperFrames |
| `hyperframes-registry` | Install and wire visual blocks |
| `website-to-hyperframes` | Convert web pages to animated video |
| `gsap` | GSAP animation library reference |
| `claude-design-hyperframes` | Brand-accurate HyperFrames for Claude Design |

Used for creating demo videos and animated presentations of the Alma architecture for the hackathon submission.

---

## Claude Code Hooks

Hooks are shell commands that execute automatically in response to Claude Code events.

### Session Start Hook
- Loads the Claude Memory MCP observations automatically
- Injects project context: 50+ observations spanning 274k+ tokens of past work
- Ensures every new conversation starts with awareness of all prior decisions

### Pre-Tool Hooks (Token Optimization)
- When reading a file that has prior observations, the hook provides a semantic summary instead of the full file content
- Reduces token consumption by ~91% on file re-reads
- Prevents context window bloat when working across 8 repositories

### Memory Persistence
- Architectural decisions saved as observations after each significant debate outcome
- Tagged by type: `🎯session`, `🔴bugfix`, `🟣feature`, `🔄refactor`, `✅change`, `🔵discovery`, `⚖️decision`
- Searchable by ID, timestamp, or semantic query

---

## CLAUDE.md as Agent Navigation Infrastructure

Every repository in the Alma stack has a `CLAUDE.md` file designed so an autonomous agent can pick it up cold — mid-session, no prior context — and immediately know what to do.

| Repository | CLAUDE.md Purpose |
|-----------|------------------|
| `claude-hackathon-infra` | 5-service orchestration, port mapping, nginx proxy, env vars per service |
| `claude-hackathon-agent` | API endpoints, AlmaChain pipeline, proactivity config, APScheduler details |
| `claude-hackathon-mcp` | 5 MCP tools, 4-layer memory, crisis tool dual usage (chain + scheduler) |
| `claude-hackathon-telegram` | Bot lifecycle, chat_id storage for proactivity, IPv6 workaround |
| `claude-hackathon-web` | JS file map (demo.js DO NOT TOUCH), SSE path, memory panel behavior |
| `claude-hackathon-alma` | Documentation-only repo, file tree, conventions |
| `claude-hackathon-experiments` | 5.9GB research sandbox, NEVER in Docker |
| `claude-hackathon-planning` | Sprint docs, NEVER in Docker |

Each CLAUDE.md contains:
- What the service does (1-line summary)
- How to start it (exact commands)
- What ports/endpoints it exposes
- What environment variables it needs
- What NOT to do (closed decisions, protected files, anti-patterns)

This enabled fully autonomous agent execution: agents could pick up tasks across sessions without human onboarding.

---

## 12-Agent Dispatch Pattern

The multi-agent debate used Claude Code's `Agent` tool with specific `subagent_type` for each specialized role:

```
ai-tech-lead               → Architecture decisions, go/no-go gates
senior-mle-engineer         → ML pipeline, model selection, embedding strategy
senior-fullstack-engineer   → API design, SSE streaming, nginx configuration
fullstack-lead              → Repo structure, Docker Compose, service boundaries
junior-mle-engineer         → Fresh ML perspectives, audio model research
junior-fullstack-dev        → Browser API patterns, modern frontend approaches
ui-ux-designer              → Emotional UX, demo flow, first-impression design
delivery-lead-agile         → Prioritization, risk management, time-boxing
emotional-companion         → Safety principles for proactive AI messaging
psiquiatria-informativa     → Clinical ethics for mental health AI applications
stakeholder-arthur          → Non-technical user perspective (male)
stakeholder-maria-usuario   → Non-technical user perspective (female, LatAm)
```

All 12 agents dispatched in parallel via Claude Code's multi-tool-call capability — a single message with 12 `Agent` tool calls, each with a focused prompt containing the debate topic and instructions to state their position. Responses were then synthesized into consensus decisions.

See [Multi-Agent Methodology](multi-agent-methodology.md) for the complete debate log with concrete examples.

---

## Tool Ecosystem Summary

```
Claude Code
├── Superpowers Skills (6)
│   ├── brainstorming
│   ├── writing-plans
│   ├── dispatching-parallel-agents
│   ├── systematic-debugging
│   ├── verification-before-completion
│   └── requesting-code-review
│
├── MCP Servers (4)
│   ├── Puppeteer — browser automation & testing
│   ├── Figma MCP — design system integration
│   ├── Pixel/Aseprite — mascot pixel art
│   └── Claude Memory — cross-session context
│
├── CLI Tools (1)
│   └── figma-ds-cli — Figma Desktop control
│
├── Skill Plugins (2)
│   ├── HyperFrames — video/animation composition
│   └── Pixel Plugin — sprite creation & export
│
├── Hooks (3)
│   ├── Session start — load memory context
│   ├── Pre-tool — token optimization
│   └── Memory persistence — save decisions
│
└── Agent Types (12)
    └── Specialized debate agents (see above)
```
