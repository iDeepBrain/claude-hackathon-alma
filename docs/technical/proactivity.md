# Proactivity System — Alma Reaches Out First

This is Alma's defining feature. Most mental health apps wait for the user. Alma doesn't.

## Why Proactivity Matters

People with depression frequently don't initiate contact even when they want to. The 3-times-daily rhythm is not arbitrary: breakfast, lunch, and dinner are natural daily anchors. A message that arrives when someone is already at their phone (eating) has a far higher chance of being read and answered than a generic daily notification.

## 3 Daily Check-Ins

APScheduler runs inside the agent service and fires three jobs per day (Lima time, UTC-5):

| Slot | Time | Message |
|------|------|---------|
| Breakfast | 08:30 | "¿Ya desayunaste? ☀️ Un buen comienzo importa" |
| Lunch | 13:30 | "¿Ya almorzaste? 🌞 ¿Cómo va tu día?" |
| Dinner | 19:30 | "¿Ya cenaste? 🌙 ¿Hiciste algo de movimiento hoy?" |
| Crisis follow-up | Immediate | Sent after crisis detection; checks in 1h later |

## APScheduler Configuration

The agent runs APScheduler with `AsyncIOScheduler` (in-process, same event loop as FastAPI):

- `Job: proactive_breakfast` — cron: hour=8, minute=30, tz=America/Lima
- `Job: proactive_lunch` — cron: hour=13, minute=30, tz=America/Lima
- `Job: proactive_dinner` — cron: hour=19, minute=30, tz=America/Lima

Proactivity is enabled/disabled via `SCHEDULER_ENABLED=true/false` env var.

## Redis Key Patterns

```
alma:chat:{tg_user_id}                       → Telegram chat_id (string)
                                               Set by telegram-bot on first message.
                                               No TTL — permanent.

alma:proactive:last:{user_id}                → Unix timestamp (string)
                                               Updated after every proactive send.

alma:proactive:slot:{user_id}:{date}:{slot}  → "1" (string)
                                               date format: YYYY-MM-DD
                                               slot values: breakfast | lunch | dinner
                                               TTL: expires at midnight Lima time.

alma:proactive:crisis_score:{user_id}        → float as string (e.g. "0.75")
                                               Updated after every message evaluation.
                                               TTL: 24 hours.
```

## Safety Gates

Before any proactive message is sent, three gates must all pass:

| Gate | Redis Key | Condition to SKIP |
|------|-----------|-------------------|
| Crisis gate | `alma:proactive:crisis_score:{user_id}` | value > 0.6 |
| Silence gate | `alma:proactive:last:{user_id}` | now - timestamp < 7200s (2h) |
| Slot gate | `alma:proactive:slot:{user_id}:{date}:{slot}` | key exists |

### Why crisis_score > 0.6 (not 0.8)?

The proactivity gate uses the "high" threshold rather than "critical" because it is precautionary — better to skip a meal check-in than to risk interrupting someone in distress. This was the `emotional-companion` agent's most important contribution in the multi-agent debate (see [Multi-Agent Methodology](../process/multi-agent-methodology.md)).

### "Silence as Self-Regulation"

A person in emotional crisis may be using silence intentionally. They may be breathing through something. Interrupting with "did you eat breakfast?" could break a fragile equilibrium. This principle was surfaced by the `emotional-companion` agent and supported by `psiquiatria-informativa`.

## Message Delivery

Proactive messages are sent **directly from the agent** via httpx to the Telegram Bot API:

```python
httpx.post(
    f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
    json={"chat_id": chat_id, "text": message_text}
)
```

The telegram-bot service is NOT involved — proactive delivery is co-located with the scheduler in the agent to avoid inter-service calls.

## End-to-End Flow

```
APScheduler fires (08:30 / 13:30 / 19:30)
    ↓
Check alma:proactive:slot:{user_id}:{date}:{slot} → already sent? skip
    ↓
Check alma:proactive:last:{user_id} → active in last 2h? skip
    ↓
Check alma:proactive:crisis_score:{user_id} → crisis_score > 0.6? skip
    ↓
GET alma:chat:{tg_user_id} → retrieve chat_id
    ↓
httpx.post(api.telegram.org/bot{token}/sendMessage, chat_id=..., text=...)
    ↓
SET alma:proactive:slot:{user_id}:{date}:{slot} = "1" (TTL 86400)
```

## Environment Variables

```
TELEGRAM_BOT_TOKEN=...           # Required — same token as telegram-bot service
SCHEDULER_ENABLED=true           # Enable/disable all proactive jobs
PROACTIVE_TZ=America/Lima        # Timezone for scheduler cron expressions
PROACTIVE_BREAKFAST_H=8          # Hour for breakfast check-in
PROACTIVE_LUNCH_H=13             # Hour for lunch check-in
PROACTIVE_DINNER_H=19            # Hour for dinner check-in
PROACTIVE_SILENCE_WINDOW_H=2     # Hours of recent activity that suppress check-in
```

## Design Constraints (12-Agent Consensus)

| Constraint | Value | Source |
|-----------|-------|--------|
| Max messages/day | 3 (one per slot) | UI/UX, María, Arthur |
| Send window | 08:00–21:00 local | María, Psiquiatría |
| Crisis gate threshold | crisis_score > 0.6 → skip | Junior MLE, Psiquiatría |
| Silence handling | Active in 2h → skip | Senior MLE, Emotional Companion |
| Tone | Short, one open question, no assumptions | UI/UX, Psiquiatría |
| Channel | Telegram only (web has no push) | ALL agents + stakeholders |
| Opt-out | /pausar command | Psiquiatría, Emotional Companion |
