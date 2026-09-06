# Decision log

Why the code is shaped the way it is.

`ROADMAP.md` used to hold this alongside a task list. The task list moved to
[GitHub issues](https://github.com/oseias-pt/incha/issues) and the
[project board](https://github.com/users/oseias-pt/projects/3) in September 2026, because keeping
both meant keeping two copies that drifted — #83 and #121 tracked the same problem twice without
either knowing about the other. The reference material moved into the issues that consume it.

What was left had no home, and it is the part that is expensive to lose: the reasoning behind
decisions that are not obvious from reading the code, and that a future contributor would otherwise
re-litigate or silently undo.

| File | Holds |
|---|---|
| [`architecture.md`](architecture.md) | Engine-wide decisions — load model, lifecycle, dispatch, dependencies, i18n |
| [`trials.md`](trials.md) | Per-trial facts — zone ids, detection strategy, encounter shape, reference addons |

## What belongs here

**Yes** — a choice with a defensible alternative, where the reasoning is not visible in the diff.
Especially: things that look wrong until you know why, and things that were tried and removed.

**No** — anything actionable. If it is work, it is an issue. If it is a fact the code states plainly
(an ability id, a constant, a function signature), the code is the source of truth and repeating it
here creates a second copy that will drift.

## Format

Each entry states what was decided, what it rules out, and what would justify revisiting it. Entries
are appended, not edited — when a decision is reversed, mark the original **Superseded** and add a
new one. The history of a reversal is usually more useful than the reversal.

Date entries. A decision that made sense against 12k lines and three trials may not against 30k and
nine.
