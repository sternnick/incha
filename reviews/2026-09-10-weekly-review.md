# Incha weekly full-project review — 2026-09-10

**Scope:** 82 lua files (syntax.sh count), branch `master` @ `1efc63e` (== origin/master), 5 parallel review lanes (architecture / code / static / business logic / performance) + 1 fix worker + 1 targeted re-review. Review run 20:11–21:30 UTC, LOOP 1/3 of the user-authorized validation campaign.
**Fixes applied on** `fix/weekly-review-fixes-2026-09-10` (5 commits `fc97b90..6546fc6`, off 1efc63e, unpushed pending this review's PR).

**Verdict.** The engine core is genuinely well built: layering direction holds with zero back-edges, every high-frequency event registration is filtered (measured, not asserted), dispatch is 3 frames + 1 pcall deep, and memory shape is right (~650 KB resident for all 9 trials, instances rebuilt per encounter only). The dominant risk is unchanged: **silent failure** — 22 of 25 bosses detect only via English name literals, and 11 bosses can never resolve hardmode (threshold `math.huge`), so their HM branches are dead code that looks alive. Static checks are honest but have quantified blind spots: every injection of the highest-severity defect class (unfiltered registration, settings-key removal, manifest reorder) passed green today.

## Findings

Severity counts across lanes (deduplicated): Blocking 1, High 6, Medium 7, Low ~9, Info (positives) 4. 22 findings fixed/verified-closed this run are listed at the bottom.

F1  Static check blind to unfiltered event registrations (worst defect class)
Severity: Blocking · Confidence: CONFIRMED
Location: test/checks/filters.lua; test/harness/eso_api.lua:100
`filters.lua` inspects declared route tables only and never greps `RegisterForEvent`; the harness stubs registration to a no-op, so runtime observation is impossible. Three injected defects (unfiltered EVENT_COMBAT_EVENT inside EventPipeline; same outside it in Xalvakka onEnter; AddFilterForEvent deleted from register()) ALL exited rc=0. The tree itself is compliant today — the *guard* is missing, not a live bug.
Fix: `test/checks/registrations.lua` — every RegisterForEvent on a high-freq event in shipped files must have a paired AddFilterForEvent; regs outside core/EventPipeline.lua must be error-wrapped. (Lane3.)

F2  Hardmode never resolves on 11 bosses; only 4 bosses gate on isHM (37 refs)
Severity: High · Confidence: CONFIRMED (quantifies known F2)
Location: hmHealthThreshold=math.huge at as/Olms:56, cr/Zmaja:103, lc/Dariel:27, lc/Xynizata:36, oc/{Jynorah:65,Kazpian:53,Shaper:27}, rg/Oaxiltso:62, ss/{Lokke:152,Nahvii:74,Yolna:50} — 11 files; plus 8 bosses (dsr 3, rg 2, lc 3) at placeholder 100000001/round estimates flagged TODO.
Probe: detectDifficulty(maxinteger)=NORMAL for all 11 math.huge bosses. isHM branches exist only on 4 bosses (Lylanar 15, Taleria 4, Xalvakka 6, Bahsei 12 refs); Xalvakka's threshold is math.huge → its 6 branches are dead; Bahsei/Lylanar/Taleria thresholds are real so their gates DO open.
Fix: measure HM pools in one play session; branch `origin/fix/hardmode-measurement-aid` (1893b70) adds "/incha hp" + loud placeholders — merge it. (Lane4; carried from 09-10 review, drift quantified.)

F3  Detection drift: 22/25 bosses gated on English name literals; docs disagree with code
Severity: High · Confidence: CONFIRMED (quantifies known F1)
Location: core/BossRegistry.lua:58-79; only KA's 3 bosses (Falgravn:248, Vrol:47, Yandir:36) are bbox-detectable; 10 files use `.name=`, 13 use `nameAliases` — zero Lang.t references (all "TODO: verify via GetUnitName"). KA's 3 carry no name fallback: wrong AABB = silent dead encounter even with right names.
Docs: architecture.md A8 claimed detection reads lang/ — WRONG; corrected on the fix branch (commit 6546fc6).
In-game check: `/script d(GetUnitName("boss1"))` vs the literal on each non-KA boss, non-EN client. (Lane4/Lane1.)

F4  settings-usage.lua never sees the per-boss toggle layer — 25 advertised checkboxes unchecked
Severity: High · Confidence: CONFIRMED
Location: test/checks/settings-usage.lua:81 (brace-depth-2 collector), :118; consumer core/Trial.lua:176; ui/Menu.lua:101-390.
Output: "clean (6 keys checked against 69 files)". The 25 per-boss toggles are read via `Settings.trial(id).bosses[key]` — a dynamic subscript the static pattern can never match. Negative test: deleting `showPercent = true` (core/Settings.lua:71) while Menu writes and boss reads it → rc=0, checkbox silently dead. Unregistered boss key → gate nil ≠ false → silently ON.
Fix: derive keys from Factory registries; assert both directions against DEFAULTS and Menu getFuncs. (Lane1 F1-1 + Lane3 F3-2.)

F5  Adding a trial requires 6+ edits, two invisible to every check
Severity: High · Confidence: CONFIRMED
Location: incha.txt; incha.lua:22-30; trial/<id>/Factory.lua; core/Settings.lua; ui/Menu.lua; test/run_log.lua:56-70.
Nothing at runtime discovers Factories; contracts/filters restate a hardcoded TRIALS list, so a trial in incha.txt but absent from incha.lua loads, registers nothing, and is inert in-zone with zero errors.
Fix: one trial manifest table driving registration + Settings + Menu. (Lane1 F1-2.)

F6  One bad boss file silently kills zone routing for every trial registered after it
Severity: Medium-High · Confidence: CONFIRMED (simulated)
Location: incha.lua:22-30; bootstrap.lua:29-34.
All nine `require("trial.*.Factory")` are top-level in the last manifest file; ESO has no require(), the shim error()s on a missing module, so one file-scope error aborts incha.lua mid-list. Simulation: registered before abort = ka,ss; aborted at rg → 7 zones with no addon and no error. Run-time errors ARE contained (EventPipeline safe()); load-time is not.
Fix: pcall each registerTrial(require(...)) line. (Lane1 F1-3.)

F7  Timer rows bled through wipes on KA trio (FIXED this run)
Severity: Medium (was High in-lane) · Confidence: CONFIRMED, fix CONFIRMED
Was: onWipe cleared flags but not Timer objects (Yandir 2, Vrol 3, Falgravn 4 timers) — stale countdowns rendered wipe→next pull; state-reset.lua grandfathered all 9 fields. Fixed on branch (02dd8c7): clears added on wipe paths, 14 grandfathered exemptions removed, harness wipe-sim shows armed→leaked=0 for all three bosses. (Lanes2/4; fix verified R2.)

F8  Bahsei blue border leaked across wipes (FIXED this run)
Severity: Medium · Confidence: CONFIRMED
CA.border(true,9000,"blue") at Bahsei.lua:232 with no off-site anywhere; fixed (fc97b90) with `CA.border(false,0,"blue")` in onWipe, matching the shipped pattern (Xalvakka:166, Jynorah:291). (Lane2 F2-2.)

F9  Wipe and boss-change are mutually unexercised reset paths
Severity: Medium · Confidence: CONFIRMED (static) / NEEDS GAME for residue
core/Trial.lua:195 sole new() site; wipe reuses the instance and relies wholly on hand-written onWipe (no engine-level schema reset); boss-change discards+news and never calls onWipe. 12/25 bosses define no onLeave. A flag cleared on one path only survives the other.
Fix: engine-level stateSchema reset for fields the boss does not claim (soft reset becomes a mechanism, not a convention). (Lane1 F1-5.)

F10  Multi-target single-slot fields where per-unit tables are the norm
Severity: Medium · Confidence: INFERRED
rg/Oaxiltso.lua:68-70 sludgeTracker1 single slot (second concurrent target silently dropped) vs the keyed pattern in the same repo (Xalvakka manifoldOthers, Nahvii meteorTargets); dsr/Lylanar destructiveEmberName/piercingHailName single-name vs firebrandTracker[] in the SAME file. oc/Kazpian chainedA/B pair state can leak residue into the next pair on a FADED-miss.
Fix: adopt per-unit tables; confirm with 2-simultaneous-target pulls (NEEDS GAME). (Lanes2/4.)

F11  state-reset.lua "reset" means "mentioned"; 25 grandfathered fields
Severity: Medium · Confidence: CONFIRMED
Line ~179 `touched = scanText:match("self%."..key.."%W")` is satisfied by a READ — schema field + `if self.x ~= nil` in onWipe passes green while the value survives the pull (injection rc=0). Exemption table = 6 files/25 fields; the 9 KA timers were removed this run (see F7); remaining: Lokke 11, Nahvii 1, Yolna 1, plus flag-type fields.
Fix: require an assignment or method call, not a mention. (Lane3 F3-5.)

F12  No load-order check beyond bootstrap-first
Severity: Medium · Confidence: CONFIRMED
Moving core/AlertSink.lua (used by core/Trial.lua) to END of incha.txt leaves all checks green — contracts requires via real file-based require, an order ESO never executes.
Fix: load-order.lua asserting each load-time symbol is defined by an earlier manifest entry. (Lane3 F3-3.)

F13  contracts.lua goes green by omission through two bypassable registries
Severity: Low-Medium · Confidence: CONFIRMED
Literal TRIALS list (:24) + `find trial -path "*/boss/*.lua"` (:75): a 10th trial never added, or a boss at an unusual path, is silently unscanned. manifest.lua already knows every loaded file — enumerate from there/ZoneManager. (Lane1 F1-8.)

F14  200 ms tick allocates a fresh row table per row per tick
Severity: Low-Med · Confidence: CONFIRMED (code shape; sizing NEEDS GAME)
ui/Panel.lua:448 setRow rebuilds rowData[key] table each call — ~15 tables/s at 3 rows; expired-timer branch concatenates a fresh name string per tick. Re-sort only on key-set change (fine).
Fix: mutate existing row table in place; pre-build constant label strings. (Lane5 F5-3.)

F15  Falgravn 20 Hz icon tick formatted a string per unit per frame (FIXED this run)
Severity: Low (was Low-Med) · Confidence: CONFIRMED, fix CONFIRMED
Was string.format per animated unit per frame (~240 strings/s at 12 units); now INST_ANIM_TEX[1..40] precomputed at file scope (2dd5148); 200-iteration equivalence assert OK, frame index provably ∈1..40. (Lane5 F5-4.)

F16  Misc hygiene cluster
Severity: Low · Confidence: CONFIRMED
core/Bridge.lua is an abstraction that does nothing (options.bridge non-nil 9/9, BridgeBase.extend zero call sites — delete or wire); legacy BSCHTKA import latches `migratedFromBSCHTKA` regardless of outcome (a load-order miss forfeits the import forever) and writes showBossUI with zero readers (known F6-0910); BossBase.fromSchema docstring over-credits itself vs contracts.lua which does the enforcing; Xalvakka registers 3 engine events outside EventPipeline (self-heals via unregister-first, benign wasted wake — comment or move to onWipe); manifest .review exclusion (d8f99d9) — scratch no longer fails the local gate.

## Strong points
- **Registration filtering is exemplary and measured:** high-freq events never registered unfiltered; per-ability-id REGISTER_FILTER + result-filtered slices discard raid-wide volume before Lua (Lane5 full grep + filters.lua).
- **Dispatch shape:** 3 Lua frames + 1 pcall per admitted event, hash routing, no per-event table builds; the pcall is the error-containment wrapper — keep it.
- **Layering is enforced by habit that holds:** zero core→trial imports; incha.txt lists every runtime file, no dupes (git ls-files diff clean).
- **A5 memory shape is right:** class/route tables resident (~650 KB live), per-pull work is one flat stateSchema copy.
- **Per-unit keying is the established pattern** (53 keyed writes) — the single-slot fields are the outliers, not the norm.

## Weak points
- Verification debt: the checks trust declarations, not call sites — every highest-severity injection class passed green (F1, F4, F11, F12).
- A good pattern applied to some files only: timer cleanup on both hooks (Yolna/Nahvii/Yandir) vs flag-only wipe (KA trio, fixed); onLeave teardown (*_cleanup shared) vs alertList-only (rg/se trio).
- Silent-failure surfaces concentrate at registration edges: detection literals (F3), trial registration list (F5), load-time require (F6), check registries (F13).

## How to address
1. **Now, code done this run** (branch `fix/weekly-review-fixes-2026-09-10`): F7, F8, F15, F16-manifest, F16-docs.
2. **Stops the next defect shipping:** `registrations.lua` closes F1; load-order.lua closes F12; settings-usage v2 (harness-loaded Settings + bidirectional assert from Factory registries) closes F4 and the F6-0910 survivor; state-reset touch-pattern tightening closes F11's read-as-reset class; contracts enumeration from manifest closes F13.
3. **Correctness/structure:** pcall-per-registerTrial (F6); engine wipe-reset from stateSchema (F9); per-unit tables for Oaxiltso sludge + Lylanar ember/hail + Kazpian pair (F10, with 2-target in-game confirmation); delete-or-wire Bridge.lua (F16).
4. **Performance:** Panel setRow in-place mutation (F14); Vrol's cached-`now` pattern spread to Falgravn tick (F5-8 lane5). In-game sizing: GetFrameTimeMilliseconds around the 200 ms tick.
5. **Game data (one play session, NEEDS GAME):** merge hardmode-measurement-aid branch and read "/incha hp" on 11 HM pools (F2); `/script d(GetUnitName("boss1"))` sweep on 22 name-gated bosses incl. a non-EN client (F3); practice-pull orderings (F4-4 lane4 stage skip; 2-simultaneous-target checks for F10).

## Explicitly not done
- PR #5 (dispatch-coverage) grading deferred — touches harness+docs only; it stays open for human merge.
- OptionalDependsOn/ext-api optionality sub-bullet (lane1 timebox), per-boss onWipe completeness audit, alert-latency sampling, DebuffTracker keying sweep (lane4 timebox).
- Branch-process note: the fix branch was rewritten mid-run by concurrent worker activity (reflog shows reset+rebuild); FINAL state independently verified correct (5 commits, all fixes on-tip, no grandfathering, checks 8/8 rc=0) — REVIEW-2's "fixes lost" warning applied to a transient state.
