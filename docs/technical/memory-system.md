# Memory System

## Overview

Alma's memory system gives her continuity across sessions. Unlike most chatbots that start fresh every conversation, Alma remembers your mood history, the events you've mentioned, your habits, and how you prefer to communicate.

## 4-Layer Architecture

### Layer 1: `mood_history`
Tracks emotional state over time.

```json
{
  "entry_key": "mood_2026-04-26",
  "mood_score": 7.2,
  "crisis_score": 0.1,
  "notes": "User mentioned feeling better after the weekend"
}
```

Used by `build_context_tool` to compute a mood trend line:
> "7.5/10 (↑ 1.3 pts, 3 días)"

### Layer 2: `mentioned_events`
Life events the user has referenced, with resolution tracking.

```json
{
  "entry_key": "evt_job_interview_april",
  "description": "Job interview at tech company",
  "date_mentioned": "2026-04-20",
  "resolved": false,
  "emotional_weight": 0.9
}
```

Alma proactively asks about unresolved events in follow-up sessions.

### Layer 3: `habits`
Behavioral patterns Alma observes over time.

```json
{
  "entry_key": "habit_sleep",
  "description": "Sleeps late on weekends, disrupted routine during work stress",
  "frequency": "weekly"
}
```

### Layer 4: `interaction_prefs`
Communication preferences Alma learns from the user.

```json
{
  "entry_key": "pref_length",
  "preference": "Prefers short, direct responses",
  "value": "short"
}
```

---

## Memory Write Flow

After every LLM response (non-blocking async):

```
1. Agent sends response via SSE stream → user sees it immediately
2. asyncio.create_task(post_response_work) runs in background:
   a. Extract mood score from conversation (heuristic)
   b. Detect mentioned events (keyword matching)
   c. upsert_memory_tool(user_id, "mood_history", {...})
   d. upsert_memory_tool(user_id, "mentioned_events", {...}) if event detected
   e. evaluate_crisis_risk_tool(user_id, message)
```

The `entry_key` ensures idempotent upserts — re-processing the same day's mood doesn't create duplicates.

## Memory Read Flow

At the start of every conversation turn:

```
1. build_context_tool(user_id) → markdown string
2. Injected into Claude's system prompt as:

## Contexto de {user_id}

### Estado de ánimo reciente
7.5/10 (↑ 1.3 pts, 3 días)

### Eventos mencionados (sin resolver)
- Job interview at tech company (peso: 0.9)
- Examen de cálculo (peso: 0.7)

### Hábitos observados
- Duerme tarde los fines de semana

### Preferencias de interacción
- Prefiere respuestas cortas
```

## Semantic Search

The `search_memories_tool` finds the most semantically relevant memories for a given query:

```python
# Example: user says "my boss was really unfair today"
results = search_memories("user_123", "conflict at work", k=3)
# Returns top-3 memories most similar to "conflict at work"
# across all layers, scored by cosine similarity
```

**Embedding model**: `sentence-transformers/all-MiniLM-L6-v2` via `fastembed` (local ONNX inference)
**Similarity threshold**: 0.5 (configurable)
**Search scope**: all layers for the user

## Web UI Memory Panel

The memory panel in the web chat (`#memory-panel`) calls `GET /api/v1/memory/{user_id}` after each exchange and displays the 4 layers. It appears after the first response — hidden initially so it doesn't look empty.

This makes the "Alma remembers you" moment a live, visible demo: as the conversation progresses, the panel updates in real time.
