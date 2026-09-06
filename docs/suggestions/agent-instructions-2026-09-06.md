# Your `agents/` files, read line by line — notes and ideas from a run that followed them

> **This PR changes no behaviour and touches no file under `agents/`.** By design: the instruction files are
> yours, and the only thing we should do is tell you precisely what they produced when an agent actually
> ran them. Every paragraph below is (1) what your file says, in your order, (2) what happened when it was
> executed on `master` @ `9e29446`, (3) an idea, phrased as an idea. Take, rewrite or delete any of it.
>
> Labels follow your own convention: **measured** = a command was run on this tree; **inferred** = read
> from source, not executed.

The two files were followed as written, in full: `complete-review.md` produced the audit
(`sh test/checks/all.sh` → 10/10 green before and after), and every command in `workflow-code-review.md`
was executed verbatim. Total tree: 14,897 LOC, 80 Lua files, 9 trials, 25 boss modules.

---

# Part A — `agents/workflow-code-review.md`, in your order

### A.1 Preamble (lines 1–19) — "you run on a schedule, pick one coherent piece of work, and stop"

**Worked as intended.** "Research → evidence → test → implementation, in that order" is the reason the
audit shipped measurement requests instead of plausible boss files. The file-roles sentence (line 13–16)
is the best part of the preamble: *this file defines how you operate; the issue tracker defines what the
project needs.*

**Idea.** Add one clause to line 13 — **upstream**: the clone's `origin` is a fork whose tracker is off
(`has_issues: false`, `open_issues: 0`), so `gh issue` needs `--repo oseias-pt/incha`. Measured: without
it, §3.1's own command returns *"the 'sternnick/incha' repository has disabled issues"*.

### A.2 "The one rule" — never invent game data

**Held, and it is verifiable in the tree:** 5 files still carry `100000001` rather than a patched guess.
This rule is doing real work; nothing to add except: keep it at the top, where it is.

### A.3 §1 Evidence classification — the five classes, and "may I implement?"

**Worked.** It gave the audit a vocabulary that survives contact with a reviewer: four of the top findings
were `NEEDS GAME`/`INGAME_VERIFICATION`, which is a complete answer rather than an apology.

**Two ideas.**
- *"Acceptable evidence, strongest first"* is a ranking of sources but not a ranking of **trials**. When
  two candidates are equally evidenced, the agent picks arbitrarily. A one-line tie-breaker ("prefer the
  trial in the current milestone; then the one with the most open issues") removes a whole class of
  inconsistent daily choices.
- `BLOCKED` currently means "report and move on" — but not where to report. §5 says issues; §6 says the
  daily report. Naming one destination (issue comment, I'd guess) stops blocked items evaporating.

### A.4 §2 Priorities — "The developer edits this section" (line 68)

**The honest finding: an agent cannot derive a daily plan from it, because it is a ladder and not a
schedule.** The five priorities are individually excellent; there is no rule that maps *today* onto one of
them, so each run re-decides — and the ladder's last rung (Priority 4, implement) is the only one that
produces a visible diff, which biases every run toward writing code. Priority 1's own justification ("an
agent implementing against a harness that cannot tell whether a mechanic ever fires would manufacture
confident-looking wrong code at scale") is exactly right, and yet §2 is worded so that the agent reaches
for rung 4.

**Idea (draft, numbers deliberately blank for you):** `D1..D4` for daily, `W1..W2` for weekly, plus the
sentence *a D4 day — issues corrected and one precise measurement request filed — is a successful day.*
Full draft in §C.2 below.

### A.5 §3.1 Orient (lines 99–108)

**Measured, command by command.** `git fetch` / `git log`: fine. `gh pr list`: fine — and genuinely empty,
in both repos. `gh issue list --milestone "v0.2 — Critical fixes"`: **fails as written** (A.1) — with
`--repo` it returns 9 open issues.

The consequence matters more than the flag: an agent that sees an empty tracker applies Priority 4
correctly and does nothing. Silent nothing, which your own `complete-review.md` §1.4 ranks worst.

**Idea.** Add to this section a *duplicate gate*, one line: before writing anything up, `gh issue list
--repo oseias-pt/incha --state open` and cite the issue number. §5 already forbids duplicates ("#83 and
#121 tracked the same problem twice") — it just doesn't hand over the means. Concretely: this audit
re-derived #109, #110, #111, #118 and #119 because `gh` was absent during it and §3.1 never mentioned
issues.

### A.6 §3.2 Research — the seven things to establish, and the preferred source order

**Worked; the source order is unusually good** ("not general web results" is a sentence most projects need
and few write). The OSI note at line 130 — `OSI.PrintMyPosition()` turning "we need coordinates" into a
collection task — is the kind of thing that saves a day, and it checked out.

**Idea.** The seven bullets cover *mechanic* semantics but not **space** (arena AABBs, proximity radii) or
**magnitude** (health pools). Those two families account for most of the current `INGAME_VERIFICATION`
backlog — the blocking finding in the audit was a distance compared in the wrong unit. Making "what unit
is this number in, and is it world-space or normalised?" an eighth bullet would put a name on it. See
§C.6.

### A.7 §3.3 Log verification (lines 175–195)

**Worked, and the honesty here is exemplary:** *"the replay ran clean" does not mean your mechanic fired*.
Nothing to fix. Only: the sentence *"Until Priority 1 lands, confirm a route fired by adding a temporary
`Log.debug`"* is currently the load-bearing one — and `Log.warn`/`Log.debug` are both gated off unless
`/incha debug` is set. Worth one clause: the temporary probe must be printed with a path that actually
reaches the console, or the instruction silently produces "no output, therefore never fired".

### A.8 §3.4 Test before implementing — "never duplicate boss logic inside a test"

**Worked.** It also has an unfalsifiable edge: nothing makes anyone *prove* a new check can fail. Every
"X enforces" claim in §3.5 is a claim about a check's power, and the audit found two of them to be half
true (A.9).

**Idea.** Require the negative test **in the PR body** for any check change: "the defect reintroduced is
`<command>`; the check's output is `<output>`". See §C.5 for turning that into a check itself.

### A.9 §3.5 Implement — the invariants (the strongest section in either file)

Every invariant is correct **as an invariant**. I verified each parenthetical "(`check` enforces)" claim by
breaking the thing it guards, in a throwaway clone:

| Invariant | Check claim | Measured |
|---|---|---|
| new file must be in `incha.txt` | `manifest.lua` enforces | **Half true.** Membership: yes. **Order: no** — `lib/Throttle.lua` moved to the last line of `incha.txt`, after every file that requires it, and **all 10 checks passed**. ESO would throw on the first `require`. |
| every per-pull field reset in `onWipe` | `state-reset.lua` enforces | **Half true.** A field first assigned in a method, with no `stateSchema` entry → `state-reset: clean`, exit 0. Fields *declared* in the schema are audited; undeclared ones are invisible. |
| no new globals | `globals.lua` enforces | True — caught. |
| every setting needs a reader | `settings-usage.lua` enforces | True — caught. |
| `*Common` sets disjoint from routes | `filters.lua` enforces | True — caught, including the shadowed-key-in-constructor case, which nothing but a source scan can see. |

**Ideas, in order of value.**
- Reword the two half-true parentheticals (three lines, no behaviour change) so the agent stops believing
  it is covered where it isn't: *"`manifest.lua` enforces that every file is **listed** — the **order** is
  not checked"*, and *"`state-reset.lua` audits fields declared in `stateSchema`; declare yours there"*.
- The load-order gap is ~20 lines of Lua: replay `incha.txt` order against a `require` shim in manifest
  order and fail on the first unresolved symbol. It closes the one defect class in this whole exercise that
  **no issue in the tracker covers** and no existing check can see.
- Two cardinality/unit invariants read as obvious until they bite, and are worth an explicit line each, in
  §3.5's own register: **"a distance is in world units only at the API boundary; `MapUtils` draws in
  0–1 normalised space — never compare the two"**, and **"one debuff across N players is per-unit keyed —
  a single field is a bug the moment two people take it"**. Both are silent, both are invisible to Lua,
  both are in the audit (the blocking finding, and a `trial/rg` MT-follow-up loss).

### A.10 §3.6 Validate (lines 232–246)

**Measured:** all 10 checks pass on `master`, so the list is executable — but it lists **8** scripts and
the suite is **10**: `branch-name.sh` and `lang.lua` are missing, from both files, while `all.sh` and CI
run all 10.

**Idea.** Replace both lists with `sh test/checks/all.sh`. Its header already says it mirrors CI, it
prints `ok/FAIL` per check, and it exits non-zero — so the duplicated list can only drift, which is what
it did.

### A.11 §3.7 Commit (line 251) — "a pre-push hook rejects anything else and `master` is PR-only"

**Measured:** the branch rule and `Co-Authored-By` / PR footer conventions are followed in this PR. But
`git config --get core.hooksPath` is **unset** — so `.githooks/pre-push` never runs on a fresh clone — and
`branches/master/protection` is **404** on the fork *and* upstream, i.e. `master` is directly pushable
while `README.md:61` tells readers it is blocked. (#119, and the sentence is not a criticism of your
intent: `.githooks/pre-push` is written correctly.)

**Idea.** One sentence in §3.7: *before your first push, `git config core.hooksPath .githooks` — nothing
sets it for you.* Until branch protection exists, every "check enforces" in §3.5 means *advises*; that is
worth one clause at the end of §3.5 so no future run over-trusts a green pipeline.

### A.12 §4 In-game verification requests

**The best-specified section in either file** — the Bahsei example is executable without thinking, and it
names the exact `file:` to replace. "Batch these, one trip settles everything" is the correct
operational insight.

**Idea.** Requests are currently prose in an issue. A tiny fixed template (`trial / boss / difficulty /
needed / command / replaces`) with a `MEASUREMENTS.md`-style ledger would let one play session drain them
all and, when a number lands, `grep` for its placeholder to prove nothing was missed — the five
`100000001` sites would then be self-auditing. §9's `research/abilities/` idea is the same instinct
pointed at evidence instead of measurements.

### A.13 §5 Issue and decision-log rules (line 303)

**Worked, and the #121 anecdote (13 claimed, 5 actual) is *true today*** — I counted 5 files. The rule
"correct the issue when the tree contradicts it" is rare and right.

**Two notes.** (a) *"You may comment on them and open new ones"* — commenting works; **opening** an issue
on `oseias-pt/incha` needs write access, and the credentials here have `pull: true, push: false`. I did
**not** test a create call (deliberately — no attempted write to your tracker). So "it will 403" is
inferred, not observed. Either add the automation as a collaborator, or state the working form: *comment
upstream, detail on the fork*.
(b) `docs/decisions/` rules, including "ROADMAP.md was retired" — accurate: the file is gone, and the
reason given is the correct reason (a second copy of an ability id drifts).

### A.14 §6 Daily report (line 331)

**Worked** — eight sections is a good shape and "Never present an unverified item as complete" is the right
closing line. One mechanical problem: `DAILY_REPORT.md` is **not gitignored** (`git check-ignore` → no). So
every *successful* day leaves the tree dirty, which then pollutes the next morning's §3.1 orientation and
lets a `git commit -a` sweep a report into a feature branch.

**Idea.** Ignore it, or write it under `reviews/` (already ignored) and link it from the PR.

### A.15 §7 Autonomy boundaries

**Worked** — and this PR is inside them (branch + commit + PR; no merge, no master push, no check weakened,
no evidence touched, no invented data). Nothing to change. If anything, this section is the model of how to
write an autonomy boundary: an explicit *may* list, an explicit *must not* list, and "when uncertain,
preserve and report".

### A.16 §8 Separation of concerns

The table is genuinely useful — it is what told me where this file belongs (docs, not `agents/`). One row
would now be honest: `agents/*.md` — *how the agent operates* — **maintained by the developer; agents
propose, they do not edit.**

### A.17 §9 Roadmap for this workflow

**Item 1 (per-ability coverage) is the correct #1** and I can add evidence to your case: the audit had to
answer "is this handler reachable?" by reading routing tables by hand, 25 bosses at a time. Item 3
(evidence DB) is the biggest efficiency gain for a *scheduled* agent — measured: `research/` does not
exist yet, so a fresh run currently concludes "no evidence base" rather than "none written down".

**Idea:** mark the unbuilt items *not implemented — do not look for output here*. §3.3 already does this
for the replay runner; the same honesty in §9 prevents an agent mistaking a missing directory for missing
knowledge.

---

# Part B — `agents/complete-review.md`, in your order

### B.1 Preamble + "produce five reviews"

**Held.** "The value of this review is not your opinions; it is the set of defects you can demonstrate"
set the tone for the whole run, and the five-split forced the coverage that a single narrative review
would have skipped — the performance pass, done only because §3.5 demanded it, is what surfaced the
registration-count and dispatch-chain numbers.

### B.2 §1.1 Prove it, don't assert it

**The three recipes are the most valuable 12 lines in either file.** Loading classes under
`test/harness/eso_api.lua` settled most correctness claims in seconds; the `luajit -bl` + `GGET` grep found
globals-by-reading that no static check would flag. No change; only: keep the recipes inline — moving them
to `test/README.md` would make them one hop away from being skipped.

### B.3 §1.2 Labels — CONFIRMED / INFERRED / NEEDS GAME

**Worked perfectly, and it self-enforced.** The label discipline is what made me count files rather than
adjectives, and it made the audit say "measurement request" in exactly the places where guessing would
have looked more impressive.

### B.4 §1.3 Never invent a value

**Followed.** Everything unverifiable in the audit became a §4-style request block, no plausible numbers
substituted.

### B.5 §1.4 Hunt for silent failures — the six shapes

**Five of six reproduced in this tree.** A catalogue like this belongs at the top of a review file, and
this is the reason the audit's blocking finding (a proximity callout that never fires, in the wrong unit)
was looked for at all.

**Idea:** add the two shapes that bit here and are not in the list — *a distance compared across unit
systems* and *one field holding N players' state*. Both are silent, both look like working code.

### B.6 §1.5 Check what is already in flight (line 91)

**Executed literally** — `gh pr list` (empty, correct) and `git log`. The gap is the one in A.5: no
issue list, so 34 open issues were invisible to the step whose purpose is to prevent duplicated analysis.
The audit consequently re-derived #109/#110/#111/#118/#119; the reconciliation table in the audit report
lists that honestly. **Idea:** one added command line (§A.5) and the sentence *"cite the issue instead of
reporting it again"*.

### B.7 §1.6 Scope discipline — "an engine should make forgetting impossible, or a check should catch it"

**The most productive sentence in the file.** It is what turns "a boss file is wrong" into "the engine let
it be wrong" — the same instinct as the anti-patterns list at §5, and the reason several audit findings are
check proposals rather than patches.

### B.8 §2 Orientation, 8 steps + the LOC command

**Worked; step 2 is doing real work.** *"`incha.txt` — this is the load order, and it is the only thing that
decides which files execute."* True, and — measured — **nothing checks the order**. The orientation already
tells a reviewer exactly where the gap lives; §A.9's load-order check is that observation made permanent.

### B.9 §3.1 Architecture — layering, the extension contract, "you must remember to… = latent defect"

**The extension-contract question is the right one** and produced the most transferable number in the
audit: places a contributor must touch per boss, and the ways they can forget one. Nothing to change.

### B.10 §3.2 Code review — including *"a single field holding what should be a per-unit table"*

**This bullet paid for itself** — it is the exact shape of one audit finding, found by looking for the
pattern your file named. Same for "copy-paste divergence with `file:line`" (forced listing sites instead
of complaining) and "advertised dead code".

**Idea:** §3.2 lists cardinality but not **unit**; a half-line naming the two coordinate systems would
make the blocking class findable by grep-and-compare rather than by insight.

### B.11 §3.3 Static checks — run them, then *assess the checks*, negative-test them

**The most valuable section in the file.** Negative-testing is what separated the useful claims from the
confident ones, and it is how the two half-true "enforces" claims (A.9) were caught at all — a reviewer who
only *ran* the suite would have reported them as covered.

**Idea:** make the gap register permanent rather than re-derived per review — a table, one row per check,
"what this class of bug escapes me", updated whenever a check is touched. §C.3.

### B.12 §3.4 Business logic — reachability first ("can this mechanic ever run?")

**Correct order, and it found real things:** registration/reachability produced most of the
`CONFIRMED`-by-inspection findings, and *"where code and documentation disagree, that is a finding in
itself"* is the discipline that keeps a reviewer from quietly assuming the code is right. The trials doc's
"implemented ≠ verified" honesty is what made the coverage paragraph writable.

### B.13 §3.5 Performance — event volume first, filters, the 200 ms loop, registrations outside the pipeline

**Measured and useful:** the filter question ("for every `RegisterForEvent`, find its `AddFilterForEvent`")
is the right first question for this addon, and the "outside the pipeline" note is the right second — the
audit found registrations outside the error-containment wrapper exactly where §3.5 pointed, plus two
per-tick paths that recompute unchanged values. "State the real figure rather than implying a problem"
forced actual counts instead of adjectives.

### B.14 §4 Output — the format, the severity ladder, `.review/review-<date>.md` (line 267)

**The finding template is excellent** — id / severity / confidence / location / mechanism / user-visible
effect / evidence / fix. Reusing it here is what makes the audit readable at all.
Two mechanical items: the directory is now `reviews/` (`.gitignore:19`; `.review/` is not ignored, so
following the line literally yields a folder `git status` offers to commit), and the §3.3 command list is
8 of 10 (A.10).

### B.15 §5 Anti-patterns — "the engine-level fix is usually the finding that matters"

**Kept the review honest:** no style padding, one finding per defect with all sites listed, no invented
constants, no summarising the architecture back as analysis. The last bullet is the one I would keep
bolded — it is what pushed several findings from "fix this line" to "add this check".

---

# Part C — Ideas not attached to one line (workflow level)

**C.1 A duplicate gate before writing anything up.** One command + one rule ("cite the issue or don't
report it"). §5 wants this outcome; nothing produces it. Cheapest change in this document.

**C.2 A paste-able §2 (daily/weekly + definition of done).** The priorities are a ladder; a scheduled run
needs a schedule. Draft:

```markdown
**Daily** — first *unblocked* line, ≤1 branch, ≤1 PR:
  D1 code-only `v0.2` issue (no game value needed)          → #___
  D2 one increment of Priority-1 coverage/snapshots         → #110 is the cheap prerequisite
  D3 research for trial marked In progress: ___
  D4 all blocked → correct/file issues + ONE measurement request. A D4 day is a SUCCESSFUL day.
**Weekly** — one deliverable a daily run cannot produce:
  W1 one consolidated in-game request for ONE trial: ___
  W2 one tracker pass: close stale, correct what the tree contradicts (§5).
**Done means** — code: `sh test/checks/all.sh` green + evidence class stated in the PR.
  check work: the new check FAILS on a deliberately broken tree (show it in the PR body).
  measurement request: executes without thinking.
**Capacity** — game measurements arrive ≈ ___/month; don't queue more open INGAME_VERIFICATION items.
```

**C.3 A permanent check-gap register.** One table, one row per check: *what escapes me*. §3.3 asks every
reviewer to derive it and nothing keeps the answer. Two of ten rows are already known (manifest order,
state-reset's undeclared fields); the other eight are unexamined.

**C.4 A check that checks the documentation.** Both files assert invariants with "(x.lua enforces)"
parentheticals; both drift (8→10 scripts, two half-true claims, `.review/`). A 40-line check that fails
when a listed command doesn't exist, or when the file lists a subset of `all.sh`, converts prose into
something CI can keep honest. Cheap, and it is the only idea here that protects the *instructions* rather
than the code.

**C.5 Negative tests as fixtures.** If every check carries a tiny `test/negative/<name>.lua` that must make
it fail, then "X enforces Y" stops being a claim. This operationalises §3.4's best rule and A.8's gap in
one move.

**C.6 One line on coordinate systems.** ESO positions are world units at the API boundary; the draw layer
is 0–1 normalised. The blocking finding in the audit is exactly these two meeting in a comparison. A named
convention in §3.5 makes it a reviewable fact instead of tribal knowledge.

**C.7 Cardinality as an explicit invariant.** Already implicit in A.9/§3.2 ("per-player mechanics are keyed
per player"); extend it to *per-unit* (MT follows, chains, tethers) — one field for N units is silent and
looks fine in solo logs.

**C.8 Make `all.sh` the single source of truth** for both check lists, so the docs cannot silently
understate the suite again.

**C.9 Name the fork/upstream split once** (tracker upstream, code on the fork, `pull` vs `admin`
permissions), because three separate instruction lines (§3.1, §5, §8) are subtly wrong without it.

**C.10 State what a successful day is** — C.2's `D4` line. Your own preamble already says a research day
with an evidence trail is a good day; the ladder is what makes runs forget it.

---

# Part D — What this PR deliberately does not do

- **No edit under `agents/`.** Those files are yours; we propose, you reshape. Nothing here is a patch.
- **No behaviour changed**, no check touched, no log or fixture touched, nothing merged, `master` untouched.
- **No write attempted to `oseias-pt/incha`** — reads only; the 403 expectation in A.13 is inferred from
  permission fields, not tested.
- **No game data invented.** The 5 `100000001` placeholders are still placeholders, and the audit's answer
  for each is a request block, not a number.

**Three things we would need from you, none of them a doc edit:** (1) whether the automation may open
upstream issues or only comment; (2) the trial order / cadence numbers for C.2; (3) branch protection on
`master`, which is what separates "the checks enforce" from "the checks advise".
