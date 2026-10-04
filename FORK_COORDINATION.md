# FORK_COORDINATION — sternnick/incha (shared fork, two writers)

Contract: delivery-contract effective 2026-09-11. cp-hermes-01 = agent lane owner
via this table. Rule: claim a lane by PUSHING the branch; a finding already
claimed here gets a COMMENT on the upstream issue, never a second branch.
Every run updates this file (and commits the current table on its delivery branch).

Fork master = pure mirror of oseias-pt/master. Verified 2026-09-11 01:40 UTC:
origin/master = 1efc63e = upstream/master (reset done this date; prior
divergence of 23 commits erased, backup tag archive/fork-master-20260911 local-only).
MIRROR RESTORED 2026-09-24 (owner-side Sync between runs): origin/master =
de1dea6 = upstream/master, rev-list 0/0 both directions (verified ls-remote +
fetch --prune). Consequence: workflow gate no longer fires for pushes whose
history merely CARRIES existing workflow files — only branches that
CREATE/UPDATE a workflow file are rejected. fix/castinfo-arity pushed to
fork OK 2026-09-24 21:2xZ (rc=0) after 15 consecutive rejections.

## Author sweep + review-doc deletion (2026-09-11 02:45-03:00 UTC, verified)

A DONE: 14 cp-hermes-01 commits swept via rebase --exec amend --reset-author in isolated
worktrees (the 01:46 cron run was still active in the main worktree at the time).
Remote tips now: feature/dispatch-coverage b72d866, feature/route-shape 049c0d1,
fix/weekly-review-fixes-2026-09-10 2f41c87 — each prints EXACTLY one author line
(65017566+sternnick@users.noreply.github.com). feature/route-shape additionally carries
commit 049c0d1 fixing its 2 luacheck warnings (W542/W541 -> 0 warnings, all.sh 11/11 in a
feature/* worktree, negative tests NIL FN/FILTER KEY/STRING KEY/BAD ENTRY all rc=1).
B DONE: feature/weekly-review-2026-09-10 + fix/weekly-review-loop2-2026-09-10 deleted
(26 remote heads incl master now); content preserved: patches/pre-reset-master-2026-09-11/
0019/0028/0030 + loop2 0001.
C: both local tokens verified github_pat_11… = FINE-GRAINED (93 chars). API error text is
"Resource not accessible by personal access token" = token-TYPE limitation, matching Nick's
diagnosis. NO classic PAT exists anywhere on this box
(git-credentials has the same FGPAT via x-access-token). pi-agent00 credentials/endpoint:
NOT FOUND locally (grep ~/.secrets, scripts, RAG search = nothing) -> handoff blocked on
Nick providing pi-agent00's channel or a classic PAT (repo scope). Staged payloads ready:
PENDING_PUSH.md items 1-4.

## Reconciliation watch (added 2026-09-11 02:20 UTC)

The 01:15 daily fire (exec 3345c1b3543d af27ee4c…, started 01:46:29, OLD prompt) was
running WHILE this contract was being encoded — it overwrote ledger.json 02:01 and
PENDING_PUSH.md 02:16. It cannot be paused mid-run. One-shot reconciler job
556e23a0b22d (04:49 UTC) verifies mirror/identity/branches afterward and flags any
violation (mirror re-divergence, cp-hermes-01 commits, resurrected cb9b177-line branches).
Last reconciliation: 2026-09-11 05:58 UTC by one-shot reconciler job 556e23a0b22d — mirror
OK (origin/master==upstream/master==1efc63e, no re-divergence), identity verified (repo-local
Nick Sterniotis <65017566+sternnick@users.noreply.github.com>), 27 remote heads scanned:
ZERO cp-hermes-01 commits ahead of upstream, ZERO refs containing erased cb9b177 line.
One unannounced change found & explained: fix/manifest-load-order force-updated
8204b58→16d88f0 at 03:48Z by the daily run (exec ebd871f0, ended 03:39 + tail work) —
a rebase onto 1efc63e (2 commits, clean author, luacheck warning fixed per §2a), NOT a
mirror violation. Moved stale→live below. No branch deletions (Nick's call).
(Earlier: 2026-09-11 02:20 UTC manual — this file + ledger + prompts + orientation script
updated to contract.)

## Lane claims (agent)

| Finding / work | State | Branch / URL |
|---|---|---|
| coverage / per-ability reporting | CLOSED by upstream #284 | #284 (2026-09-16) ships per-ability coverage in run_log.lua ("Route entries never seen" + NEVER SEEN per boss). feature/dispatch-coverage b72d866 = delete candidate; PENDING_PUSH item 1 withdrawn. |
| route-shape linting | held-pending-dev-answer | branches feature/route-shape (a6355a0) + patch route-shape-check-aa27f4e.patch. Tables it guards get deleted Phase 2.5 (#241). ASK on #236/#241 first; NO PR until answered. |
| KA wipe fixes (Falgravn, Vrol, Yandir) | commented-pending | in fix/weekly-review-fixes-2026-09-10 (02dd8c7); #237/#238/#239 rewrite those files -> deliver as comment w/ exact patch + harness probe evidence, never PR. |
| luacheck W213/loop/empty-if fixes | deleted (folded) | our load-order.lua + route-shape.lua carried the warnings; per §2a fix goes on whatever branch we deliver against; upstream master + active line = 0 warnings (verified luacheck 1.1.2 worktrees). |
| load-order.lua (e26b8b5) | rebased-live (was: deleted) | NOT in upstream/master (verified merge-base rc=1 2026-09-11 05:55); branch fix/manifest-load-order rebased onto 1efc63e by daily run 03:48Z → 16d88f0, 0-behind, W213 fixed (fd9722d+16d88f0). Delivery still via PENDING_PUSH item 4c (offer re-based onto active line), claim-by-push honored. |
| weekly reviews (reviews/*.md) | deleted | NEVER commit to repo (§5). Convert top findings to 2-3 focused upstream issues; token 403 on upstream issues -> queued in pending-issues/ + PENDING_PUSH.md. |
| weekly review 2026-09-12 fix branch | pushed-live | fix/weekly-review-2026-09-12 @ 23aef5c on fork (463b1ab CastDur 2nd-return fix + harness stub, 23aef5c dead showBossUI write removed). Gates green. Upstream PR STAGED (PENDING_PUSH item 7a, token 403). LC-common regression (F1) + EventDispatcher:340 arity + _pending leak = COMMENT-recommended on #236/#264, NOT branches (rewrite territory). |
| hmHealthThreshold inventory (F2) | comment-pending | 11x math.huge + 6x 100000001 + 3 estimates at acd3f73; BossRegistry.lua:114 >= compare => 100000001 bosses always-HARDMODE. Staged as new-issue draft PENDING_PUSH 7e(i); values must be measured, never invented (§1.3). |
| replay alert-zero blindness (harness injectBoss vs getActiveBoss) | CLOSED by upstream #284 | #284 (2026-09-16, master 91c8c5f) fixes the nil-boss dispatch via Trial:injectBoss + _injected flag; replay alerts live on master (ka 14, ss 4 measured 2026-09-16). r5 @6e2cba5 = SUPERSEDED, do NOT push; fork fix/harness-activebosses 71bd279 = delete candidate. PENDING_PUSH 12a withdrawn. |
| GetAbilityCastInfo return-arity (started-bucket + CastDur dead on client) | **pushed to fork; PR STAGED** | fix/castinfo-arity @f078e6b PUSHED to fork 2026-09-24 (rc=0, gate no longer fires since mirror restored — branch carries but does not touch workflows; touches only EventDispatcher.lua/CastDur.lua/eso_api.lua). 0-behind de1dea6 (merge-base rc=0), named-branch worktree gates: all.sh **15/15 rc=0**, luacheck 0/91f, ka 14 / ss 4 alerts. Arity bug NOT fixed by #285 (EventDispatcher:425 still reads return 1). CONFIRMED via esodecoded.com official signature + Combat Metrics usage. PR onto oseias-pt STAGED (upstream POST pulls still 403). PENDING_PUSH 16a. https://github.com/sternnick/incha/tree/fix/castinfo-arity |
| snapshot tests (Phase 2 item 2, Priority 1) | PR staged (branch LOCAL) | feature/snapshot-tests @cba7dea — 0-behind de1dea6; named-branch worktree gates: all.sh **16/16 rc=0** (snapshot 9 matched), luacheck 0/92f. Push REJECTED 2026-09-24 (16th gate — branch itself UPDATES checks.yml → needs workflow scope; restoring the mirror did NOT unblock this one). PENDING_PUSH 16b. |
| LCCommon never merged into LC bosses | CLOSED upstream (#276) | e0efc5d merged LCCommon into all 5 LC bosses (verified grep 2026-09-14: Dariel:47-53, Orphic:113-122, Ryelaz:100-109, Xoryn:148-159, Xynizata:72-79). Was PENDING_PUSH 10b — no action. |
| EventDispatcher._pending wipe-path leak | narrowed, comment-pending | clearPending() wired to boss-change/zone-exit (EventPipeline:154-155 via Trial.lua:115) only; wipe path Trial.lua:394-395 calls boss:cancelPending() but not EventDispatcher.clearPending() -> dispatcher interrupt timers survive wipe while boss stays active. Re-verified at 522b56f (Trial.lua/EventPipeline.lua unchanged in a37baa6..522b56f; only armed user = ss/Nahvii events.beginCast.interrupted). NOTE: former comment target #264 CLOSED 2026-09-15 — retarget to open Nahvii/SS issue or new issue at delivery. PENDING_PUSH 12c. |
| weekly review 2026-09-20 @ de1dea6 | reported (no delivery) | 3 lanes @ frozen de1dea6 (#285 delta only: 2 commits). 0 Blocking / 2 High (F1 arity drift — fix LOCAL 16a, gate-blocked 11th; F2 HM dead 16/25 bosses — 7e(i)) / 4 Med / 5 Low + 1 drift. NEW: verboseDebug shipped without any setter path + settings-usage blind to root DEFAULTS (17a), setDispatchContext per-event cost with tracing OFF (17b), trials.md Zmaja claim stale + .review/ path NOT gitignored — reproduced check-ignore rc=1 (17c), KA bbox-only detection no name fallback (17d comment on #224). Tree clean (report in .reviews/). Report: .reviews/review-2026-09-20.md. |
| nightly delta 2026-09-23 21:2xZ @ de1dea6 | reported (no delivery) | master unchanged (3rd quiet night), 0 issue/PR activity (since-filter 0 items), 6 non-master heads unchanged. Lanes re-verified 0-behind; worktree gates: luacheck 0/91f + 0/92f, all.sh fails ONLY branch-name (detached nuance). Push 15th-gate (names checks.yml) + issues/pulls 403. Replays ka 14 / ss 4 (must run zone auto-detect — explicit 1331/1272 wrong). Report: cron-state/DAILY_REPORT_2026-09-23-nightly.md. |
| nightly delta 2026-09-22 21:3xZ @ de1dea6 | reported (no delivery) | master unchanged (2nd quiet night), 0 issue/PR activity (since-filter 0 items). Lanes re-verified: both 0-behind, gates green (branch-name fails only in detached worktree — real-branch call rc=0, 15/15+16/16 effective). Push 14th-gate + issues/pulls 403. Replays ka 14 / ss 4, 0 errors. Report: cron-state/DAILY_REPORT_2026-09-22-nightly.md. |
| nightly delta 2026-09-21 21:3xZ @ de1dea6 | reported (no delivery) | master unchanged, 0 issue/PR activity (API since-filter = 0 items). Both staged lanes re-verified 0-behind + gates green; push 13th-gate + issues/pulls both 403. FULL stub-arity audit CLOSED last 'unaudited stubs' finding: 8 functions vs official sigs (esodecoded 200s) — only defect = GetAbilityCastInfo (fix = 16a, scope proven to cover ALL master sites); GetMapPlayerPosition stub 2-vs-5 returns = LOW latent (0 call sites); GetPlayerRoles page 404 = UNVERIFIABLE. NEW LOW: .githooks/pre-push committed 100644 (non-exec) upstream -> §3.7 branch gate advisory-only on fresh clones. Report: cron-state/DAILY_REPORT_2026-09-21-nightly.md. |
| nightly delta 2026-09-20 21:1xZ @ de1dea6 | reported (no delivery) | master unchanged, 0 activity; both staged lanes re-verified 0-behind + gates green; push 12th-gate + 403 re-measured. NEW watch: 6 upstream non-master heads (all stale-behind, 0 PRs; playback-log-inject = re-anchor trigger for 4c). Stub-arity class CLOSED CLEAN (GetUnitWorldPosition correct at all 10 sites, esodecoded 200). Report: cron-state/DAILY_REPORT_2026-09-20-nightly.md. |
| weekly review 2026-09-19 @ 91c8c5f | reported (no delivery) | 3 lanes @ frozen 91c8c5f. 0 Blocking / 1 High (F1 arity, fix LOCAL 13b, gate-blocked 9th meas) / 6 Med / 7 Low. Graded FIXED: name-detection F1 (22+3/25 reachable), replay-zero (#284), LCCommon (#276). Drift-only: _pending dormant, HM 11+5. New: warnUnknown hot-path spam (PENDING_PUSH 15b), state-reset negative-test failure (15c). Report: .reviews/review-2026-09-19.md (gitignored dir — note .gitignore says `.reviews/`, complete-review.md §4 says `.review/` = F13 doc drift). |
| dead showBossUI migration write | CLOSED upstream | cf2a358/9dac1e8 dropped the key; grep master core/Settings.lua empty (verified 2026-09-14). No action. |

## Remote branches audit (27 + master, fetched 2026-09-11)

All are ours (developer works in upstream repo). >10 behind = not pushable per §2c:
rebase or delete. 0 behind = live candidates.

live (0 behind upstream/master, tips verified 2026-09-11 05:55 reconciler scan):
feature/dispatch-coverage b72d866, feature/route-shape 049c0d1,
fix/weekly-review-fixes-2026-09-10 2f41c87, fix/manifest-load-order 16d88f0 (rebased onto
1efc63e 03:48Z — was stale-32 at 8204b58; now pushable shape, 2 commits, 0 luacheck warnings)
stale 59-behind: feature/agent-instruction-suggestions 9011189 (docs/notes -> §5: comment material), fix/preview-slash-delay 28be1f5
stale 81-behind: feature/lang-keys-check, feature/string-escape-lint, fix/duplicate-lang-keys, fix/escaped-byte-literals, fix/globals-check-scope
stale 146-162-behind: archive/try-lineage, feature/ci-static-validation, feature/ci-validation-green-demo, feature/live-trial-enable, feature/review-package-2026-09-01, feature/static-validation-stack, feedback/mechanics-review (→comment), fix/boss-slot-and-alert-hygiene, fix/docs-drift-corrections, fix/hardmode-measurement-aid, fix/mechanics-review-fixes, fix/panel-cache-and-control-name, fix/single-version-source, fix/strip-utf8-bom
NOTE: the reconciler found NO cp-hermes-01 author emails and NO cb9b177-derived tips on any
of the 27 heads above. review@localhost appears on old pre-contract commits only (≤162-behind
stale branches) — pre-dates contract, listed for deletion decision, not flagged as violation.

## MIGRATION MERGED (2026-09-13, run 3345c1b3543d) — read this first

#266 merged 2026-09-13T01:18Z: master = 76d13a2, the dispatcher rewrite IS
master now. feature/event-dispatch-migration branch DELETED upstream
(ls-remote). master carries .github/workflows/close-linked-issues.yml =>
workflow-scope gate now blocks EVERY push of post-#266 history, INCLUDING
the master mirror itself (measured 2026-09-13: FF acd3f73->76d13a2 rejected).
Fork master will silently diverge until Nick adds workflow scope or uses
web "Sync fork". Deliverables re-anchored: fix/harness-activebosses-r2
(local @ 1626040, base 76d13a2, UNPUSHABLE until gate lifts; patches in
patches/newmaster-20260913/r2/). Old fix/harness-activebosses (master
pre-#266) = OBSOLETE, do not PR. Replay-blindness still live on 76d13a2
(ka/ss Alerts 0 rc 0, measured clean worktree). LCCommon regression now a
LIVE master defect (0/5 LC bosses merge LCCommon; ids 222475/165972/214675
routed by nobody) -> new-issue draft PENDING_PUSH item 9.

## Token capability (probed 2026-09-11, re-probed 2026-09-12 04:1x UTC)

- fork sternnick/incha: push OK with the token embedded in the push URL
  (branch fix/harness-activebosses pushed clean today); Issues API 422-probe OK.
  NEW 2026-09-12: plain `git push origin` now FAILS with "Permission to
  sternnick/incha.git denied to sternnick" — the credential-store entry
  (.git-credentials, user cp-hermes-01) is NOT the gh-incha-token and lost
  push rights. Push via: git push "https://x-access-token:$(cat ~/.secrets/gh-incha-token)@github.com/sternnick/incha.git" <branch>.
- NEW BLOCKER (measured 2026-09-12): pushes whose commit range introduces a
  .github/workflows/* file the fork never had are rejected outright —
  "refusing to allow a Personal Access Token to create or update workflow
  without `workflow` scope". The edm tip contains
  close-linked-issues.yml (added upstream in f1638d6), so NOTHING based on
  the active line is pushable to this fork until (a) #265 lands on master,
  or (b) the token gains workflow scope. Master-based branches unaffected.
- upstream oseias-pt/incha: READ-ONLY. POST issues=403, POST issue comments=403,
  POST pulls=403 (re-probed both ways 2026-09-12; gh CLI has no login on box).
  => PRs onto upstream and comments stay STAGED in PENDING_PUSH.md until the
  FGPAT is re-scoped to oseias-pt/incha (Issues: RW, Pull requests: RW).

## Identity (contract §0)

Repo-local git config set 2026-09-11: Nick Sterniotis <65017566+sternnick@users.noreply.github.com>.
cp-hermes-01@sterniotis.com = never again (13 such commits existed in fork master; erased by reset).
