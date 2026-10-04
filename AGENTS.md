# Agent Guidelines — Incha

## Commit messages

Every commit must have a **body** — not just a subject line.

```
<type>(<scope>): <short imperative summary>

<Body: one or more paragraphs explaining WHY this change was made.
Cover the problem it solves, any constraint or measurement that drove
the decision, and any alternative that was considered and rejected.
If a number comes from an in-game observation (timer, threshold, ID),
say so. If a TODO or unverified value is left intentionally, say why.>

Co-Authored-By: ...
```

A bare subject line is not acceptable, even for a "trivial" fix — a future
reader has no context without the body.

## Code comments

Non-obvious choices need an inline `-- why:` note at the point of the code,
not just in the commit.  Examples of things that need a comment:

- Magic numbers (timer durations, health thresholds, ability IDs)
- `if` guards that look like they could be removed
- A path that is intentionally left unimplemented (say `-- deferred: <reason>`)
- TODOs: always attach an issue number (`-- TODO: #NNN <description>`)

## Ability IDs

When adding an ability ID constant, append a one-line comment on the same
line stating the combatRoute/effectRoute this ID belongs to and what action
it triggers.  Example:

```lua
local SHADOW_SPLASH = 105123  -- combatRoute: ACTION_RESULT_BEGIN → cast bar + interrupt alert
```

If the name or timing is unverified in-game, append `-- TODO: verify in-game (#NNN)`.

<!-- hermes-governance-pointer -->
## Cross-repository governance

Automated and scheduled agents: `docs/agents/HERMES-CONTRACT.md` in `sternnick/pi-agent` (contract `1.0.0`) **outranks this file** and is read at the start of every run. Delivery here is a branch plus an open pull request — never merge, never push `master`. Write mode: `branch_pr`. Before posting any artifact run `python3 scripts/hermes-governor.py preflight --file <artifact>`
