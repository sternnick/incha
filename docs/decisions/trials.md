# Trial decisions

Per-trial facts that are not obvious from the code: how each encounter is detected, what shape it
has, and where the mechanics were derived from.

**Not here:** ability ids and constants. The boss modules are the source of truth for those —
81% of the ids the old ROADMAP carried were already declared in source, and the copy had begun to
drift. Research for mechanics *not yet implemented* lives on the trial's issue.

Engine-wide decisions are in [`architecture.md`](architecture.md).

---

## Detection strategy

A trial activates when `ZoneManager` matches the zone id. A *boss* activates by one of two routes,
tried in order:

1. **Arena bounding box** — `Boss.location`, an AABB tested against `GetUnitWorldPosition`.
   Locale-independent and unambiguous.
2. **Unit name** — `Boss.name` / `Boss.nameAliases` compared against `GetUnitName`.

Only the three KA bosses declare an AABB. The other 22 rely entirely on name matching, which
currently reads the translation table and therefore fails on a non-English client — see A8 and
#134. Capturing the missing bounds is #123.

To capture one, stand at each corner of the arena:

```
/script local _,x,y,z = GetUnitWorldPosition("player"); d(x..", "..y..", "..z)
```

**Note the leading `_`.** `GetUnitWorldPosition` returns **four** values — `zoneId, x, y, z`. The
form `local x,y,z,_ = ...` binds `x` to the zone id and `z` to the vertical axis, so every bound
measured that way is wrong. `lib/MapUtils.lua` shipped exactly that bug and the old ROADMAP
documented the broken form as the recipe.

Zone id for a trial not listed below:

```
/script d(GetZoneId(GetUnitZoneIndex("player")))
```

`GetCurrentMapZoneIndex()` returns the zone *index*, a different number. Do not use it.

---

## Trials

| Trial | Zone | Encounter shape | Reference addons |
|---|---|---|---|
| **KA** Kyne's Aegis | 1196 | 3 sequential | BSCHTKA (retired as a runtime dependency) |
| **SS** Sunspire | 1121 | 3 sequential | — |
| **RG** Rockgrove | 1263 | 3 sequential | `QcellRockgroveHelper` |
| **DSR** Dreadsail Reef | 1344 | 3 sequential; boss 1 is a **pair** | `QcellDreadsailReefHelper` (QDRH) |
| **AS** Asylum Sanctorium | 1000 | **concurrent** — see below | `AsylumPriorityTarget`, `AsylumTracker` |
| **CR** Cloudrest | 1051 | **concurrent** — see below | `HowToCloudrest` |
| **SE** Sanity's Edge | 1427 | 3 sequential | `SanitysEdgeHelper` (SEH), `SlipsSanitysEdgeAssist` (SSEA) |
| **LC** Lucent Citadel | 1478 | 5–6 sequential | `LucentCitadelHelper` (LCH), `LucentCitadel` |
| **OC** Ossein Cage | 1548 | 3 sequential | `OsseinCageHelper` (OCH), `AsquartOsseinCageHelper` |

Zone ids for CR, LC and OC were confirmed in game. The rest are long-standing and treated as
confirmed until a misfire is reported.

---

## KA — the reference implementation

The only trial where detection, hardmode thresholds and marker coordinates were all measured rather
than estimated. It is the model for what "done" looks like:

- three arena AABBs, so detection needs no names;
- measured HM pools (`Falgravn 248386060`, `Yandir` / `Vrol 72769370`);
- no runtime dependency on BSCHTKA — the legacy bridge was deleted, and a one-time settings import
  runs if BSCHTKA is present so existing users keep their preferences.

**Open:** the Falgravn OSI floor-marker coordinates do not sit inside Falgravn's own arena AABB.
The node tables use `x 22,300–27,796` / `z 7,114–12,970` while the box is `x 73,700–84,500` /
`z 50,200–61,900`; only the *y* values agree. Vrol's portal icon *does* sit inside Vrol's box, so
the convention is right elsewhere and the Falgravn tables look inherited without re-measurement.
`checkNodeCoordSpace()` prints the comparison under `/incha debug`. See #126.

---

## DSR — the dual-boss pair

Boss 1 is Lylanar **and** Turlassil, fighting simultaneously. Both are handled in one module with
`nameAliases = { Lylanar, Turlassil }` so detection fires regardless of which the engine reports as
`boss1`.

This is a genuine pair rather than the AS/CR concurrent case: the two share a health pool and a
phase, so one module is the right shape and A9 does not apply.

---

## AS and CR — the concurrent-boss trials

Both have several entities alive at once, and both currently use a single compound module:

```
trial/as/boss/OlmsEncounter.lua    Saint Olms + Llothis + Felms
trial/cr/boss/ZmajaEncounter.lua   Z'Maja + Siroria / Relequen / Galenwe
```

**AS.** Olms is always present; Llothis and Felms are simultaneous adds with their own cooldowns.

**CR.** Supports +0/+1/+2/+3 variants — the number of mini-bosses left alive when Z'Maja is engaged
changes the fight. The minis are Siroria (fire), Relequen (lightning) and Galenwe (frost).
`ZmajaEncounter` declares `SIRO_IDS` / `RELE_IDS` / `GALE_IDS` — ability sets whose purpose is
*"any of these firing marks that mini as active"* — but nothing references them, so variant
detection does not work (#109). Those sets are also a working prototype of the locale-independent
detection A8 wants.

**Both are being restructured** under A9 (#137): `Trial.activeBosses` with one module per entity.
Their mechanics are the least implemented of the nine trials, which is why the decision is being
made before that work rather than after — #129 and #130 are blocked on it.
