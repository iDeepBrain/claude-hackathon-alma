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

## Why this format exists

A polished engineering portfolio is not a feature list. It is a stated argument for why the engineering decisions made are defensible.

This document exists so that when a reviewer asks "why this and not that," the answer is on file — versioned, datable, and traceable to a specific commit. The argument is checkable. That is the difference between a portfolio piece and a screenshot.

The pattern was set by Medkit-app, the top-1 winner of the Claude Opus 4.7 hackathon, whose `spec.md` mapped each prize criterion (Impact, Demo, Opus 4.7 use, Depth, Managed Agents) to a specific feature. The lesson generalizes: engineering work shipped without an articulated criterion-to-feature mapping is shipped under-explained.
