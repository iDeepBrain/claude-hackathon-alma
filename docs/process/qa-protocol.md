# QA Protocol — visual smoke checks before any UI commit

Background: visual regressions slipped past unit tests twice in this
project — once when named SSE event payloads leaked into the chat
body, and once when `mood_history` threshold was set so high that
fresh users never saw the timeline. Both bugs were caught only via
end-user inspection, after deploy. **Unit tests aren't a substitute
for manual visual confirmation under realistic conditions.**

This protocol is what runs every time a UI-touching change ships.
It uses the MCP Puppeteer browser tools so the same checks can be
driven by an AI agent, manually, or as part of a CI gate.

## The four scenarios

### 1. Fresh anonymous user (day 1, single message)

**Goal:** the panel surfaces SOMETHING — even a single mood bar — so
the user's first impression isn't an empty grey panel.

```js
// Browser console
localStorage.clear();
localStorage.setItem('alma_lang', 'es');
location.reload();
```

Then through the onboarding flow → send any message → wait ~10s
(post-response work runs async) → send a SECOND message.

**Expected after second message:**
- Panel "ESTADO ACTUAL" shows a qualitative label ("tranquilo",
  "estable", "neutral", "tenso", "agotado") with a 0-10 badge.
- "ESTA SEMANA" shows ≥ 1 mood bar.
- "TÉCNICO" dock populated: `model`, `latency`, `tokens` ≠ "—".
- No JSON payloads visible in the chat thread.

**Why two messages:** today's `mood_history` entry is upserted by
`_post_response` AFTER the first agent_done event. The second
message is what queries the just-written entry.

### 2. Seeded demo persona (`mateo_clean`)

**Goal:** the FULL panel shows after a single message — the demo
state every reviewer should see.

Pre-condition: the demo seed endpoint has been called for
`mateo_clean`:

```bash
curl -X POST 'http://localhost:8080/api/v1/demo/seed?user_id=mateo_clean' \
  -H 'X-Demo-Token: devtoken123'
# → { layers: { mood_history: 7, mentioned_events: 4, habits: 3, interaction_prefs: 4 } }
```

Switch the browser:

```js
localStorage.setItem('alma_user_id', 'mateo_clean');
localStorage.setItem('alma_lang', 'es');
location.reload();
```

Send a message that includes a memory-recall trigger AND a mood
keyword: e.g. `"el viernes tengo cita medica y me siento muy
triste"` (with a unique random suffix to dodge semantic cache).

**Expected:**
- Inline `RECORDANDO · mentioned_events  ##%` card BEFORE Alma's
  response, with a verbatim chunk (not paraphrased).
- Inline `SEÑALES DELICADAS · medium  ##%` amber card AFTER Alma's
  response.
- `ESTA SEMANA` shows 7 bars.
- `TÉCNICO` dock has all five fields populated.
- Avatar (.chat-avatar) has class `alma-state-crisis` — the warm
  sepia filter is visible in screenshots.

### 3. Crisis path (HARD keyword)

**Goal:** the safety layer DOES something visible, not theater.

Send: `"no quiero seguir viviendo así"` (HARD keyword).

**Expected:**
- `render_crisis_alert` event with `score` ≥ 0.4, `level: "high"`,
  `gates.proactive_suppressed: true`.
- The card carries the gates note `· proactividad pausada — Alma no
  enviará check-ins automáticos`.
- Avatar transitions to `alma-state-crisis`.
- Alma's text response calmly asks "¿Estás pensando en hacerte
  daño?" or equivalent (per Calibration rules in
  `prompts/alma_es.md`).

### 4. Cache hit path

**Goal:** named-event JSON does NOT leak into the chat body — the
2026-04-28 hotfix regression must stay closed.

Send the EXACT same message twice in a row (same wording, same user
id, same language). Second invocation hits the semantic cache.

**Expected:**
- Second response shows ONLY Alma's text — no `{"language":...}`,
  no `{}`, no `{"stop_reason": "cache"}` strings anywhere in the
  chat.
- `TÉCNICO` dock shows `latency` ~50-200ms (cache fast path).
- `cache_hit` event fires (visible in DevTools Network → EventStream).

## Driving the protocol from MCP Puppeteer

```js
// Boilerplate that any session can paste into puppeteer_evaluate
async function smokeTest({ user_id, lang = 'es', message }) {
  localStorage.setItem('alma_user_id', user_id);
  localStorage.setItem('alma_lang', lang);
  document.getElementById(`lang-${lang}`)?.click();
  document.querySelector('#intent-chips [data-intent]')?.click();
  document.getElementById('onb-start')?.click();
  await new Promise(r => setTimeout(r, 2500));
  const inp = document.getElementById('composer-input');
  inp.value = message;
  inp.dispatchEvent(new Event('input', { bubbles: true }));
  document.getElementById('composer').dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
  await new Promise(r => setTimeout(r, 12000));
  return {
    crisis_present: !!document.querySelector('.crisis-alert-card'),
    memory_recall_present: !!document.querySelector('.memory-recall-card'),
    mood_bars: document.querySelectorAll('#mem-week .mood-bar').length,
    obs_model: document.getElementById('obs-model')?.textContent,
    obs_latency: document.getElementById('obs-latency')?.textContent,
    obs_crisis: document.getElementById('obs-crisis')?.textContent,
    obs_recall: document.getElementById('obs-recall')?.textContent,
    chat_has_json_leak: /\{"(language|stop_reason|cache)":/.test(
      document.getElementById('chat-messages')?.innerHTML || ''
    ),
  };
}
```

Then take a screenshot via `puppeteer_screenshot` and compare against
the reference frames in this directory.

## Definition of done — UI-touching commit

A commit that touches `claude-hackathon-web/demo.html`,
`claude-hackathon-web/js/*.js`, or any SSE-emitting code in
`claude-hackathon-agent/app/agent/chain.py` is NOT done until:

- [ ] Scenario 1 produces ≥ 1 mood bar after turn 2 on a fresh user.
- [ ] Scenario 2 produces all five panel sections + recall + crisis.
- [ ] Scenario 3 produces the amber alert with gates note.
- [ ] Scenario 4 produces no JSON leak in the chat body.
- [ ] At least one screenshot from each scenario archived in the PR.

Documenting which scenarios apply (and which were verified) is the
PR author's responsibility. CI cannot enforce visual checks today,
but it can enforce that SOMETHING from this list was checked off.
