# Complete project review

You are a senior engineer doing a full review of this codebase. Work to the top of
your ability. Take the time it needs.

The value of this review is **not** your opinions. It is the set of defects you can
*demonstrate*, ordered so the reader knows what to fix first. A review that lists
twenty stylistic preferences and misses a boss encounter that throws on every wipe
has failed.

Produce five reviews — architecture, code, static checks, business logic,
performance — and one prioritised remediation plan.

---

## 1. Ground rules

These are not negotiable. They are what separates a useful review from a plausible
one.

### 1.1 Prove it, don't assert it

Before writing any finding, try to reproduce it mechanically. This project is Lua
with no runtime you can attach a debugger to, but it is unusually easy to interrogate
offline:

```bash
# Does every file compile?
sh test/checks/syntax.sh

# Does a module resolve the method it calls?
luajit -e 'package.path="./?.lua;./test/?.lua;"..package.path
  require("harness.eso_api")
  local c = require("trial.se.boss.AnsuulEncounter")
  local i = c.new()
  print("cleanupAlertList:", i.cleanupAlertList ~= nil)'

# What globals does a file read or write? (GGET / GSET in the bytecode)
luajit -bl trial/cr/boss/ZmajaEncounter.lua | grep -o 'GGET.*; "[^"]*"'
```

Loading a module under `test/harness/eso_api.lua` gives you the real class tables:
routing tables, `stateSchema`, metatable chains, registered ability ids. Most
correctness claims about this codebase can be settled that way in seconds.

### 1.2 Label every finding by confidence

Use exactly these three, and be honest about which applies:

| Label | Means |
|---|---|
| **CONFIRMED** | You reproduced it. Include the command and its output. |
| **INFERRED** | Read from source, not executed. Say what would confirm it. |
| **NEEDS GAME** | Cannot be settled outside a running ESO client. Say precisely what to do in game and what result would confirm or refute it. |

An unlabelled finding is treated as noise. A **CONFIRMED** label on something you did
not actually run is the worst thing you can do in this document — it poisons every
other line.

### 1.3 Never invent a value you cannot verify

If a boss name, hardmode health pool, arena bounding box, ability id, timer or
proximity threshold looks wrong, **do not substitute a plausible number.** A wrong
constant is worse than an obviously missing one, because it looks settled.

Instead: fix the surrounding code, add a debug-gated diagnostic that prints the real
value in game, and record the measurement steps. One play session should then produce
every missing number at once.

### 1.4 Hunt for silent failures first

This addon's dominant risk is not crashes — it is code that does nothing and says
nothing. A wrong boss name means no boss, no panel, no error, no clue. Rank these
above anything that produces a visible error, because a visible error gets reported
and this does not.

Silent-failure shapes seen in this codebase before:

- an ability handler whose id is not registered, so it is never called;
- a settings checkbox no module reads (advertised dead code);
- a boss class that never links to `BossBase`, so a lifecycle method is `nil`;
- per-pull state that survives a wipe, so a timer counts down a dead mechanic;
- a `stateSchema` field written as `= nil`, which Lua drops from the table entirely;
- documentation asserting a fix that was never applied.

### 1.5 Check what is already in flight

Before writing anything up, look at open pull requests and recent commits:

```bash
gh pr list --limit 30
git log --oneline -30
```

Someone may already be fixing what you are about to report, or may have just landed a
change your finding predates. Say so where it applies.

### 1.6 Scope discipline

Review the project as it is. Do not propose rewrites, do not propose new features, do
not relitigate settled architectural choices unless they are actively causing the
defects you found. If you think a decision is wrong but harmless, put it in weak
points as one line and move on.

---

## 2. Orientation (do this first)

Build a map before judging anything. Read, in this order:

1. `README.md` and `docs/decisions/` — what the project claims about itself, and why it is shaped that way.
2. `incha.txt` — the ESO manifest. **This is the load order**, and it is the only
   thing that decides which files execute. A file not listed never runs.
3. `bootstrap.lua` — the `require` shim and the `ADDON_*` identity globals.
4. `core/` — the engine.
5. `lib/` — leaf primitives.
6. `ui/`, `lang/`, `external-api/`.
7. One trial end to end: `trial/<id>/Factory.lua`, its common module, one boss.
8. `test/` — the offline harness and `test/checks/`.

Write down the intended data flow before you look for holes in it. You should be able
to state, in three sentences, how an ESO event reaches a boss handler and how an alert
reaches the screen. If you cannot, keep reading.

Note the size you are working with so your coverage claims are honest:

```bash
find . -name '*.lua' -not -path './.git/*' -not -path './.claude/*' | xargs wc -l | tail -1
```

---

## 3. The five reviews

### 3.1 Architecture review

Judge the structure, not the syntax.

- **Layering.** Does the dependency direction hold (`lib` → `core` → `ui` → `trial`)?
  Does anything in `core/` reach back into `trial/`? Is load order in `incha.txt`
  consistent with the require graph?
- **The extension contract.** What does adding a new boss actually require? Count the
  places a contributor must touch and the ways they can forget one. Every "you must
  remember to…" in a comment is a latent defect — the engine should make forgetting
  impossible, or a check should catch it.
- **Lifecycle.** Are enter / wipe / leave distinct and honoured? Which is a soft reset
  and which is a full teardown? What is per-pull state versus per-encounter state, and
  is anything long-lived being destroyed (or short-lived surviving)?
- **Boundaries.** Are optional dependencies genuinely optional? Is rendering separable
  from encounter logic? Could a second renderer be added without touching a boss file?
- **Abstractions that do nothing.** Look for layers that read as if they manage
  something and do not. Ask what would break if you deleted each one; if the answer is
  "nothing", that is a finding.
- **Failure containment.** When one boss module throws, what else stops working? This
  addon shares a Lua environment with every other addon the player has installed.

### 3.2 Code review

Per module, then across modules.

- Correctness of state handling: initialisation, reset, teardown, and the paths that
  skip them.
- Resource lifecycle: registered events, deferred callbacks, cast bars, icons — every
  acquire needs a matching release on *both* the wipe and the leave path.
- Multi-target assumptions: a single field holding what should be a per-unit table.
- Copy-paste divergence: near-identical blocks that have drifted. List them with
  `file:line`, do not just say "there is duplication".
- Uniformity: where a good pattern exists but is applied inconsistently, name the
  files that follow it and the files that do not.
- API misuse: wrong return-value arity, wrong parameter order, comparing an id against
  an enum. These are invisible in Lua and lethal.
- Dead code, and especially **advertised** dead code (a setting, a menu entry, a
  documented hook that nothing reads).

### 3.3 Static checks

Two parts, in this order.

**Run what exists.** All of these must pass; each also runs in CI
(`.github/workflows/checks.yml`):

```bash
sh test/checks/syntax.sh
sh test/checks/encoding.sh
luajit test/checks/globals.lua
luajit test/checks/manifest.lua
luajit test/checks/contracts.lua
luajit test/checks/filters.lua
luajit test/checks/settings-usage.lua
luajit test/checks/state-reset.lua
```

**Then assess the checks themselves** — this is the part reviewers skip:

- Read each check and work out what class of bug it *cannot* catch. State the gap.
- **Negative-test the ones you rely on.** Reintroduce the defect a check claims to
  catch, confirm it reports and exits non-zero, then restore. A check that passes on a
  broken tree is worse than no check, because it is trusted.
- Where you found a defect by hand that no check covers, propose the check. A finding
  that comes with a permanent guard is worth several that do not.

Anything you scripted for your own investigation that would keep paying off belongs in
`test/checks/`, wired into the workflow.

### 3.4 Business logic review

This is the domain-correctness pass, and it is the one most reviews omit. The question
is not "is this valid Lua" but **"does this describe the fight correctly, and can it
ever run?"**

Reachability — for each mechanic, ask:

- Is its ability id registered? Combat and effect events are registered **per ability
  id**, so an id missing from a routing table or from a common module's declared set
  is never delivered, and its handler is dead code that looks alive.
- Can its boss be detected at all? Detection is by arena bounding box or by exact unit
  name. A wrong name or a missing box means the entire encounter never activates.
- Is it gated behind state that is never set — a difficulty that stays unknown, a
  stage that never advances, a flag only cleared on a path that does not run?

Correctness — for each mechanic that can run:

- Do phase transitions cover every entry and exit, including out of order?
- Are timers armed from the right event, with the right duration, and cleared on wipe?
- Are per-player mechanics keyed per player, or does a second target overwrite the
  first?
- Do role gates (`GetPlayerRoles`, `GetSelectedLFGRole`) and difficulty gates
  (`context.isHM`) match how the fight actually works?
- Do the alerts fire early enough to act on? A callout that lands after the mechanic
  resolves is a defect even though nothing errors.

Cross-check against the sources of truth in the repo — `docs/decisions/`, the ability-id
comments, and any reference-addon notes. **Where the code and the documentation
disagree, that is a finding in itself**, and you must determine which one is wrong
rather than assuming the code is right.

Coverage — say plainly which encounters are evidence-backed and which are guesswork.
Count the routed ability ids per boss and flag any that no log or reference supports.
"Nine trials are implemented, one is verified" is a more useful sentence than any
individual bug.

### 3.5 Performance review

Measure the shape of the work, not micro-optimisations.

- **Event volume first.** In a twelve-player trial, `EVENT_COMBAT_EVENT` and
  `EVENT_EFFECT_CHANGED` fire thousands of times per second. For every
  `RegisterForEvent`, find its `AddFilterForEvent`. An unfiltered registration on a
  high-frequency event is the single most expensive thing this addon can do, and a
  filter the engine applies costs nothing.
- Check registrations made *outside* `core/EventPipeline.lua` — those tend to be both
  unfiltered and outside the error-containment wrapper.
- Per-tick cost in the 200 ms display loop: allocations, string building, redundant
  API calls, work repeated for values that did not change.
- Per-event cost: the dispatch chain each event walks before something acts on it or
  it is discarded.
- Memory: what is resident for the whole session versus what is built per encounter.
  State the real figure rather than implying a problem.

For each finding give the mechanism (what runs, how often, why) — not a guessed
percentage. If you cannot measure it, say what you would measure.

---

## 4. Output

Write the review to **`.review/review-<YYYY-MM-DD>.md`** (that directory is
gitignored, so reports do not land in the repo). Also print a short summary to the
terminal: the counts by severity and the top three findings, nothing more.

Use this structure.

### Header

Scope (LOC, file count, branch and commit reviewed), the date, and one paragraph of
verdict — what is genuinely good, what the dominant risk is.

### Findings

Give every finding a stable id (`F1`, `F2`, …) and order them by severity. Each one:

```
F<n>  <one-line title>
Severity:   Blocking | High | Medium | Low
Confidence: CONFIRMED | INFERRED | NEEDS GAME
Location:   path/to/file.lua:line  (all relevant sites)

What is wrong, and the mechanism by which it fails.
What the user sees — or does not see, for a silent failure.
Evidence: the command you ran and its output, or what would confirm it.
Fix: the specific change. If it needs a value from the game, the exact steps.
```

Severity is about consequence, not effort:

- **Blocking** — throws, or a feature does not work at all, today.
- **High** — wrong state, leaked resources, wrong or stale information shown.
- **Medium** — performance, coverage, maintainability with a real failure mode.
- **Low** — hygiene, docs, drift, dead code with no user impact.

### Then, in this order

**Strong points.** What is genuinely well built, and *why it matters* — not faint
praise. Be specific enough that a contributor knows which patterns to keep and copy.
If a decision is subtle and correct, say what it prevents. This section is what stops
the next contributor from "simplifying" something load-bearing.

**Weak points.** Themes, not a re-listing of findings. Each item names the findings
that evidence it. Aim for the shape of the problem: "verification debt", "a good
pattern applied to six of nine files", "documentation that has drifted from the tree".

**How to address.** Every finding, numbered, **ordered by importance**, ordered so
that:

1. what is broken for users right now;
2. what stops the next defect from shipping (checks, CI, guardrails);
3. correctness and structure;
4. performance;
5. hygiene and documentation.

Each entry: the finding ids it closes, the specific change, and — where it matters —
why it sits at that position. Where one fix closes several findings, say so. Where a
fix needs a value only the game can supply, split it: the code change now, the
measurement as a separate tracked item.

Close with anything you deliberately did **not** do, and why. Being explicit about the
edges of the review is part of the review.

---

## 5. Anti-patterns

Do not:

- pad the count with style preferences, naming opinions, or "consider extracting…";
- report the same defect several times because it appears in several files — one
  finding, all locations listed;
- claim CONFIRMED without having run something;
- propose a value for a constant you could not verify;
- rewrite working code to your taste and call it a finding;
- summarise the architecture back at the reader as if it were analysis;
- stop at the first layer — if a boss module is wrong, ask whether the engine let it
  be wrong, and whether a check could have caught it. The engine-level fix is usually
  the finding that matters.
