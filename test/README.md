# Incha Integration Tests

Replays real ESO encounter logs through the live boss modules and prints every
alert the addon would have fired.  **Phase 1** — smoke / run-without-errors.
Assertions (expected alerts vs actual) come in Phase 2.

---

## Requirements

**LuaJIT** (ESO uses a modified Lua 5.1; LuaJIT is compatible):

```bash
winget install DEVCOM.LuaJIT
```

After installation open a new terminal so `luajit` is on PATH.

---

## Running

Run from the **repository root**:

```bash
luajit test/run_log.lua <log_file> [zone_id]
```

| Argument | Description |
|----------|-------------|
| `log_file` | Path to an ESO encounter log (`.log`). Archive logs work fine. |
| `zone_id` | Optional. Force a specific trial zone (e.g. `1196` for Kyne's Aegis). When omitted, the first recognised trial zone in the log is used. |

### Example

```bash
luajit test/run_log.lua "C:/Users/.../ESO/live/Logs/esologsarchive/Archive-20260816T165207Z-Encounter.log" 1196
```

Sample output:

```
Reading log: …/Archive-20260816T165207Z-Encounter.log
Parsed 2104792 entries (0 parse errors)
Target trial: KA (zone 1196)

=== Trial: KA (zone 1196) ===
[ 1290453ms] BOSS    Yandir the Butcher activated (key=yandir)
[ 1686788ms] BOSS    Yandir the Butcher removed
[ 2617806ms] BOSS    Captain Vrol activated (key=vrol)
[ 2799498ms] ACTION  KILL Conjurer! (20 s)
[ 2812438ms] ACTION  Portal OK!
…
── Summary ─────────────────────────────────────────────
  COMBAT_EVENT entries processed :  306385
  EFFECT_CHANGED entries processed: 983833
  Bosses activated                :      10
  Alerts fired                    :      19
  Handler errors                  :       0
```

Exit code `0` = clean run.  Exit code `1` = at least one handler threw an error.

---

## Known zones

| Zone ID | Trial |
|---------|-------|
| 1196 | Kyne's Aegis (KA) |
| 1121 | Sunspire (SS) |
| 1263 | Rockgrove (RG) |
| 1344 | Dreadsail Reef (DSR) |
| 1000 | Asylum Sanctorium (AS) |
| 1051 | Cloudrest (CR) |
| 1427 | Sanity's Edge (SE) |
| 1478 | Lucent Citadel (LC) |
| 1548 | Ossein Cage (OC) |

---

## Architecture

```
test/
  harness/
    eso_api.lua       All ESO global stubs (constants, EVENT_MANAGER, unit
                      queries, zo_callLater, …) + pre-stubs for ui.Panel,
                      ui.Menu, core.Settings so they load without a game client.
    unit_tracker.lua  Tracks UNIT_ADDED / UNIT_REMOVED and resolves numeric
                      unit IDs → ESO tags ("player", "boss1", "group3", …).
    log_reader.lua    Parses the ESO encounter log CSV format into a flat list
                      of typed event tables.
  run_log.lua         Entry point.  Builds a real Trial with live boss modules,
                      replays all log events, prints alerts and a summary.
```

### How boss detection works

ESO detects the active boss via `EVENT_BOSSES_CHANGED` + world position or unit
name.  In the harness neither is available, so the runner uses a **direct
injection** strategy:

1. Every `UNIT_ADDED` with `isBoss=T` is looked up in the `TRIAL_CONFIG.hints`
   table (a log-unit-name → boss-key map) or via `BossRegistry:findByName` for
   bosses that declare a `.name` field.
2. If the boss class is found, `trial.activeBoss` is set to a fresh instance and
   `boss:onEnter(context, alerts)` is called — identical to what the real addon
   does after `EVENT_BOSSES_CHANGED`.

### What is stubbed

| ESO global | Stub behaviour |
|------------|---------------|
| `EVENT_MANAGER` | All methods are no-ops; events fire directly in the replay loop instead. |
| `GetGameTimeMilliseconds()` | Returns the current log entry's ms offset. |
| `GetZoneId` / `GetUnitZoneIndex` | Returns the trial zone ID set from `ZONE_CHANGED` entries. |
| `GetUnitWorldPosition` | Returns `(0,0,0,0)` — position-based boss detection falls back to name lookup. |
| `DoesUnitExist` / `GetUnitName` / `GetUnitDisplayName` | Delegate to `UnitTracker`. |
| `GetUnitPower` | Returns health from tracker if known, otherwise `(0,0,0)`. |
| `IsUnitInCombat` | Always `false`. |
| `zo_callLater` | Returns a handle but **does not execute the callback** (callbacks fire long after the triggering event and their own guards would make them no-ops anyway). |
| `CombatAlerts` / `OSI` | `nil` — all `CA.*` calls and `OSI.*` calls are silently skipped by existing guards. |
| `ui.Panel` / `ui.Menu` | Thin stubs; alerts are re-routed to the runner's print callbacks. |
| `core.Settings` | Returns all options enabled. |

---

## Phase 2 roadmap

- **Snapshot tests**: record alert output per boss encounter, save as fixture
  files, and assert future runs produce identical output.
- **Per-ability coverage**: count which `combatRoutes` / `effectRoutes` entries
  were exercised; flag dead entries with no log matches.
- **Cross-trial runs**: auto-detect and replay all trial zones found in a single
  log file.
