# FORK_COORDINATION — sternnick/incha (shared fork, two writers)

Contract: delivery-contract effective 2026-09-11. cp-hermes-01 = agent lane owner
via this table. Rule: claim a lane by PUSHING the branch; a finding already
claimed here gets a COMMENT on the upstream issue, never a second branch.
Every run updates this file (and commits the current table on its delivery branch).

Fork master = pure mirror of oseias-pt/master. Verified 2026-09-11 01:40 UTC:
origin/master = 1efc63e = upstream/master (reset done this date; prior
divergence of 23 commits erased, backup tag archive/fork-master-20260911 local-only).

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
| coverage / per-ability reporting | commented-pending | held: MUST be a comment on oseias-pt/incha#236, not code (#256 already ships test/checks/dispatch.lua). Our coverage.lua patch archived: patches/0001-fix-test-harness-dispatches-again... | 
| route-shape linting | held-pending-dev-answer | branches feature/route-shape (a6355a0) + patch route-shape-check-aa27f4e.patch. Tables it guards get deleted Phase 2.5 (#241). ASK on #236/#241 first; NO PR until answered. |
| KA wipe fixes (Falgravn, Vrol, Yandir) | commented-pending | in fix/weekly-review-fixes-2026-09-10 (02dd8c7); #237/#238/#239 rewrite those files -> deliver as comment w/ exact patch + harness probe evidence, never PR. |
| luacheck W213/loop/empty-if fixes | deleted (folded) | our load-order.lua + route-shape.lua carried the warnings; per §2a fix goes on whatever branch we deliver against; upstream master + active line = 0 warnings (verified luacheck 1.1.2 worktrees). |
| load-order.lua (e26b8b5) | rebased-live (was: deleted) | NOT in upstream/master (verified merge-base rc=1 2026-09-11 05:55); branch fix/manifest-load-order rebased onto 1efc63e by daily run 03:48Z → 16d88f0, 0-behind, W213 fixed (fd9722d+16d88f0). Delivery still via PENDING_PUSH item 4c (offer re-based onto active line), claim-by-push honored. |
| weekly reviews (reviews/*.md) | deleted | NEVER commit to repo (§5). Convert top findings to 2-3 focused upstream issues; token 403 on upstream issues -> queued in pending-issues/ + PENDING_PUSH.md. |
| weekly review 2026-09-12 fix branch | pushed-live | fix/weekly-review-2026-09-12 @ 23aef5c on fork (463b1ab CastDur 2nd-return fix + harness stub, 23aef5c dead showBossUI write removed). Gates green. Upstream PR STAGED (PENDING_PUSH item 7a, token 403). LC-common regression (F1) + EventDispatcher:340 arity + _pending leak = COMMENT-recommended on #236/#264, NOT branches (rewrite territory). |
| hmHealthThreshold inventory (F2) | comment-pending | 11x math.huge + 6x 100000001 + 3 estimates at acd3f73; BossRegistry.lua:114 >= compare => 100000001 bosses always-HARDMODE. Staged as new-issue draft PENDING_PUSH 7e(i); values must be measured, never invented (§1.3). |

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

## Token capability (probed 2026-09-11)

- fork sternnick/incha: push OK, PR/Issues API OK (422 probes)
- upstream oseias-pt/incha: READ-ONLY. POST issues=403, POST issue comments=403, POST pulls=403.
  => PRs onto upstream and comments on #236/#241 are BLOCKED until this FGPAT is
  re-scoped to include oseias-pt/incha (Issues: RW, Pull requests: RW).
  Until then: push branch to fork + stage command/body in PENDING_PUSH.md.

## Identity (contract §0)

Repo-local git config set 2026-09-11: Nick Sterniotis <65017566+sternnick@users.noreply.github.com>.
cp-hermes-01@sterniotis.com = never again (13 such commits existed in fork master; erased by reset).
