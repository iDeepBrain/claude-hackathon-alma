# Spec — How Alma Hits Portfolio Review Criteria

This document maps Alma's existing technical features to the criteria a recruiter, a CTO, or an investor uses to evaluate engineering work.

The format is borrowed from the Medkit-app submission's `spec.md`, which mapped each hackathon prize to a feature. Adapted here, it maps features to portfolio review criteria — the lens that matters now that the hackathon is closed.

---

## Criterion-to-feature mapping

| Criterion | How Alma hits it |
|---|---|
| **Engineering rigor under safety constraints** | Crisis detection is deliberately deterministic — keyword-based scoring, not an LLM. Reasons documented: latency, reproducibility, auditability, failure-safe defaults. The same `evaluate_crisis_risk_tool` is invoked by two callers (AlmaChain after each user turn + the proactive scheduler before each outbound message), one implementation, two integration points. Source: [`technical/crisis-detection.md`](technical/crisis-detection.md). |
| **Production-ready cloud architecture** | Deployed on Google Cloud Run with Cloud Scheduler-driven proactivity (replacing in-process APScheduler), Postgres + pgvector with HNSW index for semantic search, Upstash Redis for proactivity gates, custom domain via Cloud Run domain mapping. The codebase is environment-agnostic — only env vars (`DATABASE_URL`, `REDIS_URL`, `MCP_URL`, `SCHEDULER_ENABLED`) differ between local Docker and Cloud Run. Source: [`technical/deployment.md`](technical/deployment.md). |
| **Multi-agent system design** | The AlmaChain pipeline routes between Claude Opus 4.7, Haiku 4.5, and Gemini Pro (failover), with state transitions on `crisis_score` escalation. Routing logic is explicit code in `agent/llm/router.py`, not buried in prompts. Source: [`technical/architecture.md`](technical/architecture.md). |
| **Information retrieval at scale** | A four-layer memory model (`mood_history`, `mentioned_events`, `habits`, `interaction_prefs`) is stored in Postgres with pgvector and an HNSW index. Cosine similarity search is filtered by `user_id` at query time so vectors from one user never leak into another's recall. Memory writes happen after the response stream completes, asynchronously. Source: [`technical/memory-system.md`](technical/memory-system.md). |
| **Defense against LLM hallucination** | The crisis path is non-LLM. Memory retrieval returns chunks verbatim — the LLM cannot paraphrase facts about the user when citing memory. Proactive messages reference memory chunks by ID, not by paraphrase. (Server-side citation sanitizer in progress — see [`evolution.md`](evolution.md).) |
| **Observable production system** | Trace IDs are propagated through every AlmaChain step. Cloud Logging dashboards expose latency p50/p95 per endpoint, error rates, and invocation counts. Cost per conversation is calculable from token counts (the Anthropic SDK returns them per response). The post-hackathon polish surfaces these into a user-visible observability dock. |
| **Failure mode design** | Crisis detection: failure-safe `{"score": 0.0}` default if the MCP server is unreachable. LLM provider: Anthropic with Gemini failover on timeout or quota. Cloud Scheduler: idempotent via `alma_proactive_log` table — re-firing the same `(user_id, slot, date)` is safe. |
| **End-to-end reproducibility** | `docker compose up` reproduces the full five-service stack locally with a single command. The eight-repository topology is documented in `CLAUDE.md` files at every level so an autonomous agent can bring the system up cold. |
| **Test discipline** | Tests on the deterministic crisis logic do not require an LLM and run in under two seconds without network. The eval suite for LLM-coupled behavior runs separately, against captured fixtures. (Eval harness with precision/recall reporting is in progress — see [`evolution.md`](evolution.md).) |
| **Documentation as portfolio artifact** | Every repository carries a `CLAUDE.md` describing what it does, how to start it, what env vars it needs, and what NOT to do. Ten Mermaid architecture diagrams render directly on GitHub. The `docs/` tree separates technical, user, and process documentation cleanly. Source: [`process/claude-code-skills.md`](process/claude-code-skills.md). |
| **Use of Claude Code as development infrastructure** | Six Superpowers skills used in development (`brainstorming`, `writing-plans`, `dispatching-parallel-agents`, `systematic-debugging`, `verification-before-completion`, `requesting-code-review`). Four MCP servers integrated (Puppeteer, Figma, Pixel/Aseprite, Claude Memory). Twelve specialized agent types orchestrated in parallel debate cycles. Documented in [`process/claude-code-skills.md`](process/claude-code-skills.md) and [`process/multi-agent-methodology.md`](process/multi-agent-methodology.md). |

---

## Telegram bot architecture: why no phone number is needed

A frequent question from reviewers and users alike: *if Alma can write to me on Telegram, doesn't that mean she has my phone number?* No. The Telegram Bot API is built so that bots never see user phone numbers. The architecture below documents how Alma reaches the user without ever knowing their phone — and what data IS captured per outbound channel.

### When does Alma ask for a phone number?

| Channel chosen in "Mi perfil" | Phone field appears? | Why |
|---|---|---|
| **Yes, via SMS** | Yes — required (≥7 digits enables Save) | The phone IS the delivery address. There is no other way to send SMS. |
| **Yes, via Telegram** | No, never | Telegram identifies users by `chat_id` (an integer the platform assigns to the user-bot conversation). The phone is never exposed to the bot, by Telegram's design. |
| **Yes, via browser push** | No, never | The browser generates an FCM registration token (~150-character string) which IS the push delivery address. The phone is irrelevant. |
| **No, I prefer to open it myself** | No, never | No outbound channel is configured, so no delivery address is needed. |

### How the Telegram bridge works (no phone, by design)

Telegram Bot API enforces two rules at the platform level — neither can be bypassed by a bot:

1. **A bot cannot initiate a conversation with a user.** The user MUST send a message (typically `/start`) to the bot before the bot can call `sendMessage(chat_id, …)`. This is enforced by Telegram's servers.
2. **The user's phone number is never delivered to the bot.** Even after `/start`, the only identifiers the bot receives are `tg_user_id` (Telegram's internal integer) and `chat_id` (the channel for replies). No phone, no email, no real name unless the user sets one in Telegram.

Alma's Telegram bridge (`WS-D.4`) uses these guarantees as a feature, not a workaround:

```
Web app (signed in as google_<sub>)
   │
   │ User picks "Telegram" as proactive channel and clicks Save.
   ▼
POST /api/v1/users/telegram-link/token  →  Redis SET alma:tg-link:<token> = google_<sub>  (TTL 10 min)
   │
   │ Returns deep_link = https://t.me/AlmaHackathonBot?start=alma_<token>
   ▼
User clicks the link, Telegram opens the bot.
   │
   │ User sends "/start alma_<token>" (this IS the explicit consent).
   ▼
Bot's /start handler:
  • GET alma:tg-link:<token>  →  google_<sub>
  • DELETE alma:tg-link:<token>           (single-use)
  • SET alma:tg-chat-for:google_<sub> = chat_id
   │
   ▼
Proactive scheduler (Cloud Scheduler → /cron/proactive/<slot>) reads
alma:tg-chat-for:<user_id> when sending check-ins. The phone number
is not stored, not requested, not in the path.
```

The user's first `/start` is the opt-in. If they never start the bot, Alma never writes to them — the platform makes silent contact impossible. That's not a workaround for missing phone capture; it's the privacy guarantee that makes phone capture unnecessary.

---

## Why this format exists

A polished engineering portfolio is not a feature list. It is a stated argument for why the engineering decisions made are defensible.

This document exists so that when a reviewer asks "why this and not that," the answer is on file — versioned, datable, and traceable to a specific commit. The argument is checkable. That is the difference between a portfolio piece and a screenshot.

The pattern was set by Medkit-app, the top-1 winner of the Claude Opus 4.7 hackathon, whose `spec.md` mapped each prize criterion (Impact, Demo, Opus 4.7 use, Depth, Managed Agents) to a specific feature. The lesson generalizes: engineering work shipped without an articulated criterion-to-feature mapping is shipped under-explained.
