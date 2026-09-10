# Weekly Full Review — Incha — 2026-09-10

Scope: 15,642 Lua LOC, 89 .lua files, branch `master` @ `1efc63e` (== origin/master).
Per agents/complete-review.md (fingerprint c92816… unchanged, no drift vs ledger).
Run note: **dry-run validation run** (user-approved): 3 delegated reviewer lanes were
launched in parallel; all three exceeded the 3000 s child wall and returned no final
report, so every lane below was re-derived by the orchestrator directly with the
commands shown. No code fixes were applied in this run (intentionally deferred).

**Verdict.** The event architecture is genuinely good: every high-frequency registration
(EVENT_COMBAT_EVENT / EVENT_EFFECT_CHANGED) is per-ability-id filtered inside
core/EventPipeline.lua, and the lifecycle hooks are nil-guarded so bosses opt in
without crashing. The dominant risk is still *silent detection failure*: 8 of 9 trials
activate only by exact English unit-name match, and on 11 bosses hardmode can never be
detected (threshold = math.huge), so 37 isHM branches are dead. Additionally, on master
today the replay fixtures dispatch **zero** alerts — the whole evidence layer is blind
until PR #5 merges (fix verified on that branch).

## Findings

F1  Non-KA trial detection relies on exact English name literals
Severity: High   Confidence: CONFIRMED (mechanism) / INFERRED (locale failure)
Location: core/BossRegistry.lua:53-58 (findByName + its own CAVEAT comment), all 22 non-KA boss files
    luajit probe: detect=loc only for Yandir/Vrol/Falgravn (KA); every other boss detect=name.
    luajit -e '... require("core.BossRegistry"):findByName(...)'
    Only KA declares Location bounds; 8 trials rely on name/nameAliases alone. Code comment
    (BossRegistry.lua:55-57) states DE/FR/RU/ES/JP clients match nothing — silent no-boss.
    Also OlmsEncounter.lua:52 nameAliases carries `TODO: verify via GetUnitName in-game`.
Fix: per trial, add Location bounds (issue #123) or per-locale name tables; one /incha
    debug run per trial yields the exact GetUnitName strings (Trial.lua:162-170 already logs them).

F2  Hardmode permanently unresolvable on 11 bosses — threshold = math.huge
Severity: High   Confidence: CONFIRMED (mechanism) / NEEDS GAME (the values)
Location: trial/{oc/3,ss/3,lc/2,as/1,cr/1,rg/1}/boss/*.lua (e.g. trial/ss/boss/Lokke.lua:152)
    grep -rln 'hmHealthThreshold = math.huge' trial/ | wc -l  ->  11
    luajit probe: detectDifficulty(Lokke, 12_000_000) => 1 (NORMAL); HM=2 never reachable.
    37 `isHM` call sites in trial/ are therefore gated off on these bosses.
Fix: one vet-HM pull per boss reading UnitHealth max (NEEDS GAME); code change is a
    one-line constant replace per boss. (Baseline 2026-09-05 F2 — unchanged.)

F3  Replay harness dispatches nothing on master: all 9 fixtures fire 0 alerts (fix in PR #5)
Severity: High   Confidence: CONFIRMED
Location: test/run_log.lua + test/harness (regression landed after a519e34)
    luajit test/run_log.lua test/fixtures/<x>.log for x in ka ss rg dsr as cr se lc oc
    -> "Alerts fired : 0" in all 9; ka also "Route entries never seen: 15"; all rc=0 (green on dead routes).
    Grading of fix branch feature/dispatch-coverage (PR #5, 0dcdc05): rebased on 1efc63e,
    ledger records alerts=14(ka)/4(ss), LOGGED-NEVER-DISPATCHED=0, rc=0 — merges cleanly,
    4 files +396/−26, no CI workflow touched. Recommend merging PR #5; this finding then closes.

F4  filters.lua cannot catch an unfiltered high-frequency registration (negative-tested)
Severity: Medium Confidence: CONFIRMED
Location: test/checks/filters.lua; injection site core/EventPipeline.lua:97-98/40
    Injected in scratch worktree: dropped the REGISTER_FILTER_ABILITY_ID AddFilterForEvent on the
    EVENT_COMBAT_EVENT per-id path -> filters.lua printed "filters: clean", rc=0.
    Also dropped both EVENT_POWER_UPDATE filters -> still "clean", rc=0. Restored, tree clean.
    The check validates per-boss routing data, not the pipeline's registration call sites.
Fix: have the harness record (event -> filters) per namespace registration and assert
    non-empty filter set for COMBAT_EVENT/EFFECT_CHANGED; wire into all.sh.

F5  state-reset.lua is a real guard (negative-test passed) — but 4 known survivors stay grandfathered
Severity: Low    Confidence: CONFIRMED
Location: test/checks/state-reset.lua:38+ (GRANDFATHERED), injected defect test
    Injected `negTestField = 0` into Lokke.stateSchema -> "NOT RESET ... rc=1"; after
    git checkout -- -> rc=0. Mechanically honest. Grandfathered Falgravn/Vrol/Yandir/Lokke
    timer survivors keep counting down across a wipe until centralized reset lands.
Fix: centralize schema reset in BossBase:cancelPending/onWipe path; delete GRANDFATHERED entries.

F6  showBossUI: legacy-migration write with no UI and no reader; invisible to settings-usage.lua
Severity: Low    Confidence: CONFIRMED
Location: core/Settings.lua:132 (only occurrence repo-wide outside harness stub test/harness/eso_api.lua:314)
    grep -rn showBossUI ui/ -> no hits (no checkbox exists); grep across core/ trial/ -> no reader.
    settings-usage.lua scans the per-trial defaults block, not the migration block, so it stays green.
Fix: drop the migration write (or map it to trials.ka.bosses.*), and extend settings-usage.lua
    to scan every `_sv.trials.*.` assignment including migrations. (Baseline F6, evolved shape.)

F7  manifest.lua scan is filesystem-wide: workstation scratch (.review/*.lua) fails CI-gate locally
Severity: Low    Confidence: CONFIRMED
    luajit test/checks/manifest.lua with stray .review/*.lua present -> 7x "NOT LOADED", rc=1;
    after moving scratch out -> "manifest: clean (71 files, v0.1.0)" rc=0. CI unaffected.
Fix: enumerate via `git ls-files` (already tracked in ledger as Priority-2).

## Checks baseline (master, clean tree)
syntax rc=0 | encoding rc=0 | globals rc=0 | manifest rc=0 | lang rc=0 | contracts rc=0 |
filters rc=0 | settings-usage rc=0 | state-reset rc=0.  Negative-tests: state-reset → effective
(rc=1 on injected defect); filters → BLIND (F4). Fixture replays rc=0 but alerts=0 (F3).

## Performance (no finding)
Per-id REGISTER_FILTER_ABILITY_ID registrations in EventPipeline.lua:91-119; cDied/cRes filtered
by combat result; Xalvakka.lua:151-157 registers outside the pipeline but filtered
(REGISTER_FILTER_UNIT_TAG reticleover, medium-frequency events); incha.lua only registers
ADD_ON_LOADED / ZONE_CHANGED / PLAYER_ACTIVATED (rare). POWER_UPDATE filtered by health+boss-prefix.
No unfiltered high-frequency registration found. Panel.lua declares/observes zero per-tick allocation
(Panel.lua:29-30; alert clear uses zo_callLater with seq invalidation, Panel.lua:422).

## Strong points
- Registration filtering discipline (§3.5): the loudest events are only ever subscribed per-ability-id
  inside one audited file — the design that prevents the #1 ESO addon perf sin.
- state-reset.lua genuinely catches wipe-surviving schema fields (mechanically proven, F5).
- Trial.lua lifecycle is nil-guarded (227/319/362): missing optional hooks degrade silently-safe, and
  the detection-failure debug dump (Trial.lua:162-189) turns a silent no-boss into one /incha debug
  run listing every wrong name — exactly the §1.3-correct pattern.

## How to address
1. F3 — merge PR #5 (restores all evidence tooling; unblocks every future finding).
2. F4 — harness-recorded filter assertion (stops F3-class blindness from shipping again).
3. F1 — Location bounds or locale name tables (issue #123); game measurement = tracked item.
4. F2 — HM health measurement session; then 11 one-line constant fixes.
5. F5 — central reset in BossBase; F6/F7 — hygiene, fold into next housekeeping PR.

## Branch hygiene
- feature/dispatch-coverage (0dcdc05) -> PR #5 OPEN, applies on master, no CI file — merge it.
- feature/route-shape-check (aa27f4e) -> mergeable into master (merge-tree: 0 conflict markers),
  touches .github/workflows/checks.yml -> **push blocked for FGPAT** (needs Workflows permission
  on the token, or one human push). Its check is exactly the F4-class guard.
- feature/route-coverage (9fed25a) -> same-subject predecessor of aa27f4e; treat as SUPERSEDED
  (73-file diff vs route-shape-check is base drift); do not push; safe to delete after aa27f4e lands.
- Patches exported to ~/.hermes/cron-state/incha/patches/; PENDING_PUSH.md updated.

## What I did not do
No fixes applied (dry-run directive); no PRs merged; no negative-test on the shared tree
(worktree + instant restore only); no upstream writes; did not re-report items owned by open
PRs #2/#3/#5; no in-game verification (all NEEDS GAME values marked as such).
