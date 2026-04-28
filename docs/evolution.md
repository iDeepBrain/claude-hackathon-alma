# Evolution — Technical Decision Log

This file records the architectural and engineering decisions made during Alma's development, including the paths considered and rejected. Order is roughly chronological. Each entry names the decision, the rejected alternatives, and the reasoning that resolved the tradeoff.

This document is intentionally honest about reversals — a decision log that hides its mistakes is propaganda, not engineering.

---

## SQLite + sentence-transformers → Postgres + pgvector  *(April 2026)*

**Decision:** migrate from a per-service SQLite database with locally embedded sentence-transformers to Supabase Postgres with the `pgvector` extension and an HNSW index.

**Why we rejected the original SQLite path:**

- No production-ready vector search at scale. The Python wrapper around SQLite that we had been using was fine for development but would not survive contact with concurrent writes across services.
- Container-bound: starting a new Cloud Run instance meant rebuilding the embeddings index on cold start, adding seconds to first-message latency.
- No cross-service consistency: the agent and the MCP server each had their own SQLite file, racing on writes. There was no single source of truth.

**Why pgvector won over Qdrant or Weaviate:**

- One database for both relational data (users, conversations) and vectors (memory layers). Less infrastructure to operate at the scale a portfolio project requires.
- HNSW parameters are tunable in-table (`m = 16`, `ef_construction = 64`). The same SQL query can do `WHERE user_id = $1 AND embedding <=> $2 < 0.4` in a single index seek — no multi-store join.
- Migration tooling (Alembic) was already in the agent. We did not have to introduce a second migration system for a vector store.

**What survived:** the four-layer memory schema (`mood_history`, `mentioned_events`, `habits`, `interaction_prefs`) is unchanged. Only the storage substrate moved.

---

## APScheduler → Cloud Scheduler  *(April 2026)*

**Decision:** replace the in-process APScheduler with Google Cloud Scheduler hitting `/cron/proactive/{slot}` endpoints, authenticated by an `X-Cloud-Scheduler-Token` header.

**Why we rejected APScheduler in production:**

- Cloud Run scales to zero. APScheduler timers die when the container does. The check-in that mattered would never fire because the instance was not running when the trigger time arrived.
- A second instance starting up does not know what the first instance scheduled. There is no shared timer state.
- No persistence. A missed slot is silently missed — exactly the failure mode a system whose value proposition is "always reaches out first" cannot tolerate.

**Why we kept APScheduler in local Docker:**

- Same code path runs in development without a Google account. The agent is environment-agnostic; a `SCHEDULER_ENABLED=true` env flag toggles between modes.
- Local development without external dependencies is a hard requirement for new contributors.

**Tradeoff accepted:** Cloud Scheduler costs ~$0.10/month for three daily slots in production. Acceptable.

**Idempotency:** the `alma_proactive_log` table records every successful send, keyed by `(user_id, slot, date)`. Re-firing the same slot is safe.

---

## Crisis detection: deterministic over LLM  *(March 2026)*

**Decision:** `crisis_score` is computed from a curated keyword list, not from an LLM.

This was the most contentious internal debate of the project.

**Why we rejected LLM-based crisis detection:**

- **Latency.** 100–800 ms is unacceptable for a system that gates safety messaging. The proactive scheduler must check this score before sending any check-in; an extra LLM call there adds visible cost and time.
- **Non-reproducibility.** The same message can score differently across runs. An auditor cannot certify behavior that is not deterministic.
- **Failure mode.** If the LLM is unreachable, the system has to fall back gracefully on a "not in crisis" default. That fallback is exactly the deterministic check we would write anyway. So we wrote it as the primary, not the fallback.

**The dual-caller pattern.** The same `evaluate_crisis_risk_tool` is invoked by:

1. **AlmaChain** — after each user message, asynchronously, in a `post_response_work` task that does not block the streamed response.
2. **The proactive scheduler** — before sending any check-in, synchronously, gating outbound messages.

One implementation, two integration points. Both default to `{"score": 0.0}` if the MCP server is unreachable. See [`technical/crisis-detection.md`](technical/crisis-detection.md).

**The principle that won the debate:** in a system that mediates self-harm signals, predictability beats nuance.

---

## Anthropic with Gemini failover  *(April 2026)*

**Decision:** primary LLM is Claude Opus 4.7 / Haiku 4.5 via the Anthropic SDK. The failover is Gemini Pro on timeout or quota errors.

**Why we added a failover at all:**

During an Anthropic API incident in early April, Alma went silent for proactive check-ins. A user did not receive their morning message. For a system whose value proposition is "always reaches out first," silent failure is the worst possible failure mode. Adding a second provider is not gold-plating; it is the price of the value proposition.

**Why we rejected provider abstraction layers (LangChain, LiteLLM):**

- Added abstraction surface to debug under stress.
- The two SDKs diverge in tool-use semantics and structured output, so a unified interface ends up papering over differences that matter at the safety layer.
- We control two providers. We do not need a router that supports twenty.

**Implementation:** a thin wrapper in `agent/llm/router.py` tries Anthropic first; on `httpx.TimeoutException` or rate-limit errors, retries once with Gemini. The provider used is logged in the response trace and (in the post-hackathon polish) surfaced in the observability dock.

---

## nginx `/api/*` proxy in front of agent  *(March 2026)*

**Decision:** the web frontend talks to the agent via nginx proxying `/api/*` to `agent:8000` on the Docker network — same origin, no CORS.

**Why we rejected raw CORS:**

- Three browsers, three CORS quirks. Maintaining preflight responses across browsers is a tax we did not want to pay.
- The `EventSource` API does not allow custom headers, which makes auth-via-header impossible across origins.

**The trailing-slash gotcha that cost an afternoon:**

- `proxy_pass http://agent:8000` (no trailing slash) preserves the request URI. Correct.
- `proxy_pass http://agent:8000/` (with slash) strips the URI prefix. Incorrect.

The fix is one character. The debugging session was one afternoon. The CLAUDE.md in `claude-hackathon-infra` now documents this so the next agent does not repeat the loss.

---

## Identity: `tg_{telegram_user_id}` vs UUID  *(March 2026)*

**Decision:** Telegram users are identified as `tg_{telegram_user_id}`. Web users are identified as a UUID stored in localStorage. Optional linking joins the two.

**Why we rejected forcing one identity scheme:**

- Forcing UUID on Telegram users would discard the natural identity Telegram already provides (and break proactivity targeting).
- Forcing Telegram on web users means sign-up friction. The whole bet is "no friction, the app reaches out first." Sign-up at first contact violates the principle.

**Risk we accepted:** linking is optional, so a user can have two parallel histories. The UI surfaces a "link account" affordance rather than auto-merging based on conversational cues — auto-merging risks silently joining two strangers' memories on weak inference.

---

## Pixel-art mascot first, animation later  *(April 2026)*

**Decision:** the colibrí mascot ships as static pixel art (Pixel/Aseprite MCP) for the hackathon submission. Lottie animation with state-machine reactivity is the next step, deferred to portfolio polish.

**Why pixel-art first:**

- The Pixel MCP integration was already operational. A static mascot existed and had been approved as a brand element grounded in the Nazca Lines (Peruvian cultural anchor). Shipping with what worked was faster than blocking on a Lottie pipeline.
- Static mascot does not pretend to react. A non-reactive animated mascot ("alas batiendo siempre") would have been worse than a still illustration.

**Why this is changing post-hackathon:**

- The post-mortem analysis of the winners showed that visible agent state was a recurring win pattern. The next iteration replaces the static colibrí with four Lottie states (`idle`, `processing`, `generating`, `crisis-empathy`) sync'd to AlmaChain pipeline events via SSE. See [`spec.md`](spec.md).

---

## What's next

The post-hackathon polish work is documented in [`spec.md`](spec.md) — the evolution from "submitted" to "portfolio-ready" focuses on surfacing the technical depth listed above into demo-visible engineering, without adding large new features.
