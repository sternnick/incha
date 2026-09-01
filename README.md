# Incha

An Elder Scrolls Online addon that provides a real-time mechanics overlay for veteran trials. Tracks boss abilities, timers, and mechanic assignments and displays them on a draggable HUD panel.

## Supported trials

| Trial | Status |
|---|---|
| Kyne's Aegis (KA) | ✅ Feature-complete |
| Rockgrove (RG) | 🔄 In progress |
| Dreadsail Reef (DSR) | 🔄 In progress |
| Asylum Sanctorium (AS) | 🔄 In progress |
| Cloudrest (CR) | 🔄 In progress |
| Sanity's Edge (SE) | 🔄 In progress |
| Lucent Citadel (LC) | 🔄 In progress |
| Ossein Cage (OC) | 🔄 In progress |
| Sunspire (SS) | 🔄 In progress |

## Optional dependencies

The addon works standalone. These libraries unlock additional features:

- **LibAddonMenu-2.0** — settings panel (in-game UI to configure the overlay). Without it the `/incha` slash command is still available.
- **OdySupportIcons (OSI)** — mechanic icons on players and world positions (unit frames, floor markers).
- **CombatAlerts** — screen-border flash alerts for high-priority mechanics.

Install via [Minion](https://minion.mmoui.com/) or manually from [ESOUI](https://www.esoui.com/).

## Installation

1. Download or clone this repository into your ESO addon folder:
   ```
   Documents\Elder Scrolls Online\live\AddOns\incha\
   ```
2. The folder **must** be named `incha` (lowercase). ESO derives `ADDON_NAME`
   from the folder name — not from the manifest — and `bootstrap.lua:15-19`
   builds the log prefix, slash command and saved-variable name from it.
3. Launch ESO and enable **Incha** in the addon manager.

## Usage

- The overlay panel appears automatically when you enter a supported trial.
- Drag to reposition; position and scale are saved per account.
- `/incha` opens the settings panel (or the slash-command fallback if LAM is not installed).

---

## Contributing

### Branch naming

All branches must follow one of these patterns:

```
feature/<short-description>
fix/<short-description-or-id>
```

Examples: `feature/se-ansuul-mechanics`, `fix/vrol-fog-timer`.

**Pull requests from branches that do not follow this convention will be closed without review.**

Direct commits to `master` are blocked — all changes must go through a pull request.

### Merge strategy

PRs are merged with a standard merge commit. Squash and rebase merges are disabled. This preserves the full branch history.

### Local hook (enforce naming before push)

To catch naming violations before they reach GitHub, set up the pre-push hook:

```bash
git config core.hooksPath .githooks
```

> **Note:** Git hooks are not applied automatically on clone — you must run this command once after cloning. The hook rejects pushes from branches that don't match `feature/*` or `fix/*`.

### Workflow

```
git checkout -b feature/my-new-thing
# ... make changes, commit ...
git push origin feature/my-new-thing
# open a PR on GitHub targeting master
```

---

## Project layout

```
bootstrap.lua          addon entry point
incha.lua              main event wiring
incha.txt              ESO manifest

lib/                   shared primitives (Timer, Log, Throttle, CastDur, BossBase, …)
core/                  engine (BossRegistry, CombatHandler, EventPipeline, Settings, …)
ui/                    overlay panel and settings menu
trial/<id>/            per-trial modules
  boss/<Name>.lua      per-boss combat handlers
  Factory.lua          trial setup / zone detection and boss order
test/                  offline test harness
```

## Development notes

- Boss modules implement `onCombatEvent`, `onEffectChanged`, `onUpdate`, and `reset` via `BossBase`.
- `stateSchema` on each boss defines the saved-variable shape for per-boss persistence.
- Zone IDs and boss name strings that are marked TBD in ROADMAP.md require in-game verification — see the [verification backlog](ROADMAP.md#in-game-verification-backlog).
- OSI calls must always be nil-guarded; the dependency is optional.

See [ROADMAP.md](ROADMAP.md) for the full implementation plan and open architecture questions.
