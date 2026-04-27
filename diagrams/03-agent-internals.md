# Agent Internal Architecture

This diagram shows the internal structure of the FastAPI agent (`claude-hackathon-agent`), the core orchestration service. It breaks down the API layer (4 endpoints), the AlmaChain pipeline (guard, cache, context, routing, LLM streaming, SSE), the post-response async work (6 background tasks), the APScheduler proactivity system, and the shared application state. The agent is the most complex service in the stack and handles both reactive (user-initiated) and proactive (system-initiated) flows.

```mermaid
graph TD
    subgraph AGENT["FastAPI Agent (app/)"]
        direction TB

        subgraph API["API Layer (app/api/)"]
            CHAT_EP["POST /api/v1/chat"]
            MEM_EP["GET /api/v1/memory/{user_id}"]
            TRIG_EP["POST /api/v1/trigger"]
            HEALTH["GET /health"]
        end

        subgraph CHAIN["AlmaChain (app/agent/chain.py)"]
            direction LR
            G["InjectionGuard"] --> SC["SemanticCache\nlookup"]
            SC -->|"miss"| CTX["build_context\n(MCP)"]
            CTX --> ROUTE["ModelRouter\nHaiku/Sonnet/Opus"]
            ROUTE --> LLM["LLM Stream\nAnthropics SDK"]
            LLM --> SSE["SSE Response"]
            LLM --> POST["post_response_work\n(async task)"]
        end

        subgraph POST_WORK["Post-Response (async, non-blocking)"]
            direction TB
            T1["trim_history\n(max 40 msgs)"]
            T2["evaluate_crisis_risk\n(MCP tool)"]
            T3["state_transition\nonboarding→chat→crisis"]
            T4["upsert mood_history\n(MCP)"]
            T5["upsert mentioned_events\n(MCP)"]
            T6["cache_response\n(Redis)"]
        end

        subgraph SCHED["APScheduler (startup)"]
            direction LR
            JOB["check_proactive_queue\nevery 60 min"]
            JOB --> EVAL["Evaluate per user:\n- last_interaction > 24h?\n- last_proactive > 20h?\n- crisis_score < 0.6?\n- in send window 8am-9pm?"]
            EVAL -->|"yes"| GEN["Generate proactive msg\n(Haiku + special prompt)"]
            GEN --> SEND["httpx POST\nTelegram Bot API\n/sendMessage"]
        end

        subgraph STORE["State (app.state)"]
            S1["mcp_client"]
            S2["session_store (Redis)"]
            S3["cache (Redis)"]
            S4["alma_chain"]
        end
    end

    CHAT_EP --> CHAIN
    TRIG_EP --> CHAIN
    MEM_EP --> S1
    POST --> POST_WORK
```

## Key Takeaways

- **Pipeline architecture**: Every message flows through a strict pipeline: InjectionGuard, SemanticCache lookup, MCP context building, model routing, LLM streaming, and SSE delivery -- ensuring consistent safety and performance.
- **Non-blocking post-response work**: After streaming the response, 6 background tasks run asynchronously (crisis evaluation, memory upserts, cache storage, history trimming) without blocking the user's SSE stream.
- **Proactivity lives in the agent**: APScheduler runs inside the same FastAPI process, evaluating users every 60 minutes against 4 safety gates before sending proactive messages via Telegram.
