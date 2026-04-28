---
name: alma-memory-curator
description: Audit a specific ALMA user's memory layers (mood_history, mentioned_events, habits, interaction_prefs) for polluted records — raw test messages, timestamp suffixes, duplicated description-vs-message-vs-response_preview triples — and propose a dry-run cleanup. Never deletes without explicit confirmation; produces a diff for human review.
---

# alma-memory-curator

Audits a user's memory layers for known pollution patterns and
proposes a cleanup. Pollution typically enters via:

- **Auto-upserted exchanges** with the legacy schema
  `{description=message[:120], message, response_preview}` — three
  fields with shared prefix that render badly in the panel and inflate
  storage. The schema was changed to `{event}` in
  `chain.py:_extract_event_snippet`, but legacy records remain.
- **Test/demo timestamp suffixes** (e.g. `1777414930080`,
  `0.5683724887043067`) appended to messages during automation.
- **Duplicate identical entries** stacking from upserts that didn't
  dedupe by content.

## When to invoke

- After running automated tests against a user_id (cleans up artifacts).
- Before recording a demo (ensures the panel shows clean themes).
- During a `mateo_clean` or other demo persona refresh.
- As a portfolio walkthrough item — show that the system has tooling
  to maintain memory hygiene, not just write to it.

## What this skill does

1. **Asks for the user_id** to audit. Defaults to none — never picks
   a user without explicit input.
2. Calls `GET /api/v1/memory/{user_id}` (or queries Postgres directly
   with the user's permission) and inspects each layer.
3. Flags records matching the pollution patterns:
   - Long digit sequences in any text field (`\b\d{8,}\b`).
   - Records with `description` AND `message` AND `response_preview`
     where `description == message[:len(description)]` (legacy schema).
   - Identical content already present elsewhere in the same layer.
4. Outputs a **dry-run diff** showing which records would be removed
   or merged, with `before`/`after` previews.
5. **Stops there.** No DELETE / UPDATE without the human pasting
   "yes apply" or running the explicit `--apply` flag.

## Asymmetric-cost reminder

Memory loss is permanent. The skill biases toward FALSE-NEGATIVE in
cleanup decisions:

> Better to leave 10 polluted records than delete 1 real memory.

If a record looks ambiguous (could be real user input even if it has
a numeric tail), the default action is "skip" not "delete".

## Output shape

```
=== Memory curator — demo_mateo ===
mood_history       (7 records)   — clean
mentioned_events   (12 records)  — 4 polluted, 8 clean
  · "tengo cita medica el viernes y estoy nervioso 1777413128908"
    └─ proposed: trim digit suffix → "tengo cita medica el viernes y estoy nervioso"
  · "recordame que tengo cita medica el viernes 1777413170704"
    └─ proposed: trim digit suffix → "recordame que tengo cita medica el viernes"
  ...
habits             (3 records)   — clean
interaction_prefs  (4 records)   — clean

dry-run only. To apply, re-run with --apply or paste 'yes apply'.
```

## Files this skill reads (and may write, with consent)

- Postgres `alma_memory_layers` table (read).
- Optionally writes — only after explicit user confirmation.
