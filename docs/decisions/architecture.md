# Architecture decisions

Engine-wide. Per-trial facts are in [`trials.md`](trials.md).

---

## A1 · The manifest is the load order, and `require` never touches disk

*2026-08 · settled*

ESO exposes no `require` and no `package` library. `bootstrap.lua` defines both: `package.loaded`
is a plain table and `require` is a **lookup that raises** rather than falling back to file I/O.
Every module ends with `package.loaded["x.y"] = M; return M`, and `incha.txt` fixes the order.

**Rules out** circular requires and lazy loading. A module appearing after its first caller in the
manifest fails loudly at load with a named error, which is the intent — the alternative is a silent
nil at first use, mid-fight.

**Consequence:** every file executes at startup. Anything relying on deferred loading does not work
here; see A2.

**Enforced by** `test/checks/manifest.lua` — a `.lua` on disk but absent from `incha.txt` never runs.

---

## A2 · Module unloading was removed because it reclaimed nothing

*2026-09 · reversal of an earlier decision*

`core/ModuleLoader.lua`, the `trialModules(prefix)` helper and the `unloadList` plumbing through
`ZoneManager` were deleted.

**Why it could not work.** Given A1, every file already ran. Each Factory builds its `Trial` at file
scope and `ZoneManager` holds it in `trials[zoneId].module` for the session, so every boss class,
routing table and constant stays reachable regardless. Clearing `package.loaded` on zone exit freed
the cache *keys* and nothing else — while reading to the next maintainer as if it were managing
memory. `ModuleLoader.loadScoped`, the function that would have made it real, had no callers.

**What a real fix needs:** build Trials lazily on zone entry, which means restructuring every Factory
to return a constructor rather than a ready-made instance.

**Revisit when** the resident set actually matters. For ~15k lines of Lua it is a few hundred KB of
tables, so not yet.

---

## A3 · Wipe and leave are different operations

*2026-08 · settled*

`onWipe` is a **soft** reset — stop bars, clear per-pull flags, hide position icons. `onLeave` is a
**full** teardown — discard icons, unregister events.

The distinction is the one most encounter addons get wrong. Collapsing them means either leaking
icons across pulls or destroying markers players still need between attempts.

**The subtle part:** `Trial` keeps the **same boss instance** across a wipe. It calls
`cancelPending()` then `onWipe()` and does not rebuild, because the boss is still active and
`onEnter` is not re-run. So a `stateSchema` field returns to its starting value **only if `onWipe`
touches it** — an armed `Timer` will otherwise keep counting down a mechanic from the pull that
already ended.

**Enforced by** `test/checks/state-reset.lua`.

**Trap:** `k = nil` in a `stateSchema` declares nothing — Lua drops nil keys from a table
constructor, so `BossBase.fromSchema` never sees the field. Write `= false` or `= 0`. Three fields
in the tree still get this wrong and the check cannot see them (#113).

---

## A4 · Rendering is decoupled behind two small interfaces

*2026-08 · settled · row API changing, see #137*

`AlertSink` defines the alert vocabulary; `Bridge` defines five lifecycle hooks with **no-op
defaults**, so `Trial` calls every hook unconditionally and no call site needs a nil guard.
A boss module never touches a control.

**Rules out** boss code that reaches into the panel, which would make a second renderer impossible
and every boss a UI dependency.

**Pending change:** the row API is positional (`setRow(n, ...)`), which forces a compound module to
hand-partition the seven rows. Moving to `setRow(key, name, eta, priority)` — the caller says *what*
and *how urgent*, the panel decides *where* — is a prerequisite for A9, and makes a cleared row
simply absent rather than a blank slot.

---

## A5 · Combat and effect events are registered per ability id

*2026-09 · settled*

`EVENT_COMBAT_EVENT` and `EVENT_EFFECT_CHANGED` are the loudest events in the game — thousands per
second in a twelve-player trial. Both were once registered unfiltered, so every event crossed into
Lua to be discarded there.

`EventPipeline:setActiveBoss` now registers **one ability-filtered handler per routed id**, plus a
`REGISTER_FILTER_COMBAT_RESULT` registration for `ACTION_RESULT_DIED`, and tears them down on boss
change. There are no unfiltered combat or effect registrations anywhere.

**What this constrains, permanently:** an ability id absent from a routing table (or from a common
module's `combatAbilityIds` / `effectAbilityIds`) is **never registered and never dispatched**. Its
handler is dead code that reads as live. This is the project's most common defect class — see
#109 and #110.

**Requires** boss route sets and common ability sets to stay **disjoint**, since one filtered handler
serves both. Common modules gate on the same table they export, so registration and dispatch cannot
drift apart.

**Enforced by** `test/checks/filters.lua`.

---

## A6 · Optional dependencies are injected, not read from globals

*2026-09 · settled, with a known tradeoff*

`external-api/` holds one gateway per third-party addon (CombatAlerts, OdySupportIcons). Each keeps
a private `_impl`, injected once from `incha.lua`'s `OnAddOnLoaded`, and silently no-ops until then.
No module outside that tier references `OSI` or `CombatAlerts` directly.

**Better than** the previous wrappers, which tested the global at every call site: the dependency is
explicit, the no-op state is deliberate rather than incidental, and the layer is testable with a stub.

**The tradeoff:** binding moved from late to early. The old form picked up a global whenever it
appeared; the gateway captures it once. If a dependency publishes its global after Incha's load
event, every icon and cast bar stays off for the session with no error. `## OptionalDependsOn`
guarantees load *order*, not that the global is assigned by then. Tracked as #112.

---

## A7 · The engine prevents lifecycle mistakes rather than documenting them

*2026-09 · settled*

Two cases where "the boss author must remember" became "the engine does it":

- **`BossBase.fromSchema` links the class to `BossBase`** when the boss file did not. Four classes
  had forgotten the `setmetatable` line, so `cleanupAlertList` resolved to nil and threw on every
  wipe and zone exit, and the default `onDied` was missing so their cast bars were never stopped.
- **`BossBase:after(ms, fn)` replaces bare `zo_callLater`.** Handles are recorded on the instance and
  cancelled by `cancelPending()`, which `Trial` calls on wipe and boss exit. A raw deferred closure
  outlives the pull that scheduled it — it either fires into a reset raid or reads a guard flag on a
  discarded instance.

**Principle:** where a comment says "remember to...", prefer changing the engine so forgetting is
impossible, or adding a check that fails when it happens. Every check in `test/checks/` exists
because its bug shipped once.

---

## A8 · Translations are display data and must not drive logic

*2026-09 · decided, not yet implemented — #134*

`lang/` + `core/Lang.lua` + `core/Fmt.lua` hold user-visible strings. `Lang.t` returns the key when
a string is missing, so gaps are visible on screen rather than blank. `Fmt` keeps `|cRRGGBB` markup
and format specifiers out of the table so translators see prose.

**The rule:** a translator must be able to edit `lang/*.lua` freely with no functional effect.

**Currently violated.** 23 boss detection fields read the display table
(`nameAliases = { Lang.t("boss_zmaja") }`), so a translation string decides whether an encounter
activates. That is also self-defeating as i18n: adding `lang/de.lua` changes what detection compares
against, making the string table a second, invisible detection contract.

**Direction:** locale-independent detection — arena bounding boxes (#123) and ability-id signature
detection. The unwired `SIRO_IDS` / `RELE_IDS` / `GALE_IDS` sets in `ZmajaEncounter` are a prototype
of the second (#109).

**Enforced by** `test/checks/lang.lua` for duplicate, missing and orphan keys — not yet for the
coupling.

---

## A9 · Concurrent bosses: adopt `Trial.activeBosses`

*2026-09 · decided, not yet implemented — #137*

AS and CR have several boss entities alive at once. Both currently use a **compound module** covering
every entity, originally chosen for being lower-risk.

**Reversing that.** The compound form hides its cost: `ZmajaEncounter` hand-partitions the seven
tracker rows one-per-entity and runs to 637 lines; `context.healthPercent` is assigned from whichever
`bossN` power update arrived last, so percentage-gated call-outs fire against an arbitrary entity;
and the static checks see one class, so the minis' per-pull state is invisible to the check meant to
guarantee it resets.

**Decision:** `Trial.activeBosses`, a list that is length 1 for the seven single-boss trials so their
behaviour is unchanged by construction. Each entity becomes an ordinary boss module.

**Prerequisite:** keyed tracker rows (A4), which removes the row-allocation problem entirely rather
than solving it.

**Measured, not assumed:** no two bosses in any trial currently route the same ability id, and
genuinely shared abilities already belong in the trial's `*Common.lua`. Dispatch fan-out is therefore
not needed until an encounter proves otherwise.

---

## A10 · Static checks are domain-specific, and a check that cannot fail is not a gate

*2026-09 · settled*

Ten checks run in CI, most encoding a bug that shipped once: a setting with no reader, per-pull state
that survives a wipe, ability sets that overlap, a string-table key defined twice.

**Two lessons paid for:**

- **Fail closed.** `globals.lua` once reported clean when its scan produced no output — a broken
  toolchain passed silently. It now treats "no listing" as a finding, and derives its file list from
  `incha.txt` rather than a hardcoded directory list that had never scanned `external-api/`.
- **A generic linter earns its place.** All ten bespoke checks pass on a tree containing a live crash
  in Bahsei hardmode (#107). luacheck's `W411` caught it, and luacheck is advisory (#111). Checks
  encoding yesterday's failures are regression nets, not discovery tools.

---

## Resolved questions

Kept so they are not reopened.

- **`core/` must not depend on `ui/`** — resolved. `core/Bridge.lua` lives in `core/`; both
  `core/Trial.lua` and `ui/Panel.lua` require it.
- **Module-level mutable state in `*Common` files** — resolved for the only case that had it.
  `OsseinCageCommon` keeps `_toxicIreLastMs` and `_carrionStacks` as upvalues, which survive wipes;
  it exports `reset()` and all three OC bosses call it from `onWipe`. No other common module holds
  mutable state.
- **OSI dependency** — resolved by A6. `## OptionalDependsOn` remains in the manifest and all OSI
  traffic goes through `external-api/`.
