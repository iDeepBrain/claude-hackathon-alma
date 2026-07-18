# Claude Opus 4.7 Hackathon — Alma Submission

Alma was built for Anthropic's Claude Opus 4.7 Innovation Suite Hackathon (April 2026). This file documents the submission, the winners we learned from, and the post-hackathon trajectory.

The main `README.md` has been moved toward a "publication-style" voice — atemporal, suitable for a recruiter, an investor, or a clinician who has never heard of the hackathon. The hackathon-specific context lives here.

---

## What we built for the submission

Alma — a proactive emotional companion for mental health, deployed at https://alma-bot.com on Google Cloud Run.

Key technical commitments at submission time:

- Multi-agent pipeline (**AlmaChain**) routing between Claude Opus 4.7 and Haiku 4.5, with Gemini Pro as failover.
- Four-layer semantic memory in **Postgres + pgvector** with an HNSW index.
- **Deterministic crisis detection** with a dual-caller pattern (in-chain after each turn + pre-flight before each scheduled proactive message).
- Three Redis-gated daily proactive check-ins (Lima time).
- **Custom domain** via Cloud Run domain mapping.

The eight-repo system, Docker Compose orchestration, Cloud Scheduler integration, and full architecture diagrams are documented in the `docs/technical/` and `diagrams/` directories.

---

## Result

Alma did not win.

### The top three

1. **Medkit** ([repo](https://github.com/bedriyan/medkit-app)) — voice-first clinical training simulator with browser 3D, attending grader citing real medical guidelines (NICE, AHA, GINA, GOLD).
2. **Wrench-board** ([repo](https://github.com/Junkz3/wrench-board)) — agent-native diagnostic workbench for component-level electronics repair, where the agent pilots a boardview canvas via WebSocket-emitting tools.
3. **Maieutic** ([repo](https://github.com/pauvasquezh/maieutic)) — Socratic IDE that requires students to specify behavior in natural language before writing code, with an instructor cohort dashboard.

### Other notable winners (special categories)

- **Mobius** ([repo](https://github.com/leventilo/mobius)) — physics paper PDFs into interactive Ciechanowski-style simulators with an 8-dimensional scientific integrity critic.
- **Omnibridge** ([repo](https://github.com/adindamochamad/omnibridge)) — autonomous identifier of legacy serial protocols (RS-232).

---

## What we learned from them

Three patterns appeared in every winner that Alma's submission did not surface clearly:

1. **Last-mile workflow integration over chat surface.**
   Each winner is deeply embedded in a specific technical workflow — medical training, microsoldering, electronics interfacing, programming education, scientific publishing. None ship as "a chat with memory." Alma's value proposition (proactive emotional contact) was real, but the demo surface was indistinguishable from a generic Claude wrapper.

2. **Hallucination defense as visible feature.**
   Server-side sanitizers (wrench-board's regex close-list that envelopes unverified component refdes as `⟨?U999⟩`), citation registries (medkit's "cite real guidelines, don't invent" rule), deterministic engines (mobius' integrity critic checking units, conservation, claim-match). Anti-hallucination is presented as engineering rigor, not as a footnote. Alma already implements this — the dual-caller crisis pattern is exactly this kind of engineering — but it was hidden behind the chat UI.

3. **Advanced Opus 4.7 use, justified explicitly.**
   Managed Agents primitives (medkit uses six: Agent versioning, Environment with egress restrictions, Session per-shift, custom tools, permission policies, credential vault). Prompt caching with `cache_control: ephemeral` and visible cache-hit rates (omnibridge: 65% hit rate, $0.22/investigation). 1M context for full document parsing (mobius). Each repo has a "Why Opus 4.7 specifically" table that maps a model capability to a feature and what would break without it. Alma never published this table.

---

## Acknowledgements

The five winners are credited above with their public repositories. Their code, READMEs, and design documents informed Alma's post-hackathon technical direction:

- The **tools-as-UI-primitive** pattern from medkit and wrench-board (`render_vitals_chart`, `bv_highlight_component` — Claude calls a tool, the frontend renders a component or mutates a canvas).
- The **named-prompts engineering rigor** from maieutic (seven prompts in `src/lib/opus/prompts/`, 100–300 lines each, with bias rules and few-shots).
- The **AgentTracePanel blueprint** from omnibridge (765-line Svelte component streaming `thinking → tool_call → tool_result → final` with cost/token footer).
- The **"build from what you know"** narrative discipline from all four top entries (medkit's author is a physician, wrench-board's is a professional microsolderer, maieutic's is a CS faculty deputy director, omnibridge's is an industrial IoT engineer).

The post-hackathon roadmap that operationalizes these lessons lives in [`evolution.md`](evolution.md) and [`spec.md`](spec.md).
