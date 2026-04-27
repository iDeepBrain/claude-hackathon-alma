# Multi-Agent Development Methodology

Alma was designed and debated by **12 specialized Claude Code agents** before a single line of implementation was written. This document explains how that process worked, what decisions it produced, and three concrete examples where the debate changed the final architecture.

---

## The 12 Agents

| Agent | Role |
|-------|------|
| `ai-tech-lead` | Architecture decisions, go/no-go gates, bug triage |
| `senior-mle-engineer` | ML pipeline design, model selection, embedding strategy |
| `senior-fullstack-engineer` | API design, SSE streaming, nginx configuration |
| `fullstack-lead` | Repo structure, Docker Compose, service boundaries |
| `junior-mle-engineer` | Fresh ML perspectives, audio model research |
| `junior-fullstack-dev` | Browser API patterns, modern frontend approaches |
| `ui-ux-designer` | Emotional UX, demo flow, first-impression design |
| `delivery-lead-agile` | Prioritization, risk management, time-boxing |
| `emotional-companion` | Safety principles for proactive AI messaging |
| `psiquiatria-informativa` | Clinical ethics for mental health AI applications |
| `stakeholder-arthur` | Non-technical user perspective (male) |
| `stakeholder-maria-usuario` | Non-technical user perspective (female, LatAm) |

The first 8 agents participated in Round 1. All 12 participated in Round 2.

---

## Round 1 — Docker + Chat + Memory (Cycles 0–10)

Round 1 established the core architecture: Docker services, real-time chat, and persistent memory.

| Cycle | Focus |
|-------|-------|
| 0 | All 8 agents state initial positions (audio strategy, frontend architecture) |
| 1 | Convergence — Web Speech API ✓, web served from infra repo ✓, SSE as P0 ✓ |
| 2 | SSE contract, memory endpoint design, repo organization |
| 3 | `audio.js` implementation (~45 lines, Web Speech API) |
| 4 | Memory endpoint (3 files, ~25 lines) |
| 5 | Demo flow + UX (landing → `#chat-real` same page, memory panel reveals after first exchange) |
| 6 | `nginx.conf` + `docker-compose.yml` finalized |
| 7 | CLAUDE.md updates across all repos |
| 8 | Security audit (`.db` in `.gitignore`, `.env` clean) |
| 9 | Technical sanity check — nginx trailing slash bug caught |
| 10 | Delivery plan (74 min total for P0 + P1 implementation) |

---

## Round 2 — Proactivity System (Full 12-Agent Debate)

Round 2 addressed a harder question than Docker networking: **Should Alma initiate conversations?**

The full 12-agent roster debated whether, when, and how Alma should send unsolicited check-ins to users with depression. This involved technical, ethical, and product tradeoffs that required every perspective in the room.

### Key Positions

**`emotional-companion`:**
> "Silence can be self-regulation — do not interrupt a crisis with a meal check-in. A person managing acute distress may be in a fragile equilibrium. An unexpected notification could break it."

**`psiquiatria-informativa`:**
> "Three daily check-ins have an evidence base in depression treatment compliance. Skipping meals is a recognized depressive symptom. The ethical requirement here is not to suppress proactivity but to make opt-out easy and obvious."

**`stakeholder-arthur`:**
> "I'd feel genuinely cared for if Alma asks whether I ate. I forget to eat when I'm depressed. That's exactly the kind of thing a friend would notice."

**`stakeholder-maria-usuario`:**
> "As long as it doesn't spam me. A morning greeting plus asking about meals — yes. Anything beyond that becomes annoying. Three times a day is the maximum."

**`ai-tech-lead`:**
> "APScheduler inside the agent process. Direct httpx to the Telegram Bot API. We do not spin up a sixth service for this."

**`senior-mle-engineer`:**
> "Memory of past conversations combined with proactivity is real differentiation from GPT wrappers. The system remembers you skipped breakfast yesterday and follows up today. That's the demo moment."

**`delivery-lead-agile`:**
> "Three slots is correct. More than three creates churn risk. Implement after core chat works — proactivity is P1, not P0."

### Decisions from Round 2

| Decision | Result |
|----------|--------|
| Check-in frequency | 3x daily |
| Breakfast slot | 08:30 Lima time (UTC-5) |
| Lunch slot | 13:30 Lima time (UTC-5) |
| Dinner slot | 19:30 Lima time (UTC-5) — also asks about exercise |
| Delivery channel | Telegram only (web has no native push notifications) |
| Infrastructure | APScheduler inside agent process, not a separate service |
| Transport | Direct `httpx` to `api.telegram.org` (agent holds `TELEGRAM_BOT_TOKEN`) |
| Crisis gate | `crisis_score > 0.6` → suppress check-in immediately |
| Silence gate | User active in last 2h → suppress (they don't need it) |
| Slot gate | Check-in already sent today for this slot → suppress |

---

## Three Concrete Examples Where Debate Changed the Architecture

### 1. The nginx Trailing Slash Bug (Cycle 9 — `ai-tech-lead`)

During the technical sanity check in Cycle 9, the `ai-tech-lead` agent flagged a configuration error that would have been invisible until the first end-to-end integration test:

> "With `proxy_pass http://agent:8000/` (trailing slash), nginx strips the `/api/` prefix from the path before forwarding. The agent receives `/v1/chat` instead of `/api/v1/chat` and returns 404 on every request. Remove the trailing slash."

The correct configuration:
```nginx
location /api/ {
    proxy_pass http://agent:8000;  # no trailing slash
}
```

This is the kind of bug that costs an hour in production debugging. Catching it in design review cost 30 seconds.

### 2. Audio Strategy Reversed (Cycle 0 — unanimous)

Before the first debate cycle, the `junior-mle-engineer` agent proposed running Whisper (speech-to-text) and Kokoro (text-to-speech) inside Docker containers. The proposal was technically sound but practically catastrophic: the models alone would have pushed the Docker VM over 143GB.

After Cycle 0, all 8 agents reached the same conclusion independently: use the browser's native Web Speech API. Zero Docker changes. Zero model downloads. Already works on Chrome and Safari.

The junior MLE agent's reflection, recorded in the debate log:
> "I caused the 143GB Docker VM in my initial proposal. Now I understand: 'works in the browser' always beats 'is the coolest model' in a hackathon context. The constraint is real."

This reversed a major architectural decision before any code was written.

### 3. Silence as Self-Regulation (Round 2 — `emotional-companion`)

The initial proactivity proposal sent check-ins regardless of the user's current emotional state. The `emotional-companion` agent blocked this:

> "A person in emotional crisis may be using silence intentionally. They may be breathing through something. They may be waiting for the feeling to pass. Interrupting with 'did you eat breakfast?' could break a fragile equilibrium and signal that Alma doesn't understand what they just shared."

This introduced the crisis gate: before every scheduled check-in, the scheduler queries the user's last known crisis score from Redis. If `crisis_score > 0.6`, the message is suppressed entirely.

Without this debate, Alma would have sent cheerful meal reminders to users who had just expressed suicidal ideation.

---

## Claude Code Skills Used

| Skill | When |
|-------|------|
| `superpowers:brainstorming` | Before any implementation — full design space exploration |
| `superpowers:writing-plans` | Converting debate outcomes into executable implementation plan |
| `superpowers:dispatching-parallel-agents` | Running 6–12 agents simultaneously per debate cycle |
| `superpowers:systematic-debugging` | Each bug treated as root cause investigation, not a patch |
| `superpowers:verification-before-completion` | Sanity check before marking any task complete |

---

## CLAUDE.md as Navigation Infrastructure

Every repository in the Alma stack has a `CLAUDE.md` file designed so an autonomous agent can pick it up cold — mid-session, no prior context — and immediately know:

- What the service does
- How to start it locally
- What ports it exposes
- What environment variables it requires
- What it must NOT do (anti-patterns, decisions that are closed)

This is not documentation for humans. It is the memory system for the agents building and maintaining the service. In a multi-agent workflow where parallel agents pick up tasks independently, `CLAUDE.md` is the shared context that prevents contradiction and duplication.

The multi-agent development process generated the CLAUDE.md content as a byproduct of debate — every closed decision, every anti-pattern caught in review, every "do not re-debate this" note was encoded there.
