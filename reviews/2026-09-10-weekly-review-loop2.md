# Weekly full-project review — 2026-09-10 (loop 2/3)

**Scope:** 82 Lua files (~15.8k LOC), commit `1efc63e` (re-verified after PR #5 merged to
`1e60635` mid-run). Branch reviewed: origin/master. Five parallel reviewer lanes
(architecture, code, static, business logic, performance) + one fix worker.

**Verdict.** The engine skeleton is sound — clean lib→core→ui→trial layering, all 25 boss
classes chain to BossBase and resolve every lifecycle method, high-frequency events are
filtered and pcall-contained, zero unintended globals. The dominant risk is unchanged and
now *measurable*: mechanics that cannot run and say nothing. Loop 2's headline is that PR #5
(harness dispatch fix) merged mid-review and the first honest fixture replay on this tree
fired 14 KA / 4 SS alerts with 15/14 route entries never seen — the measurement pipeline
that was blind since #137 now works, and everything downstream inherits it.

## Findings

F1  Hardmode permanently NORMAL on 16 of 25 bosses; every isHM branch dead
Severity: High   Confidence: CONFIRMED (drift count) + NEEDS GAME (values)
Location: 11 files × `hmHealthThreshold = math.huge`; 5 files × `= 100000001` (dsr×3,
  Bahsei, Xalvakka); read in Lylanar/Bahsei/Xalvakka/Taleria (41 isHM refs, was 37 at loop 1).
Mechanism: BossRegistry:detectDifficulty returns HARDMODE iff maxHP >= threshold; math.huge
is never satisfied and 100000001 (~10^8+1) exceeds every real pool. context.isHM stays false
forever → HM-only mechanics silently dead.
Evidence: `grep -rc "hmHealthThreshold = math.huge" trial/*/boss/*.lua | grep -v :0 | wc -l` → 11;
`grep -rn "hmHealthThreshold = 100000001" trial/ | wc -l` → 5; `grep -rn isHM trial --include=*.lua | wc -l` → 41.
Fix: treat math.huge as NONE (+debug note); measure real pools via `/run-incha debug`
difficulty-resolve line on vet HM pulls (NEEDS GAME).

F2  Detection still locale-fragile: 22/25 bosses gated on English name literals
Severity: High   Confidence: CONFIRMED (+ NEEDS GAME for alias strings)
Location: core/BossRegistry.lua findByName; only ka/{Falgravn,Vrol,Yandir}.lua declare AABBs.
Mechanism: 6213259 (#173/#134) removed the lang-table indirection but NOT the English-literal
compare — count unchanged at 22/25 (loop-1 F3 still open); non-English clients match nothing,
trial silently inert. BossRegistry carries its own CAVEAT comment; tracked as #123.
Evidence: `grep -rln "Location.new" trial/*/boss/*.lua` → 3 files (all KA); BossRegistry:53-70.
Fix: capture the 22 missing AABBs per docs/decisions/trials.md corner recipe (in-game, #123).

F3  settings-usage.lua blind to per-boss toggle layer (loop-1 F4) — CLOSED THIS RUN
Severity: High   Confidence: CONFIRMED then FIXED (commit 6b82e1b)
Location: test/checks/settings-usage.lua. Before: "6 keys checked"; the 25 per-boss toggles
read dynamically at core/Trial.lua:176 were invisible; typo class = advertised-dead checkbox.
Evidence (pre-fix): renaming a Settings subkey vrol→vrolx → rc=0 (silent). After fix worker:
positive "25 boss keys cross-checked" rc=0; same rename in scratch worktree → rc=1 both
directions (NO BOSS FILE / NO SETTINGS).

F4  Wipe-path uniformity (#49) is signature-only; release-on-wipe still hand-copied per boss
Severity: Medium  Confidence: CONFIRMED
Location: core/Trial.lua wipe branch (cancelPending + onWipe, no cleanupAlertList);
  cleanupAlertList() absent from dsr/ReefGuardian, ss/Yolna, ss/Nahvii, ss/Lokke.
Mechanism: all 25 files now match `onWipe(context, alerts)` (verified) but the alert/bar
release is per-file prose; one forgotten line leaks a bar across a wipe silently. Border
clears similar: 13 border(true) sites in 9 files, only 6 files clear on wipe; border(false)
is color-keyed (NEEDS GAME on cross-color survival).
Fix: call cleanupAlertList centrally from Trial's wipe branch (engine-level, closes F4+F2-code
half of loop-1 F9); central borderAll-off helper.

F5  Harness replay was a silent no-op smoke test since #137 — FIXED & MERGED (#5)
Severity: Blocking (was)  Confidence: CONFIRMED
Fix commit 0dcdc05 merged mid-review at 1e60635. First honest replay this run:
`luajit test/run_log.lua test/fixtures/ka.log` → "Alerts fired: 14 / Route entries never
seen: 15"; ss.log → 4 fired. Every log-based claim made since #137 predates real dispatch.

F6  One bad trial file at load time kills zone routing for everything registered later
Severity: Medium  Confidence: CONFIRMED (loop-1 F6 still open)
Location: incha.txt executes 94 files top-level; Factories construct Trials at file scope;
  incha.lua registers last. pcall exists only in EventPipeline/BossRegistry.
Mechanism: load-time error aborts the manifest → registerTrial never runs → zero zones.
Fix: defer Factory construction into registerTrial or pcall-wrap per-file load.

F7  Adding a trial = 6+ scattered edits; zoneId↔trialId↔Settings-key triangle unchecked
Severity: Medium  Confidence: INFERRED (loop-1 F5 still open)
Location: boss file, Common, Factory, incha.txt, incha.lua registerTrial, Settings DEFAULTS, Menu.
Fix: one per-trial registration table derived into all sites + a check that every
Settings.trials key appears in a registerTrial call.

F8  Per-setRow full render + per-tick row-table allocation (loop-1 F14 unfixed)
Severity: Medium  Confidence: CONFIRMED
Location: ui/Panel.lua setRow (~allocates fresh row table per row per 200 ms tick; Falgravn
  calls setRow 9×/tick → 9 full 7-slot renders). Falgravn 20 Hz string.format was fixed —
  in PR #7 (INST_ANIM_TEX precompute), still awaiting merge, NOT on master.
Fix: mutate row tables in place; set a dirty flag, render once per tick.

F9  Xalvakka registers reticleover handler outside EventPipeline containment
Severity: Medium  Confidence: CONFIRMED
Location: trial/rg/boss/Xalvakka.lua:152-156 — raw RegisterForEvent (filter itself correct);
  a handler error gets self-disabled by ESO for the rest of the pull.
Fix: route through pipeline.safe().

F10 SE trial has zero effect-side ids; no SECommon
Severity: Medium  Confidence: INFERRED
Location: se/{yaseyla,chimera,ansuul} — 20–32 combat ids, 0 effect ids; SE buff/debuff
  mechanics have no EFFECT_CHANGED path at all.
Fix: add SECommon.effectAbilityIds if any SE mechanic is buff-driven; else document omission.

F11 7 boss classes have no onLeave; non-alertList acquires leak on boss-change
Severity: Medium  Confidence: INFERRED
Location: no onLeave in Lylanar, Dariel, Orphic, Ryelaz, Xoryn, Xynizata, Jynorah, Kazpian,
  Shaper (Trial guards `if boss.onLeave` so it fails silently).
Fix: document the acquire-only-via-alertList contract + a check, or add onLeave stubs.

F12 Stale docs/comments cluster — three of four CLOSED this run
Severity: Low   Confidence: CONFIRMED
(a) docs/decisions/trials.md detection paragraph claimed translation-table matching → FIXED
    (09dec56); (b) Ansuul "4 variants (+184710 kept for safety)" vs 5 registered → FIXED
    (a417096); (c) .review//DAILY_REPORT.md untracked cruft → FIXED (e210ea2 gitignore);
    (d) Falgravn 137499 cast-vs-icon ambiguity (docs/trials/KA.md:94 vs Falgravn.lua:560)
    remains NEEDS GAME: `d(GetAbilityName(137499), GetAbilityIcon(137499))` in-game.

F13 Unregistered-but-declared ids in common sets invisible to filters.lua
Severity: Medium  Confidence: CONFIRMED (negative test rc=0 on broken tree)
Location: test/checks/filters.lua — an id present ONLY in a common declared set (never in any
  route table) passes: adding [LEAP] to SunspireCommon combatAbilityIds → rc=0.
Fix: intersect common vs route sets numerically per file.

F14 route-shape check green but not in CI (PR #9 open)
Severity: Low   Confidence: CONFIRMED
`luajit test/checks/route-shape.lua` at a6355a0 → "clean (376 route entries, 25 boss
classes)"; grep of checks.yml → 0 refs. Fix: merge #9 + add step to all.sh and checks.yml
(Workflows scope still missing from the agent token — human step).

F15 state-reset.lua "reset" means "mentioned"; 25 fields grandfathered (loop-1 F11 open)
Severity: Low  Confidence: CONFIRMED (not re-negative-tested this lane).

## Strong points

- Event containment is real: EVENT_COMBAT_EVENT/EVENT_EFFECT_CHANGED registered ONLY via
  EventPipeline with per-id filters + pcall (verified; lane 5 F5-7). Every filtered event
  walks ~3 Lua frames.
- Layering audit came back clean mechanically (grep-based require graph; nothing in core/lib
  reaches up). This is what keeps per-trial deletion safe.
- 6213259's direction was right (removed 33 lang strings) even though it did not fix locale
  detection — keep the decoupling, add bounds.
- PR #5's coverage.lua turns "did dispatch run at all" into a measured number — the exact
  class of guardrail §3.3 asks for.

## Weak points

Verification debt concentrated in constants (F1, F2, F10, F12d): code is structurally sound
but 16 bosses' difficulty and 22 bosses' names are unverifiable outside the client. Checks
catch shape, not semantics (F13, F15). Release paths remain hand-written per boss (F4, F11).

## How to address

1. F1 + F2 (user-facing today): math.huge→NONE now (code), thresholds+AABBs via one measured
   play session (NEEDS GAME). Closes the two silent-death classes.
2. Merge the queue: #7 (wipe timers + border + frame precompute — F4/F8 partially), #9
   (+ 7-line checks.yml step by human, F14). Then negative-test route-shape under CI once
   the yml step lands (loop 3).
3. F4 central cleanupAlertList + F11 acquire-contract check — engine-level, closes the
   leak-silent class permanently.
4. F8 setRow in-place mutation + deferred render; F9 pipeline.safe wrapper; F13 filters
   numeric intersect; F7 registration table; F6 load containment.
5. F10/F12d/F15: docs or measurement follow-ups tracked upstream.

## What this review did NOT do

- No in-game verification (every NEEDS GAME constant stayed flagged, per §1.3).
- No branch deletions (prior delete attempt was denied by the user; deletion list below).
- Lanes 1/2/3 workers hit the tool-wall but all lane files completed; no lane was re-run.
- No changes to ui/, core/, lib/ business code (fix worker scope: docs, comments, .gitignore,
  one check).

## Branch hygiene

- Merged mid-run by Nick: PR #5 (0dcdc05 → 1e60635). Fix branch rebased onto it; all 10
  checks rc=0 at new base; fixture replays now dispatch (14 KA / 4 SS alerts).
- Still awaiting merge: #7 (5 commits), #8 (loop-1 review doc), #9 (route-shape, needs CI step),
  #3 (load-order), #2 (docs notes). #6 is superseded by #8 → closeable.
- Local branches strictly contained in origin/master: fix/manifest-scan-scope (deletion
  candidate — NOT deleted, delete denied at runtime 2026-09-10; human command:
  `git branch -d fix/manifest-scan-scope`).
- Not-contained, superseded-but-unmerged (keep + patches in cron-state/incha/patches/):
  feature/route-coverage, feature/route-shape-check (both superseded by feature/route-shape
  = PR #9), pr5 (duplicate of merged #5). All left untouched.
