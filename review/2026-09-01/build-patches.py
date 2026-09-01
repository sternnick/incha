#!/usr/bin/env python3
"""Build the suggested-patch series for the Incha code review.

    python3 .review/build-patches.py --work /tmp/incha-work --out /tmp/incha/.review/patches

Creates one local branch per suggested change on top of the reviewed commit
(BASE below), commits it, and exports `git am`-compatible patches plus a
combined patch for each independent group.

Safety contract:
  * the target must be a *separate* clone; the script refuses to run inside a
    tree that has no `.git` of its own or that is the reviewed checkout;
  * every edit is an exact string replacement guarded by an assertion, so an
    upstream line move fails the build loudly instead of being guessed at;
  * nothing is pushed. Patch files are the deliverable.
"""

import argparse
import os
import re
import subprocess
import sys

BASE = "66977e3077bd4d046ca3621fc98c1754e8235651"

BOM_FILES = [
    "trial/as/boss/OlmsEncounter.lua",
    "trial/cr/boss/ZmajaEncounter.lua",
    "trial/lc/boss/DarielEncounter.lua",
    "trial/lc/boss/OrphicEncounter.lua",
    "trial/lc/boss/RyelazEncounter.lua",
    "trial/lc/boss/XorynEncounter.lua",
    "trial/lc/boss/XynizataEncounter.lua",
    "trial/oc/boss/KazpianEncounter.lua",
    "trial/oc/boss/ShaperEncounter.lua",
]


# --------------------------------------------------------------------------- helpers
def git(work, *args):
    r = subprocess.run(["git", "-C", work] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(args), (r.stderr or r.stdout).strip()))
    return r.stdout


def rd(work, rel):
    with open(os.path.join(work, rel), encoding="utf-8") as fh:
        return fh.read()


def wr(work, rel, text):
    path = os.path.join(work, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def sub(work, rel, old, new, count=1):
    src = rd(work, rel)
    n = src.count(old)
    if n != count:
        raise AssertionError("%s: expected %d occurrence(s) of %r, found %d"
                             % (rel, count, old[:70], n))
    wr(work, rel, src.replace(old, new))


def commit(work, branch, message, files, parents_away_from=None):
    git(work, "checkout", "-q", "-B", branch, BASE)
    for f in files:
        git(work, "add", "--", f)
    git(work, "-c", "user.name=sternnick review", "-c", "user.email=review@localhost",
        "commit", "-q", "-m", message, "--", *files)
    return git(work, "rev-parse", "--short", "HEAD").strip()


def commit_more(work, message, files):
    git(work, "add", "--", *files)
    git(work, "-c", "user.name=sternnick review", "-c", "user.email=review@localhost",
        "commit", "-q", "-m", message, "--", *files)
    return git(work, "rev-parse", "--short", "HEAD").strip()


def trailer(fixes, verified="static analysis only - not run in-game"):
    return ("\n\nEvidence, exact line numbers and the reproduction command are in "
            ".review/code-review-2026-09-01.md (see finding %s).\n"
            "Verification: %s." % (fixes, verified))


# --------------------------------------------------------------------------- patch 1
def patch_bom(work):
    for rel in BOM_FILES:
        raw = open(os.path.join(work, rel), "rb").read()
        if not raw.startswith(b"\xef\xbb\xbf"):
            raise AssertionError("%s has no BOM - upstream already fixed F-01?" % rel)
        open(os.path.join(work, rel), "wb").write(raw[3:])
    return commit(
        work, "fix/strip-utf8-bom",
        "fix: strip UTF-8 BOM from 9 encounter modules\n\n"
        "A BOM is not part of Lua's grammar. Lua's own command-line loader skips a\n"
        "leading BOM, but an embedded loader that hands the raw file body to\n"
        "lua_load()/luaL_loadstring() can fail at 1:1 instead. If ESO's loader does\n"
        "that, the nine files below never register and the require() from\n"
        "bootstrap.lua:29-33 raises \"module not registered\" for the AS, CR, LC and\n"
        "OC Factories - those four trials load dead with no visible error beyond a\n"
        "chat line.\n\n"
        "Byte-level change only: 3 bytes removed at offset 0 of each file.\n"
        "Gate: tools/static_checks.py (also added by feature/ci-static-validation)."
        + trailer("F-01"),
        BOM_FILES)


# --------------------------------------------------------------------------- patch 2
def patch_panel(work):
    sub(work, "ui/Panel.lua",
        '    hideAction = function()\n'
        '        if not ctrl then return end\n'
        '        ctrl.action:SetText("")\n',
        '    hideAction = function()\n'
        '        if not ctrl then return end\n'
        '        ctrl.action:SetText("")\n'
        '        ctrl.actionText = ""   -- keep the action= diff cache in sync\n')
    commit(work, "fix/panel-cache-and-control-name",
        "fix(ui): reset the action-text cache in hideAction\n\n"
        "The action handler compares the new text against ctrl.actionText before\n"
        "calling SetText, but hideAction cleared the label without clearing that\n"
        "cache. The next identical action text therefore compares equal and is\n"
        "never re-painted, leaving the action line permanently blank.\n\n"
        "Reachable today: Trial.lua:186-192 calls hideAction() whenever no health\n"
        "rule matches, and Falgravn sets hideActionWhenNoRule, so the cycle is\n"
        "'rule text -> blank -> same rule text' inside a single pull."
        + trailer("F-08"),
        ["ui/Panel.lua"])

    sub(work, "ui/Panel.lua",
        'CreateControl("InchPanel", GuiRoot, CT_CONTROL)',
        'CreateControl("Incha_Panel", GuiRoot, CT_CONTROL)')
    commit_more(work,
        "fix(ui): name the overlay root control Incha_Panel\n\n"
        "ESO only exposes global controls whose names begin with the addon's own\n"
        'name (ADDON_NAME comes from the folder, so "incha"/"Incha" here - see\n'
        "bootstrap.lua:15-19). \"InchPanel\" matches neither form, so the control is\n"
        "created but not registered as a global and ESO logs a warning. Renaming\n"
        "costs nothing: ui/Panel.lua keeps the object in the local `ctrl`, no other\n"
        "file mentions the name, and nothing reads it back.\n\n"
        "UNVERIFIED assumption: that ESO rejects or warns on a non-conforming name.\n"
        "Worth one /reloadui + /eventtrace check before merging.",
        ["ui/Panel.lua"])


# --------------------------------------------------------------------------- patch 3
TRIAL_REQUIRES = 'local BridgeBase   = require("core.Bridge")'


def patch_falgravn(work):
    sub(work, "trial/ka/boss/Falgravn.lua",
        '        self.bHM = true\n'
        '        alerts:showHeader(GetUnitName("boss1") .. " [HM: ON]")\n'
        '    elseif result == ACTION_RESULT_EFFECT_FADED then\n'
        '        alerts:showHeader(GetUnitName("boss1"))\n',
        '        self.bHM = true\n'
        '        alerts:showHeader(bossName(context) .. " [HM: ON]")\n'
        '    elseif result == ACTION_RESULT_EFFECT_FADED then\n'
        '        alerts:showHeader(bossName(context))\n')
    sub(work, "trial/ka/boss/Falgravn.lua",
        '-- HM confirmation ability (plain entry: receives result).\n'
        'local function handleFalgravnHm(self, context, alerts, result, abilityId, ...)',
        '--- Header name for the unit we actually tracked (F-02/F-03): "boss1" is only\n'
        '--- correct while Falgravn is the first occupied slot.\n'
        'local function bossName(context)\n'
        '    return GetUnitName(context.bossUnitTag or "boss1")\n'
        'end\n'
        '\n'
        '-- HM confirmation ability (plain entry: receives result).\n'
        'local function handleFalgravnHm(self, context, alerts, result, abilityId, ...)')


def build_boss_slot(work):
    patch_boss_slot_body(work)
    patch_falgravn(work)
    return commit(work, "fix/boss-slot-and-alert-hygiene",
        "fix(core): track which boss slot the active boss occupies; clear stale alerts\n\n"
        "Three one-file-apart defects in the single-active-boss branch:\n\n"
        "1. EventPipeline forwards unitTag but Trial dropped it, and the health poll\n"
        "   and the HM threshold read a literal \"boss1\". With two units in slots\n"
        "   (Ryelaz+Zilyesset, Lylanar+Turlassil) the overlay can show the wrong\n"
        "   percentage and detect difficulty off the wrong pool. context.bossUnitTag\n"
        "   now carries the matched slot, mechanics use it (Falgravn's header), and\n"
        "   power ticks from other slots are ignored.\n"
        "2. onBossesChanged never cleared the AlertSink on a boss-to-boss change, so\n"
        "   the previous boss's info/action lines stayed visible.\n\n"
        "Position-only detection (KA) keeps working: bossSlot stays nil when the slot\n"
        "cannot be resolved by name, and every read falls back to \"boss1\"."
        + trailer("F-02, F-03, F-07"),
        ["core/Trial.lua", "core/TrialContext.lua", "trial/ka/boss/Falgravn.lua"])


# --------------------------------------------------------------------------- patch 4
def patch_hm_aid(work):
    # deliberately no file-scope locals here: `require` resolves from the loader
    # cache, and the per-trial warned set lives on the instance, so this patch
    # touches only Trial:enable() and stays independent of the other Trial patch.
    sub(work, "core/Trial.lua",
        '    self.enabled = true\n'
        '\n'
        '    self.bridge.onEnable()',
        '    self.enabled = true\n'
        '\n'
        '    -- 16 of 25 boss modules still carry a placeholder hmHealthThreshold and 42\n'
        '    -- context.isHM gates depend on it: a wrong boundary silently shows or hides\n'
        '    -- whole mechanic displays. Say so once per boss per session so the value\n'
        '    -- gets measured (see /incha hp) instead of guessed.\n'
        '    if not self.hmThresholdWarned then\n'
        '        self.hmThresholdWarned = {}\n'
        '    end\n'
        '    for _, boss in ipairs(self.registry.bosses) do\n'
        '        local th = boss.hmHealthThreshold\n'
        '        if (th == nil or th == math.huge or th == 100000001)\n'
        '           and not self.hmThresholdWarned[boss.key] then\n'
        '            self.hmThresholdWarned[boss.key] = true\n'
        '            require("lib.Log").warn(\n'
        '                "%s/%s: hmHealthThreshold = %s - hardmode detection is a guess. "\n'
        '                .. "Pull the boss once in normal and once in hardmode, run "\n'
        '                .. "/incha hp for each, and set the threshold between them.",\n'
        '                self.id, boss.key, tostring(th))\n'
        '        end\n'
        '    end\n'
        '\n'
        '    self.bridge.onEnable()')

    sub(work, "ui/Menu.lua",
        '    d("  " .. ADDON_SLASH .. " reset          -  reset overlay to default position")\n',
        '    d("  " .. ADDON_SLASH .. " reset          -  reset overlay to default position")\n'
        '    d("  " .. ADDON_SLASH .. " hp             -  print boss slot health pools "\n'
        '        .. "(for hmHealthThreshold)")\n')

    sub(work, "ui/Menu.lua",
        '    elseif cmd == "preview" then',
        '    elseif cmd == "hp" then\n'
        '        -- Measure hmHealthThreshold in one pull: the pool is what\n'
        '        -- BossRegistry:detectDifficulty compares against, and it cannot be\n'
        '        -- read from a log file.\n'
        '        d(ADDON_TAG .. " boss slot health pools:")\n'
        '        for _, slot in ipairs({ "boss1", "boss2", "boss3", "boss4" }) do\n'
        '            if DoesUnitExist(slot) then\n'
        '                local cur, max, eMax = GetUnitPower(slot, POWERTYPE_HEALTH)\n'
        '                cur, max, eMax = tonumber(cur) or 0, tonumber(max) or 0,\n'
        '                    tonumber(eMax) or 0\n'
        '                d(string.format("  %s  %-24s max=%d  effectiveMax=%d  %.1f%%",\n'
        '                    slot, tostring(GetUnitName(slot)), max, eMax,\n'
        '                    max > 0 and (cur / max * 100) or 0))\n'
        '            else\n'
        '                d("  " .. slot .. "  (empty)")\n'
        '            end\n'
        '        end\n'
        '        d("  set hmHealthThreshold between the normal and hardmode values.")\n'
        '\n'
        '    elseif cmd == "preview" then')
    return commit(work, "fix/hardmode-measurement-aid",
        "fix(core): make placeholder HM thresholds loud, and measurable\n\n"
        "detectDifficulty() compares the boss's max health against\n"
        "hmHealthThreshold. 7 modules set math.huge (hardmode can never be\n"
        "detected), 5 set the 100000001 placeholder, 4 have no field at all, and\n"
        "42 context.isHM gates in Lylanar/Taleria/Bahsei/Xalvakka branch on the\n"
        "result. The values are unmeasurable offline, so instead of guessing again\n"
        "this makes the gap visible in chat and adds \"/incha hp\" to read the real\n"
        "pools from a single pull.\n\n"
        "No behaviour change for the 9 modules with a real threshold."
        + trailer("F-04, F-18"),
        ["core/Trial.lua", "ui/Menu.lua"])


# --------------------------------------------------------------------------- patch 5
def patch_live_enable(work):
    sub(work, "core/ZoneManager.lua",
        'function ZoneManager.onZoneChanged()\n'
        '    enableTrialForZone(getPlayerZoneId())\n'
        'end',
        'function ZoneManager.onZoneChanged()\n'
        '    enableTrialForZone(getPlayerZoneId())\n'
        'end\n'
        '\n'
        '--- Re-evaluate the zone the player is standing in against current settings.\n'
        '--- Called from the per-trial Enable checkboxes so a toggle takes effect\n'
        '--- immediately; until now .enabled was only consulted at zone-enter time,\n'
        '--- which meant the checkbox did nothing until you left and re-entered the\n'
        '--- trial (or reloaded the UI).\n'
        'function ZoneManager.refresh()\n'
        '    local zoneId = getPlayerZoneId()\n'
        '    local entry  = trials[zoneId]\n'
        '    if not entry then\n'
        '        return\n'
        '    end\n'
        '\n'
        '    local sv  = Settings.get()\n'
        '    local tsv = sv and entry.trialId and sv.trials[entry.trialId]\n'
        '    local wanted = not (tsv and tsv.enabled == false)\n'
        '\n'
        '    if not wanted and activeTrial == entry.module then\n'
        '        disableCurrentTrial()\n'
        '    elseif wanted and activeTrial ~= entry.module then\n'
        '        enableTrialForZone(zoneId)\n'
        '    end\n'
        'end')

    sub(work, "ui/Menu.lua",
        'local Settings = require("core.Settings")\n',
        'local Settings    = require("core.Settings")\n'
        'local ZoneManager = require("core.ZoneManager")\n')

    # ZoneManager must load before ui/Menu.lua once Menu requires it (incha.txt
    # currently lists it after core/Trial.lua). Move, do not duplicate.
    sub(work, "incha.txt",
        'core/CombatHandler.lua\n'
        'core/Bridge.lua\n',
        'core/CombatHandler.lua\n'
        'core/Bridge.lua\n'
        'core/ZoneManager.lua\n')
    sub(work, "incha.txt",
        'core/Trial.lua\n'
        'core/ZoneManager.lua\n',
        'core/Trial.lua\n')

    for tid, tooltip in [
        ("ss", None), ("rg", None), ("dsr", None), ("as", None),
        ("cr", None), ("se", None), ("lc", None), ("oc", None)]:
        old = '        setFunc = function(v) Settings.get().trials.%s.enabled = v end,' % tid
        new = ('        setFunc = function(v)\n'
               '            Settings.get().trials.%s.enabled = v\n'
               '            ZoneManager.refresh()\n'
               '        end,' % tid)
        sub(work, "ui/Menu.lua", old, new)

    sub(work, "ui/Menu.lua",
        '    -- Section: Kyne\'s Aegis\n'
        '    {\n'
        '        type = "header",\n'
        '        name = "Kyne\'s Aegis",\n'
        '    },\n'
        '    {\n'
        '        type    = "checkbox",\n'
        '        name    = "Show boss panel",',
        '    -- Section: Kyne\'s Aegis\n'
        '    {\n'
        '        type = "header",\n'
        '        name = "Kyne\'s Aegis",\n'
        '    },\n'
        '    {\n'
        '        type    = "checkbox",\n'
        '        name    = "Enable",\n'
        '        tooltip = "Track Yandir/Vrol/Falgravn mechanics and the overlay for this trial.",\n'
        '        getFunc = function() return Settings.get().trials.ka.enabled end,\n'
        '        setFunc = function(v)\n'
        '            Settings.get().trials.ka.enabled = v\n'
        '            ZoneManager.refresh()\n'
        '        end,\n'
        '    },\n'
        '    {\n'
        '        type    = "checkbox",\n'
        '        name    = "Show boss panel",')

    return commit(work, "feature/live-trial-enable",
        "feature: apply per-trial Enable immediately; add the missing KA checkbox\n\n"
        "ZoneManager read .enabled only inside enableTrialForZone(), which runs on\n"
        "EVENT_PLAYER_ACTIVATED. Ticking a trial off mid-pull therefore changed\n"
        "nothing until the player left the zone. refresh() re-reads settings for the\n"
        "current zone and enables/disables the active trial; all nine Enable rows now\n"
        "call it.\n\n"
        "KA had no Enable row at all (Settings.DEFAULTS.trials.ka.enabled exists and\n"
        "ZoneManager honours it, but the panel never exposed it) - added for parity.\n\n"
        "incha.txt: core/ZoneManager.lua moves above ui/Menu.lua, because Menu now\n"
        "requires it and the loader resolves requires in manifest order (C-03 in\n"
        ".review/checks.py guards that ordering)."
        + trailer("F-09, F-24"),
        ["core/ZoneManager.lua", "ui/Menu.lua", "incha.txt"])


# --------------------------------------------------------------------------- patch 6
def patch_version(work):
    boot = rd(work, "bootstrap.lua")
    m = re.search(r"^ADDON_SLASH.*\n", boot, re.M)
    if not m:
        raise AssertionError("ADDON_SLASH line not found in bootstrap.lua")
    boot = boot[:m.end()] + 'ADDON_VERSION = "0.1.0"         -- single source of truth (README badge, LAM, chat)\n' + boot[m.end():]
    wr(work, "bootstrap.lua", boot)

    sub(work, "incha.lua",
        'd(ADDON_TAG .. " v0.1.0 loaded  -  " .. ADDON_SLASH .. " for commands")',
        'd(ADDON_TAG .. " v" .. ADDON_VERSION .. " loaded  -  " .. ADDON_SLASH\n'
        '      .. " for commands")')
    sub(work, "ui/Menu.lua", '    version             = "0.1.0",', '    version             = ADDON_VERSION,')
    sub(work, "incha.txt", "## Version: 0.0.1", "## Version: 0.1.0")
    return commit(work, "fix/single-version-source",
        "fix: one version constant, and make the manifest agree with it\n\n"
        "incha.txt says 0.0.1 while ui/Menu.lua:24 and the chat load line\n"  "incha.lua:51 both say 0.1.0,\n"
        "so the in-game addon list, the LAM panel and any bug report disagreed. The\n"
        "manifest cannot read Lua, so it stays a literal - the constant at least\n"
        "removes one of the two Lua copies."
        + trailer("F-17"),
        ["bootstrap.lua", "incha.lua", "ui/Menu.lua", "incha.txt"])


# --------------------------------------------------------------------------- patch 7
STATIC_CHECKS = '''#!/usr/bin/env python3
"""Static validation for the Incha addon (stdlib only, no network).

  python3 tools/static_checks.py            # exit 1 on any failure

Checks, in the order a failure would bite a player:
  1. encoding   - no UTF-8 BOM, no CRLF, no mojibake in any shipped file
  2. manifest   - every .lua on disk is listed in incha.txt exactly once
  3. load order - every require() target appears before its consumer
  4. naming     - created global controls start with the addon name
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXT_SUFFIXES = (".lua", ".txt", ".md")
FAILURES = []


def rel_paths():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".github", "node_modules")]
        for name in sorted(files):
            if name.endswith(TEXT_SUFFIXES):
                yield os.path.relpath(os.path.join(base, name), ROOT)


def read_bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as fh:
        return fh.read()


def fail(check, msg):
    FAILURES.append("%s: %s" % (check, msg))


def check_encoding():
    for rel in rel_paths():
        raw = read_bytes(rel)
        if raw.startswith(b"\\xef\\xbb\\xbf"):
            fail("encoding", "%s starts with a UTF-8 BOM (3 bytes at offset 0)" % rel)
        if b"\\r\\n" in raw:
            fail("encoding", "%s contains CRLF line endings" % rel)
        if b"\\xef\\xbf\\xbd" in raw or b"\\xc3\\xa2\\xc2\\x80" in raw:
            fail("encoding", "%s contains mojibake / replacement chars" % rel)


def manifest_files():
    with open(os.path.join(ROOT, "incha.txt"), encoding="utf-8") as fh:
        return [ln.strip() for ln in fh
                if ln.strip().endswith(".lua") and not ln.startswith("##")]


def check_manifest():
    listed = manifest_files()
    on_disk = sorted(p.replace(os.sep, "/") for p in rel_paths()
                     if p.endswith(".lua") and not p.startswith("test" + os.sep))
    missing = sorted(set(on_disk) - set(listed))
    ghost = sorted(set(listed) - set(on_disk))
    dupes = sorted({p for p in listed if listed.count(p) > 1})
    for m in missing:
        fail("manifest", "%s exists on disk but is not in incha.txt (never loaded)" % m)
    for g in ghost:
        fail("manifest", "incha.txt lists %s which does not exist" % g)
    for d in dupes:
        fail("manifest", "%s is listed more than once" % d)


def check_load_order():
    order = {p: i for i, p in enumerate(manifest_files())}
    bad = []
    for rel, idx in order.items():
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for target in re.findall(r'require\\("([^"]+)"\\)', src):
            t = target + ".lua"
            if t in order and order[t] > idx:
                bad.append("%s (line %d of manifest) requires %s listed later"
                           % (rel, idx + 1, target))
    for b in sorted(set(bad)):
        fail("load order", b)


def check_control_names():
    for rel in rel_paths():
        if not rel.endswith(".lua"):
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for m in re.finditer(r'CreateControl\\(\\s*"([^"]+)"', src):
            name = m.group(1)
            if not name.lower().startswith("incha"):
                line = src[:m.start()].count("\\n") + 1
                fail("naming", '%s:%d creates global control "%s" '
                     '(must start with the addon name)' % (rel, line, name))


def main():
    check_encoding()
    check_manifest()
    check_load_order()
    check_control_names()
    for f in FAILURES:
        print("FAIL " + f)
    print("%s: %d failure(s)" % ("FAILED" if FAILURES else "OK", len(FAILURES)))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
'''

SYNTAX_JS = '''// luaparse smoke test: every shipped .lua must parse.
//   npm i luaparse && node tools/syntax_check.js
const fs = require("fs");
const path = require("path");
const parser = require("luaparse");

const root = path.join(__dirname, "..");
const manifest = fs.readFileSync(path.join(root, "incha.txt"), "utf8")
  .split("\\n").map((l) => l.trim())
  .filter((l) => l.endsWith(".lua") && !l.startsWith("##"));

let bad = 0;
for (const rel of manifest) {
  const file = path.join(root, rel);
  if (!fs.existsSync(file)) { console.log(`MISSING ${rel}`); bad++; continue; }
  try {
    parser.parse(fs.readFileSync(file, "utf8"), { luaVersion: "5.1" });
  } catch (e) {
    console.log(`SYNTAX FAIL ${rel} -> ${e.message}`);
    bad++;
  }
}
console.log(`files: ${manifest.length}  failures: ${bad}`);
process.exit(bad ? 1 : 0);
'''

WORKFLOW = '''name: static-validation

on:
  push:
    branches: [master, "fix/*", "feature/*"]
  pull_request:

jobs:
  static:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.x"
      - name: encoding, manifest sync, load order, control names
        run: python3 tools/static_checks.py

  syntax:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: parse every shipped Lua file
        run: |
          npm init -y >/dev/null 2>&1 || true
          npm install --no-save luaparse@1.8.0
          node tools/syntax_check.js
'''

PRE_PUSH = '''#!/bin/sh
# Two push-time guards, both cheap and both offline:
#   1. branch naming: feature/* or fix/* (master is handled by branch protection)
#   2. encoding: a UTF-8 BOM in a .lua file can make ESO's loader reject the file
#      at 1:1, which silently kills a whole trial (see 2026-09-01 review, F-01).

branch=$(git symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||')

case "$branch" in
  feature/*|fix/*|master)
    ;;
  *)
    echo "ERROR: Branch '$branch' does not match naming rules."
    echo "       Use feature/<name> or fix/<name>."
    exit 1
    ;;
esac

bad=$(git diff --name-only --diff-filter=ACM "$@" 2>/dev/null | grep '\\.lua$')
[ -z "$bad" ] && bad=$(git ls-files '*.lua')
for f in $bad; do
  [ -f "$f" ] || continue
  if [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \\n')" = "efbbbf" ]; then
    echo "ERROR: $f starts with a UTF-8 BOM - strip it:"
    echo "       sed -i '1s/^\\xEF\\xBB\\xBF//' $f"
    exit 1
  fi
done

exit 0
'''


def patch_ci(work):
    wr(work, "tools/static_checks.py", STATIC_CHECKS)
    wr(work, "tools/syntax_check.js", SYNTAX_JS)
    wr(work, ".github/workflows/static-validation.yml", WORKFLOW)
    wr(work, ".githooks/pre-push", PRE_PUSH)
    os.chmod(os.path.join(work, ".githooks/pre-push"), 0o755)
    return commit(work, "feature/ci-static-validation",
        "feature: offline static validation (CI + pre-push BOM guard)\n\n"
        "The BOM regression in a4e2942 touched 9 files, was invisible in review, and\n"
        "is reproducible with three bytes of inspection. Same for the two other\n"
        "classes that silently break a trial: a file missing from incha.txt, and a\n"
        "require() whose target is listed later in the manifest (the loader resolves\n"
        "in manifest order and raises \"module not registered\").\n\n"
        "tools/static_checks.py is stdlib-only; tools/syntax_check.js is a luaparse\n"
        "smoke test (luaparse accepts a BOM, so it complements rather than replaces\n"
        "the encoding check). Both run in CI and the hook blocks a BOM at push time.\n\n"
        "Note the hook now accepts the encoding check even for the tarball case where\n"
        "no upstream rev is passed, and README:72 already documents core.hooksPath."
        + trailer("F-01, F-14, F-16"),
        ["tools/static_checks.py", "tools/syntax_check.js",
         ".github/workflows/static-validation.yml", ".githooks/pre-push"])


# --------------------------------------------------------------------------- patch 8
def patch_docs(work):
    sub(work, "README.md",
        "| Asylum Sanctorium (AS) | 📋 Planned |\n"
        "| Cloudrest (CR) | 📋 Planned |\n"
        "| Sanity's Edge (SE) | 📋 Planned |\n"
        "| Lucent Citadel (LC) | 📋 Planned |\n"
        "| Ossein Cage (OC) | 📋 Planned |",
        "| Asylum Sanctorium (AS) | 🔄 In progress |\n"
        "| Cloudrest (CR) | 🔄 In progress |\n"
        "| Sanity's Edge (SE) | 🔄 In progress |\n"
        "| Lucent Citadel (LC) | 🔄 In progress |\n"
        "| Ossein Cage (OC) | 🔄 In progress |")
    sub(work, "README.md",
        "2. The folder **must** be named `incha` (lowercase) — the manifest requires it.",
        "2. The folder **must** be named `incha` (lowercase). ESO derives `ADDON_NAME`\n"
        "   from the folder name — not from the manifest — and `bootstrap.lua:15-19`\n"
        "   builds the log prefix, slash command and saved-variable name from it.")
    sub(work, "README.md",
        "  Factory.lua          trial setup / zone detection\n"
        "  Dispatcher.lua       event routing\n",
        "  Factory.lua          trial setup / zone detection and boss order\n")

    sub(work, "ROADMAP.md",
        "- [x] `ui/Panel.lua` — `WINDOW_MANAGER` overlay implementing AlertSink vocabulary\n"
        "      (`header`, `info1–3`, `action`, `clear`, `hideAction`).",
        "- [x] `ui/Panel.lua` — `WINDOW_MANAGER` overlay implementing AlertSink vocabulary\n"
        "      (`header`, `info1–10`, `action`, `clear`, `hideAction`; 10 info lines —\n"
        "      INFO_LINE_COUNT in ui/Panel.lua:37 — in a 320x260 window.)")
    sub(work, "ROADMAP.md", "### CR — Cloudrest (zoneId = TBD) 📋 Planned",
        "### CR — Cloudrest (zoneId = 1051) 🔄 In progress")
    sub(work, "ROADMAP.md", "### LC — Lucent Citadel (zoneId = TBD) 📋 Planned",
        "### LC — Lucent Citadel (zoneId = 1478) 🔄 In progress")
    sub(work, "ROADMAP.md", "### OC — Ossein Cage (zoneId = TBD) 📋 Planned",
        "### OC — Ossein Cage (zoneId = 1548) 🔄 In progress")

    sub(work, "test/README.md",
        "| 1000 | Aetherian Archive (AS) |\n"
        "| 1051 | Cradle of Shadows (CR) |\n"
        "| 1427 | Sanity's Edge (SE) |\n"
        "| 1478 | Lucent Citadel (LC) |\n"
        "| 1548 | Oathsworn Pit (OC) |",
        "| 1000 | Asylum Sanctorium (AS) |\n"
        "| 1051 | Cloudrest (CR) |\n"
        "| 1427 | Sanity's Edge (SE) |\n"
        "| 1478 | Lucent Citadel (LC) |\n"
        "| 1548 | Ossein Cage (OC) |")
    return commit(work, "fix/docs-drift-corrections",
        "fix(docs): correct status table, removed-module reference, and zone IDs\n\n"
        "All read-only corrections, each cross-checked against the code:\n"
        "  * README listed AS/CR/SE/LC/OC as Planned although all nine trials are\n"
        "    registered in incha.lua:25-33 with 25 boss modules behind them.\n"
        "  * README's tree listed trial/<id>/Dispatcher.lua, which no longer exists;\n"
        "    routing lives in each boss module's combatRoutes/effectRoutes.\n"
        "  * README said the manifest requires the lowercase folder name; it is\n"
        "    ESO's own ADDON_NAME derivation, not the manifest.\n"
        "  * ROADMAP described the panel as info1–3; it renders 10 lines.\n"
        "  * ROADMAP still said zoneId = TBD for CR/LC/OC (1051/1478/1548, per\n"
        "    incha.lua and test/run_log.lua) and marked the sections Planned.\n"
        "  * test/README misnamed three zones: 1000 is Asylum Sanctorium, 1051 is\n"
        "    Cloudrest, 1548 is Ossein Cage (the code modules are OlmsEncounter,\n"
        "    ZmajaEncounter and OsseinCageCommon)."
        + trailer("F-16, F-17"),
        ["README.md", "ROADMAP.md", "test/README.md"])


# --------------------------------------------------------------------------- driver
BUILDERS = [
    ("01", patch_bom),
    ("02", patch_panel),
    ("03", build_boss_slot),
    ("04", patch_hm_aid),
    ("05", patch_live_enable),
    ("06", patch_version),
    ("07", patch_ci),
    ("08", patch_docs),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", help="comma list of ids to build (01..08)")
    args = ap.parse_args()

    work = os.path.abspath(args.work)
    out = os.path.abspath(args.out)
    if os.path.commonpath([work, out]) == work:
        raise SystemExit("refusing to run: --out is inside --work, which this script "
                         "checks out, cleans and commits")
    if not os.path.isdir(os.path.join(work, ".git")):
        raise SystemExit("--work is not a git clone: %s" % work)
    head = subprocess.run(["git", "-C", work, "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    print("work clone HEAD: %s (patch series is built on %s)" % (head[:7], BASE[:7]))
    want = set(args.only.split(",")) if args.only else None

    os.makedirs(args.out, exist_ok=True)
    built = []
    for pid, fn in BUILDERS:
        if want and pid not in want:
            continue
        git(work, "checkout", "-f", "-q", BASE)
        git(work, "clean", "-fdq", "--", ".")
        git(work, "reset", "--hard", "-q", BASE)
        sha = fn(work)
        branch = git(work, "rev-parse", "--abbrev-ref", "HEAD").strip()
        n = 2 if pid == "02" else 1
        patch = os.path.join(args.out, "%s-%s.patch" % (pid, branch.replace("/", "-")))
        with open(patch, "w") as fh:
            fh.write(git(work, "format-patch", "-%d" % n, "--stdout", "HEAD"))
        built.append((pid, branch, sha, patch))
        print("built %-3s %-38s %s -> %s" % (pid, branch, sha, os.path.basename(patch)))
    print("\n%d patch file(s) in %s" % (len(built), args.out))


def patch_boss_slot_body(work):
    """The Trial/TrialContext half of patch 3 (Falgravn is a separate helper)."""
    sub(work, "core/Trial.lua", TRIAL_REQUIRES,
        TRIAL_REQUIRES + '\n'
        '\n'
        '-- Unit tags occupied by trial bosses (nameplate slots, engine order).\n'
        'local BOSS_SLOTS   = { "boss1", "boss2", "boss3", "boss4" }')
    sub(work, "core/Trial.lua",
        '            self:onPowerUpdate(powerValue, powerMax)',
        '            self:onPowerUpdate(unitTag, powerValue, powerMax)')
    sub(work, "core/Trial.lua",
        'function Trial:onPowerUpdate(powerValue, powerMax)\n'
        '    if not self.enabled then\n'
        '        return\n'
        '    end\n',
        'function Trial:onPowerUpdate(unitTag, powerValue, powerMax)\n'
        '    if not self.enabled then\n'
        '        return\n'
        '    end\n'
        '\n'
        '    -- Only the tracked boss drives the overlay. Concurrent encounters put two\n'
        '    -- units into boss slots at once (Ryelaz + Zilyesset in LC, Lylanar +\n'
        "    -- Turlassil in DSR); without this guard the wrong unit's percentage feeds\n"
        '    -- health rules and every timer keyed on a % window.\n'
        '    local tracked = self.context.bossUnitTag\n'
        '    if tracked and unitTag ~= tracked then\n'
        '        return\n'
        '    end\n')
    sub(work, "core/Trial.lua",
        '    local _, x, y, z = GetUnitWorldPosition("player")\n'
        '    local bossClass = self.registry:findAtPosition(x, y, z)\n',
        '    local _, x, y, z = GetUnitWorldPosition("player")\n'
        '    local bossClass = self.registry:findAtPosition(x, y, z)\n'
        '    local bossSlot  = nil   -- which boss1..boss4 tag the match came from\n')
    sub(work, "core/Trial.lua",
        '    if not bossClass then\n'
        '        for _, slot in ipairs({"boss1", "boss2", "boss3", "boss4"}) do\n'
        '            if DoesUnitExist(slot) then\n'
        '                local candidate = self.registry:findByName(GetUnitName(slot))\n'
        '                if candidate then\n'
        '                    bossClass = candidate\n'
        '                    break\n'
        '                end\n'
        '            end\n'
        '        end\n'
        '    end\n',
        '    if not bossClass then\n'
        '        for _, slot in ipairs(BOSS_SLOTS) do\n'
        '            if DoesUnitExist(slot) then\n'
        '                local candidate = self.registry:findByName(GetUnitName(slot))\n'
        '                if candidate then\n'
        '                    bossClass = candidate\n'
        '                    bossSlot  = slot\n'
        '                    break\n'
        '                end\n'
        '            end\n'
        '        end\n'
        '    else\n'
        '        -- Position match: resolve which slot this boss actually occupies so the\n'
        '        -- health poll and the power-update guard use the same unit.\n'
        '        for _, slot in ipairs(BOSS_SLOTS) do\n'
        '            if DoesUnitExist(slot)\n'
        '               and self.registry:findByName(GetUnitName(slot)) == bossClass then\n'
        '                bossSlot = slot\n'
        '                break\n'
        '            end\n'
        '        end\n'
        '    end\n')
    sub(work, "core/Trial.lua",
        '        self.context:setBoss(instance)\n'
        '\n'
        '        local _, _, effectiveMax = GetUnitPower("boss1", POWERTYPE_HEALTH)',
        '        self.context:setBoss(instance, bossSlot)\n'
        '\n'
        '        -- Info/action lines from the previous boss must not survive the\n'
        '        -- transition: on a boss-to-boss change nothing else clears them, so the\n'
        '        -- panel keeps the dead boss\'s timers until the new boss overwrites each\n'
        '        -- line - or forever, for lines the new boss never writes.\n'
        '        self.alerts:clear()\n'
        '\n'
        '        local _, _, effectiveMax =\n'
        '            GetUnitPower(bossSlot or "boss1", POWERTYPE_HEALTH)')
    sub(work, "core/TrialContext.lua",
        '        stage         = 1,\n'
        '        inCombat      = false,',
        '        stage         = 1,\n'
        '        -- boss1..boss4 tag the active boss occupies (nil = unknown). Mechanics\n'
        '        -- that name or poll the boss must use this, not a literal "boss1".\n'
        '        bossUnitTag   = nil,\n'
        '        inCombat      = false,')
    sub(work, "core/TrialContext.lua",
        'function TrialContext:setBoss(boss)\n'
        '    if boss then\n',
        '--- @param boss    table|nil  active boss instance (nil = no boss)\n'
        '--- @param unitTag string|nil boss1..boss4 tag it was matched on (nil = unknown)\n'
        'function TrialContext:setBoss(boss, unitTag)\n'
        '    self.bossUnitTag = boss and unitTag or nil\n'
        '    if boss then\n')


if __name__ == "__main__":
    main()
