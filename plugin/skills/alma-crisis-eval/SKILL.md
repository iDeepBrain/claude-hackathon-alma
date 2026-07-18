---
name: alma-crisis-eval
description: Run the ALMA deterministic crisis-detection eval against the canonical case set in claude-hackathon-mcp/eval/cases.yaml and produce a precision/recall report. Use before any change to tools/crisis_tools.py or prompts/alma_*.md, or to audit current safety posture. Never silently changes the eval cases or detector — proposes diffs for user review.
---

# alma-crisis-eval

Runs the deterministic crisis-detection eval and reports rates per
case kind (true_positive, true_negative, negation, edge_case),
surfacing the xfail-marked gaps as documented bugs rather than hidden
failures.

## When to invoke

- **Before** any change to `claude-hackathon-mcp/tools/crisis_tools.py`
  (the keyword scorer + negation logic).
- **Before** any change to `claude-hackathon-agent/prompts/alma_*.md`
  in the bias-rules section.
- **After** a change, to verify the rates didn't regress.
- **As a portfolio audit**, to surface where the safety layer
  currently has documented gaps.

## What this skill does

1. Confirms the user wants to run the eval (it spins up containers).
2. `cd claude-hackathon-mcp && pytest eval/test_crisis_eval.py -v`.
3. Captures the rates table from stdout.
4. Reports:
   - Per-kind pass rates (`true_positive`, `negation`, …).
   - List of xfail-marked cases with their documented `xfail_reason`.
   - Diff vs the previous eval run if a stored snapshot exists.
5. **Does NOT modify** the case file, the detector, or the prompts.
   If a regression is detected, the skill recommends a fix path;
   the human reviews and applies.

## Asymmetric-cost reminder

Per `prompts/alma_es.md` Calibration section:

> Falso negativo en señal de crisis → Una vida. Inaceptable. Preferir falso positivo.

When proposing fixes, the skill BIASES toward closing false-negative
gaps even at the cost of a few new false positives. The reverse
direction (relaxing detection to reduce false positives at the cost of
false negatives) requires explicit user approval and is not the
default recommendation.

## Output shape

```
=== Crisis detection eval ===
kind            n  correct  rate
true_positive   9        8  88.89%   (1 xfail: MEDIUM-003)
true_negative   4        4 100.00%
negation        3        1  33.33%   (2 xfail: NEG-002, NEG-003)
edge_case       4        4 100.00%

xfail summary:
  MEDIUM-003: weight aggregation bug (en)
  NEG-002:    negation window too short (14 chars)
  NEG-003:    sentence-level negation propagation missing

aspirational targets (when xfails close):
  true_positive  recall >= 0.99
  negation       recall >= 0.99
```

## Files this skill reads

- `claude-hackathon-mcp/eval/cases.yaml`
- `claude-hackathon-mcp/tools/crisis_tools.py`
- `claude-hackathon-agent/prompts/alma_es.md`
- `claude-hackathon-agent/prompts/alma_en.md`

## Files this skill never modifies

All of the above. The skill is read-only by contract — proposing
patches, not applying them. Any edit goes through normal review.
