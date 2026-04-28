# ALMA Companion Suite — Claude Code plugin

Three skills shipped with the ALMA repository for engineers working
on (or evaluating) the system. Mirrors the pattern that medkit-app,
mobius, and wrench-board adopted in the Claude Opus 4.7 hackathon —
ship the developer-facing tooling alongside the product so reviewers
can audit the system, not just look at screenshots.

## Skills

| Skill | When to use |
|---|---|
| [`alma-crisis-eval`](skills/alma-crisis-eval/SKILL.md) | Run the deterministic crisis-detection case set against `claude-hackathon-mcp` and produce a precision/recall report, surfacing the documented xfail gaps. Use before any change to `tools/crisis_tools.py` or `prompts/alma_*.md`. |
| [`alma-memory-curator`](skills/alma-memory-curator/SKILL.md) | Audit a user's `mentioned_events` layer for polluted records (raw test messages, timestamp suffixes, duplicated descriptions) and propose a dry-run cleanup before applying. |
| [`alma-prompt-tuner`](skills/alma-prompt-tuner/SKILL.md) | Run the same canonical inputs through two prompt revisions side-by-side and surface diffs in tone, length, and bias-rule compliance. Use when revising `prompts/alma_es.md` or `alma_en.md`. |

## Install

From within Claude Code:

```
claude plugin add ./plugin
```

After install, the skills become invokable as
`/alma-crisis-eval`, `/alma-memory-curator`, `/alma-prompt-tuner`.

## Why ship the plugin in-repo

Three reasons:

1. **The skills depend on the repo's local state** — eval cases live in
   `claude-hackathon-mcp/eval/cases.yaml`, prompts in
   `claude-hackathon-agent/prompts/`. A standalone plugin would have to
   either bundle stale copies or do path-discovery; bundling alongside
   keeps them in sync trivially.

2. **Reviewers look here first.** When an MLE reviewer opens the repo,
   the `plugin/` directory is a strong signal that the codebase is
   maintained with care — same as a `tests/` directory or an
   `evolution.md`. medkit-app, mobius, and wrench-board all shipped
   plugin folders; not shipping one would leave portfolio polish on
   the table.

3. **Composability across sessions.** A clean install means the next
   session can pick up the safety eval, prompt tuner, or memory
   curator without re-explaining each.

## Versioning

The plugin version tracks the ALMA repo's `CITATION.cff` version. When
either the prompts schema or the eval cases schema changes
incompatibly, bump major.
