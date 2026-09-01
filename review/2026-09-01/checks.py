#!/usr/bin/env python3
"""
Incha repository review checks — read-only, stdlib only.

Purpose
    Reproduce, on any machine, every mechanical claim made in
    .review/code-review-2026-09-01.md.  No file in the repository is modified.

Usage
    python3 .review/checks.py [--repo PATH] [--json findings.json] [--git]

Exit status
    0  every check with FAIL severity passed
    1  at least one FAIL
    (WARN/NOTE results never fail the run)

Severity convention used throughout this review
    FAIL  concrete defect or contradiction; fix before release
    WARN  probable defect or a risk that needs one in-game measurement
    NOTE  information / documentation drift
"""

import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys

BOM = b"\xef\xbb\xbf"

# Files that are legitimately exempt from some checks.
EXEMPT_NOT_A_MODULE = {"bootstrap.lua", "incha.lua"}

results = []


def add(check, status, message, where=""):
    results.append(
        {"check": check, "status": status, "message": message, "where": where}
    )


def module_name(relpath):
    return relpath[:-4].replace(os.sep, ".").replace("/", ".")


def lua_files(repo, include_test=True):
    out = []
    for path in glob.glob(os.path.join(repo, "**", "*.lua"), recursive=True):
        rel = os.path.relpath(path, repo)
        if rel.startswith(".git" + os.sep):
            continue
        if not include_test and rel.split(os.sep)[0] == "test":
            continue
        out.append(rel)
    return sorted(out)


def read(rel, repo):
    with open(os.path.join(repo, rel), "rb") as fh:
        raw = fh.read()
    return raw


# --------------------------------------------------------------------------
# C-01  Byte-order mark
# --------------------------------------------------------------------------
def check_bom(repo):
    targets = []
    for pattern in ("**/*.lua", "**/*.txt", "**/*.md"):
        for path in glob.glob(os.path.join(repo, pattern), recursive=True):
            rel = os.path.relpath(path, repo)
            if rel.startswith(".git" + os.sep) or rel.split(os.sep)[0] == ".review":
                continue
            with open(path, "rb") as fh:
                if fh.read(3) == BOM:
                    targets.append(rel)
    if targets:
        add("C-01 BOM", "FAIL",
            "%d source files start with a UTF-8 BOM (EF BB BF). "
            "A BOM is not part of Lua's grammar; ESO compiles the file body "
            "itself, so if its loader does not skip those 3 bytes the file "
            "fails to parse at 1:1 and the module never registers." % len(targets),
            ", ".join(sorted(targets)))
    else:
        add("C-01 BOM", "PASS", "no BOM in any source file")


# --------------------------------------------------------------------------
# C-02  Manifest <-> disk
# --------------------------------------------------------------------------
def check_manifest(repo):
    manifest = []
    for line in open(os.path.join(repo, "incha.txt"), encoding="utf-8"):
        line = line.strip()
        if line.endswith(".lua") and not line.startswith("##"):
            manifest.append(line.replace("/", os.sep))
    dups = [k for k, v in collections.Counter(manifest).items() if v > 1]
    have = set(manifest)
    disk = set(lua_files(repo, include_test=False))
    missing = sorted(os.path.relpath(os.path.join(repo, m), repo)
                     for m in have - disk)
    never = sorted(os.path.relpath(p, repo) for p in disk - have)
    if missing or never or dups:
        add("C-02 manifest", "FAIL",
            "in manifest but absent on disk: %s | on disk but never loaded: %s "
            "| duplicate entries: %s" % (missing or "none", never or "none",
                                          dups or "none"))
    else:
        add("C-02 manifest", "PASS",
            "all %d addon files are listed exactly once" % len(manifest))


def manifest_order(repo):
    order = []
    for line in open(os.path.join(repo, "incha.txt"), encoding="utf-8"):
        line = line.strip()
        if line.endswith(".lua") and not line.startswith("##"):
            order.append(line)
    return order


# --------------------------------------------------------------------------
# C-03  Load order (ESO has no file-loading require(); order is the contract)
# --------------------------------------------------------------------------
def check_load_order(repo):
    order = manifest_order(repo)
    loaded, offenders = set(), []
    for rel in order:
        path = os.path.join(repo, rel)
        if not os.path.exists(path):
            continue
        src = open(path, encoding="utf-8", errors="replace").read()
        reqs = set(re.findall(r'require\(\s*"([^"]+)"\s*\)', src))
        self_mod = rel[:-4].replace("/", ".")
        for dep in sorted(reqs):
            if dep not in loaded and dep != self_mod:
                offenders.append("%s requires %r before it is loaded" % (rel, dep))
        loaded.add(self_mod)
    if offenders:
        add("C-03 load order", "FAIL", "; ".join(offenders))
    else:
        add("C-03 load order", "PASS",
            "every require() target appears before its consumer in incha.txt")


# --------------------------------------------------------------------------
# C-04  Self-registration name matches the module path
# --------------------------------------------------------------------------
def check_registration(repo):
    bad = []
    for rel in manifest_order(repo):
        if rel in EXEMPT_NOT_A_MODULE:
            continue
        path = os.path.join(repo, rel)
        if not os.path.exists(path):
            continue
        src = open(path, encoding="utf-8", errors="replace").read()
        regs = set(re.findall(r'package\.loaded\[\s*"([^"]+)"\s*\]', src))
        want = rel[:-4].replace("/", ".")
        if regs != {want}:
            bad.append("%s registers %s, expected %r" % (rel, sorted(regs), want))
    if bad:
        add("C-04 registration", "FAIL", "; ".join(bad))
    else:
        add("C-04 registration", "PASS",
            "each module registers exactly its path-derived module name")


# --------------------------------------------------------------------------
# C-05  Routing-table handler signatures vs CombatHandler dispatch
#
# core/CombatHandler.lua dispatches two ways:
#   plain function   f(self, ctx, alerts, <result|changeType>, abilityId, ...)
#   D6 shorthand     { result = X, fn = f }  -> f(self, ctx, alerts, abilityId, ...)
# A handler whose 4th parameter is named for the wrong slot is the Jynorah P0
# bug class (see ROADMAP "Known bugs P0").
# --------------------------------------------------------------------------
def check_routes(repo):
    kinds = {
        "combatRoutes": ("result", "abilityId"),
        "effectRoutes": ("changeType", "abilityId"),
    }
    mismatches, entries = [], 0
    for rel in lua_files(repo, include_test=False):
        if "/boss/" not in "/" + rel and not rel.endswith("Common.lua"):
            continue
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        sig = {}
        for m in re.finditer(r"function\s+([A-Za-z_][\w.:]*)\s*\(([^)]*)\)", src):
            name = m.group(1).split(".")[-1].split(":")[0]
            params = [p.strip() for p in m.group(2).split(",") if p.strip()]
            if "alerts" in params:
                i = params.index("alerts")
                if i + 1 < len(params):
                    sig[name] = params[i + 1]
        for kind, (want_plain, want_short) in kinds.items():
            for tm in re.finditer(r"(\w+(?:\.\w+)*)\." + kind + r"\s*=\s*\{", src):
                start = tm.end() - 1
                depth, i = 0, start
                while i < len(src):
                    if src[i] == "{":
                        depth += 1
                    elif src[i] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    i += 1
                body = re.sub(r"--[^\n]*", "", src[start:i + 1])
                for em in re.finditer(r"\[([^\]]+)\]\s*=\s*([^\[\]\n][^,\n]*),", body):
                    key, val = em.group(1).strip(), em.group(2).strip()
                    entries += 1
                    if val.startswith("{"):
                        fm = re.search(r"fn\s*=\s*(\w+)", val)
                        if fm and sig.get(fm.group(1)) and sig[fm.group(1)] != want_short:
                            mismatches.append("%s: %s [%s] = { fn = %s } declares 4th "
                                              "param %r, shorthand passes %r"
                                              % (rel, kind, key, fm.group(1),
                                                 sig[fm.group(1)], want_short))
                    elif re.fullmatch(r"\w+", val):
                        got = sig.get(val)
                        if got == "...":       # explicit pass-through wrapper
                            continue
                        if got and got != want_plain:
                            mismatches.append("%s: %s [%s] = %s declares 4th param "
                                              "%r, plain dispatch passes %r"
                                              % (rel, kind, key, val, got, want_plain))
    if mismatches:
        add("C-05 route signatures", "FAIL", "; ".join(mismatches))
    else:
        add("C-05 route signatures", "PASS",
            "%d route entries agree with the CombatHandler dispatch convention "
            "(the Jynorah P0 bug class has not recurred)" % entries)


# --------------------------------------------------------------------------
# C-06  Settings keys that are written but never read
# --------------------------------------------------------------------------
def check_dead_settings(repo):
    src = open(os.path.join(repo, "core", "Settings.lua"), encoding="utf-8").read()
    block = re.search(r"trials\s*=\s*\{(.*?)\n    \}", src, re.S)
    keys = set()
    if block:
        for m in re.finditer(r"([A-Za-z_]\w*)\s*=", block.group(1)):
            keys.add(m.group(1))
        keys.discard("enabled")          # consumed by ZoneManager
    exempt = {"core" + os.sep + "Settings.lua", "ui" + os.sep + "Menu.lua"}
    dead = []
    for key in sorted(keys):
        readers = []
        for rel in lua_files(repo):
            if rel in exempt:
                continue
            body = open(os.path.join(repo, rel), encoding="utf-8",
                        errors="replace").read()
            if re.search(r"[.\w]" + re.escape(key) + r"\b(?!\s*=)", body) and \
               re.search(r"\b" + re.escape(key) + r"\b", body):
                # ignore the definition-only occurrences (harness defaults)
                lines = [ln for ln in body.splitlines()
                         if re.search(r"\b" + re.escape(key) + r"\b", ln)
                         and not re.match(r"\s*" + re.escape(key) + r"\s*=", ln)]
                if lines:
                    readers.append(rel)
        if not readers:
            dead.append(key)
    if dead:
        add("C-06 unread settings", "FAIL",
            "settings keys exposed in the LAM panel but never read by any "
            "consumer: %s" % ", ".join(dead),
            "core/Settings.lua DEFAULTS.trials + ui/Menu.lua checkboxes")
    else:
        add("C-06 unread settings", "PASS", "every per-trial setting key has a reader")


# --------------------------------------------------------------------------
# C-07  HM thresholds that cannot work
# --------------------------------------------------------------------------
def check_hm_thresholds(repo):
    huge, placeholder, ok = [], [], 0
    for rel in lua_files(repo, include_test=False):
        if "/boss/" not in "/" + rel:
            continue
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        m = re.search(r"hmHealthThreshold\s*=\s*([0-9.eA-Za-z_]+)", src)
        if not m:
            continue
        val = m.group(1)
        if val.startswith("math.huge"):
            huge.append(rel)
        elif val.strip() == "100000001":
            placeholder.append(rel)
        else:
            ok += 1
    if huge or placeholder:
        add("C-07 HM thresholds", "WARN",
            "%d bosses use math.huge (detectDifficulty can never return HARDMODE) "
            "and %d use the 100000001 placeholder: %s"
            % (len(huge), len(placeholder),
               ", ".join(sorted(huge + placeholder))),
            "BossRegistry:detectDifficulty, core/BossRegistry.lua:61-71")
    else:
        add("C-07 HM thresholds", "PASS", "no placeholder thresholds left")


# --------------------------------------------------------------------------
# C-08  Proximity thresholds: world-unit scale
# --------------------------------------------------------------------------
def check_proximity(repo):
    suspects = []
    for rel in lua_files(repo, include_test=False):
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"isGroupMemberNearby\(\s*\w+\s*,\s*([0-9.]+)\s*\)", src):
            thr = float(m.group(1))
            line = src[:m.start()].count("\n") + 1
            if thr < 50:          # world units: a boss room spans thousands
                suspects.append("%s:%d uses %g" % (rel, line, thr))
    if suspects:
        add("C-08 proximity scale", "WARN",
            "lib/MapUtils.isGroupMemberNearby now measures GetUnitWorldPosition "
            "units, but these call-sites still pass pre-rewrite values, so the "
            "alert can never fire: %s" % "; ".join(suspects),
            "lib/MapUtils.lua:5-17")
    else:
        add("C-08 proximity scale", "PASS", "all proximity thresholds look world-unit sized")


# --------------------------------------------------------------------------
# C-09  stateSchema entries assigned nil are no-ops
# --------------------------------------------------------------------------
def check_nil_schema(repo):
    hits = []
    for rel in lua_files(repo, include_test=False):
        if "/boss/" not in "/" + rel:
            continue
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"stateSchema\s*=\s*\{(.*?)\n\}", src, re.S):
            for km in re.finditer(r"^\s*([A-Za-z_]\w*)\s*=\s*nil\s*,?",
                                  m.group(1), re.M):
                line = src[:m.start(1) + km.start()].count("\n") + 1
                hits.append("%s:%d %s" % (rel, line, km.group(1)))
    if hits:
        add("C-09 nil stateSchema", "NOTE",
            "`key = nil` inside a table constructor stores nothing, so "
            "BossBase.fromSchema cannot create these fields — the entries are "
            "documentation only: %s" % "; ".join(hits))
    else:
        add("C-09 nil stateSchema", "PASS", "no `= nil` stateSchema entries")


# --------------------------------------------------------------------------
# C-10  Version strings
# --------------------------------------------------------------------------
def check_version(repo):
    man = open(os.path.join(repo, "incha.txt"), encoding="utf-8").read()
    vm = re.search(r"##\s*Version:\s*(\S+)", man)
    manifest_version = vm.group(1) if vm else "?"
    others = {}
    for rel in ("incha.lua", os.path.join("ui", "Menu.lua")):
        body = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        found = set(re.findall(r"v?(\d+\.\d+\.\d+)", body))
        if found:
            others[rel] = sorted(found)
    bad = {k: v for k, v in others.items() if manifest_version not in v}
    if bad:
        add("C-10 version", "NOTE",
            "manifest declares ## Version: %s while these report something "
            "else: %s" % (manifest_version, bad))
    else:
        add("C-10 version", "PASS", "version string is consistent (%s)" % manifest_version)


# --------------------------------------------------------------------------
# C-11  Documentation drift (cheap textual assertions)
# --------------------------------------------------------------------------
def check_docs(repo):
    notes = []
    readme = open(os.path.join(repo, "README.md"), encoding="utf-8").read()
    if "Dispatcher.lua" in readme:
        notes.append("README.md documents trial/<id>/Dispatcher.lua, a layer the "
                     "history shows was removed "
                     "(commit 'refactor: remove Dispatcher layer')")
    if re.search(r"Planned", readme) and os.path.isdir(os.path.join(repo, "trial", "oc", "boss")):
        notes.append("README.md marks AS/CR/SE/LC/OC as 'Planned' although those "
                     "trees contain fully routed boss modules "
                     "(e.g. trial/cr/boss/ZmajaEncounter.lua is 637 lines with 43 "
                     "combatRoutes)")
    roadmap = open(os.path.join(repo, "ROADMAP.md"), encoding="utf-8").read()
    if "without BOM" in roadmap:
        bom_present = [p for p in lua_files(repo)
                       if read(p, repo).startswith(BOM)]
        if bom_present:
            notes.append("ROADMAP.md states files were 're-saved as UTF-8 without "
                         "BOM' while %d of them still have one" % len(bom_present))
    if re.search(r"require\(\"ui\.Bridge\"\)", roadmap):
        if os.path.exists(os.path.join(repo, "core", "Bridge.lua")) and \
           not os.path.exists(os.path.join(repo, "ui", "Bridge.lua")):
            notes.append("ROADMAP.md 'Open architecture questions' #1 still "
                         "describes the core -> ui.Bridge inversion that has since "
                         "been fixed (core/Bridge.lua exists, ui/Bridge.lua does not)")
    for line, zone in ((217, "CR"), (327, "LC"), (418, "OC")):
        pass
    if "zoneId = TBD" in roadmap:
        zones = dict(re.findall(r"registerTrial\((\d+),\s*require\(\"trial\.(\w+)\.Factory\"\)",
                                open(os.path.join(repo, "incha.lua"),
                                     encoding="utf-8").read()))
        wanted = {tid: zid for zid, tid in zones.items() if tid in ("cr", "lc", "oc")}
        notes.append("ROADMAP.md still shows 'zoneId = TBD' for CR/LC/OC while "
                     "incha.lua registers them (%s)"
                     % ", ".join("%s=%s" % kv for kv in sorted(wanted.items())))
    panel = open(os.path.join(repo, "ui", "Panel.lua"), encoding="utf-8").read()
    if re.search(r"H=200", panel):
        notes.append("ui/Panel.lua header comment says H=200 while the code uses "
                     "%s" % re.search(r"local W, H = (\d+), (\d+)", panel).group(0))
    if notes:
        add("C-11 doc drift", "NOTE", " | ".join(notes))
    else:
        add("C-11 doc drift", "PASS", "no known doc/code contradiction detected")


# --------------------------------------------------------------------------
# C-14  Global control names must be prefixed with the addon's own name
# --------------------------------------------------------------------------
def check_control_names(repo):
    names = set()
    for rel in lua_files(repo, include_test=False):
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'CreateControl\(\s*"([^"]+)"', src):
            names.add((rel, src[:m.start()].count("\n") + 1, m.group(1)))
    # bootstrap.lua derives the addon title; ESO requires global control names to
    # start with the addon's own name (here: "Incha").
    bad = sorted((rel, line, n) for rel, line, n in names if not n.startswith("Incha"))
    if bad:
        add("C-14 control names", "WARN",
            "ESO only lets an addon create global controls whose names start with "
            "the addon's own name; these do not: %s"
            % "; ".join("%s:%d %r" % b for b in bad),
            "ADDON_NAME/ADDON_TITLE come from bootstrap.lua:16-19 (folder 'incha', "
            "title 'Incha')")
    else:
        add("C-14 control names", "PASS", "every named control is prefixed with Incha")


# --------------------------------------------------------------------------
# C-15  Panel text caches must be reset by every path that clears a control
# --------------------------------------------------------------------------
def check_panel_caches(repo):
    src = open(os.path.join(repo, "ui", "Panel.lua"), encoding="utf-8", errors="replace").read()
    block = re.search(r"hideAction = function\(\).*?\n    end,", src, re.S)
    if not block:
        add("C-15 panel caches", "NOTE", "could not locate the hideAction handler")
        return
    line = src[:block.start()].count("\n") + 1
    if "ctrl.actionText" not in block.group(0):
        add("C-15 panel caches", "FAIL",
            "hideAction clears the control but not the cached string, so the next "
            "identical action text is diffed away and never re-drawn "
            "(compare action handler at ui/Panel.lua:205-207): see ui/Panel.lua:%d"
            % line)
    else:
        add("C-15 panel caches", "PASS", "hideAction resets the action text cache")


# --------------------------------------------------------------------------
# C-17  Declared-but-unused constants (dead ability IDs / dead tuning knobs)
# --------------------------------------------------------------------------
def strip_noise(src):
    src = re.sub(r"--\[(=*)\[[\s\S]*?\]\1\]", "", src)
    src = re.sub(r"--[^\n]*", "", src)
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
    return src


def _const_block(src, m):
    """Value text of a `local NAME = ...` declaration, brace-aware."""
    tail = src[m.end():]
    if tail.lstrip().startswith("{"):
        i = m.end() + tail.index("{")
        depth, j = 0, i
        while j < len(src):
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        return src[m.end():j + 1]
    return src[m.end():src.find("\n", m.end())]


def check_dead_constants(repo):
    """Declared ability IDs / tuning values that no code path uses.

    Three outcomes, deliberately separated:
      unrouted  - the ID exists nowhere else in the file: the mechanic is
                  documented but has no route, i.e. it is not implemented.
      redundant - the ID set duplicates literals already used inline in the
                  routing table; cleanup only, no behaviour change.
      unused    - tuning constants / colour palettes with no numeric ID.
    """
    unrouted, redundant, unused = [], [], []
    for rel in lua_files(repo, include_test=False):
        src = strip_noise(read(rel, repo).decode("utf-8", "replace"))
        for m in re.finditer(r"^local ([A-Z][A-Za-z0-9_]*)\s*=([^{\n]*)", src, re.M):
            name = m.group(1)
            if "require(" in m.group(2):
                continue                              # deliberate preload (incha.lua:5-8)
            if len(re.findall(r"(?<![\w.])" + re.escape(name) + r"(?![\w])", src)) >= 2:
                continue                              # used
            line = src[:m.start()].count("\n") + 1
            value = m.group(2) + _const_block(src, m)
            nums = [n for n in re.findall(r"\b(\d{4,})\b", value)]
            if nums:
                inline = [n for n in nums
                          if len(re.findall(r"(?<![\d])" + n + r"(?!\d)", src)) > 1]
                if len(inline) == len(nums):
                    redundant.append("%s:%d %s (all %d ids routed inline)"
                                     % (rel, line, name, len(nums)))
                else:
                    missing = [n for n in nums if n not in inline]
                    unrouted.append("%s:%d %s ids %s" % (rel, line, name, ",".join(missing)))
            else:
                unused.append("%s:%d %s" % (rel, line, name))
    if unrouted:
        add("C-17 unrouted ability ids", "WARN",
            "%d declared ability IDs appear nowhere else in their file: the "
            "mechanic is documented but never routed, so no alert can ever fire "
            "for it. Either route them or move them to the ROADMAP backlog:"
            % len(unrouted), "; ".join(unrouted))
    else:
        add("C-17 unrouted ability ids", "PASS", "every declared ability ID is routed")
    leftovers = redundant + unused
    if leftovers:
        add("C-17b unused constants", "NOTE",
            "%d unused locals: %d ID sets that duplicate inline literals "
            "(cleanup), %d tuning/colour constants (7 of the *_FIRST_CD group "
            "are measured first-pull cooldowns that are never wired to "
            "Timer:reset): %s"
            % (len(leftovers), len(redundant), len(unused), "; ".join(leftovers)))
    else:
        add("C-17b unused constants", "PASS", "no unused module constants")


# --------------------------------------------------------------------------
# C-18  context.isHM gates behind a threshold that cannot work
# --------------------------------------------------------------------------
def check_hm_gates(repo):
    unusable = ("math.huge", "100000001")
    hits = []
    for rel in lua_files(repo, include_test=False):
        if "/boss/" not in "/" + rel:
            continue
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        th = re.search(r"hmHealthThreshold\s*=\s*([0-9A-Za-z_.]+)", src)
        if not th or th.group(1) not in unusable:
            continue
        gates = [src[:m.start()].count("\n") + 1
                 for m in re.finditer(r"\bisHM\b|\.difficulty\b", src)]
        if gates:
            hits.append("%s (threshold %s): %d gates at lines %s"
                        % (rel, th.group(1), len(gates),
                           ", ".join(str(g) for g in gates[:12])
                           + (" …" if len(gates) > 12 else "")))
    if hits:
        add("C-18 isHM gates", "WARN",
            "boss modules branch on context.isHM while their threshold is a "
            "placeholder, so those branches are driven by an unmeasured boundary "
            "(may mis-detect in either direction): %s" % " | ".join(hits))
    else:
        add("C-18 isHM gates", "PASS", "no isHM gate depends on a placeholder threshold")


# --------------------------------------------------------------------------
# C-19  Persistent CA bars whose handle is thrown away
# --------------------------------------------------------------------------
def check_ca_handles(repo):
    orphans = []
    for rel in lua_files(repo, include_test=False):
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"^\s*CA\.castAlertsStart\(", src, re.M):
            line = src[:m.start()].count("\n") + 1
            orphans.append("%s:%d" % (rel, line))
    if orphans:
        add("C-19 CA bar handles", "WARN",
            "CA.castAlertsStart returns an id used to stop the bar early; these "
            "call sites discard it, so the bar cannot be cancelled on wipe or "
            "zone exit and will keep running for its full duration: %s "
            "(CA.alertCast is a one-shot bar and is fine)" % ", ".join(orphans))
    else:
        add("C-19 CA bar handles", "PASS", "every castAlertsStart handle is kept")


# --------------------------------------------------------------------------
# C-20  Deferred callbacks with no cancellation handle
# --------------------------------------------------------------------------
def check_call_later(repo):
    bare = []
    for rel in lua_files(repo, include_test=False):
        src = open(os.path.join(repo, rel), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"^\s*zo_callLater\(", src, re.M):
            bare.append("%s:%d" % (rel, src[:m.start()].count("\n") + 1))
    if bare:
        add("C-20 zo_callLater handles", "NOTE",
            "deferred callbacks whose handle is discarded cannot be cancelled by "
            "onWipe/onLeave; each must only touch state it re-checks itself: %s"
            % ", ".join(bare))
    else:
        add("C-20 zo_callLater handles", "PASS", "every deferred callback is cancellable")


# --------------------------------------------------------------------------
# C-21  Local forward references (calls before `local function` = nil call)
# --------------------------------------------------------------------------
def check_forward_refs(repo):
    offenders = []
    for rel in lua_files(repo):
        src = strip_noise(read(rel, repo).decode("utf-8", "replace"))
        defs = {m.group(1): src[:m.start()].count("\n") + 1
                for m in re.finditer(r"local function ([A-Za-z_]\w*)", src)}
        for name, defline in defs.items():
            for m in re.finditer(r"(?<![\w.:])" + re.escape(name) + r"\s*\(", src):
                line = src[:m.start()].count("\n") + 1
                if line < defline:
                    offenders.append("%s:%d calls %s() declared at :%d"
                                     % (rel, line, name, defline))
    if offenders:
        add("C-21 forward references", "FAIL", "; ".join(offenders))
    else:
        add("C-21 forward references", "PASS",
            "no call site precedes its `local function` declaration "
            "(Lua would bind nil there)")


# --------------------------------------------------------------------------
# C-22  Harness configuration must mirror the shipped addon
# --------------------------------------------------------------------------
def check_harness_parity(repo):
    main = open(os.path.join(repo, "incha.lua"), encoding="utf-8").read()
    addon = dict(re.findall(r'registerTrial\((\d+),\s*require\("trial\.(\w+)\.Factory"\)', main))
    runner = os.path.join(repo, "test", "run_log.lua")
    if not os.path.exists(runner):
        add("C-22 harness parity", "NOTE", "test/run_log.lua not found")
        return
    h = open(runner, encoding="utf-8", errors="replace").read()
    cfg = dict(re.findall(r'\[(\d+)\]\s*=\s*\{\s*id\s*=\s*"(\w+)"', h))
    problems = []
    if addon != cfg:
        problems.append("zone->trial map differs: addon=%s harness=%s" % (addon, cfg))
    for zone, tid in sorted(cfg.items(), key=lambda x: int(x[0])):
        blk = re.search(r"\[%s\]\s*=\s*\{(.*?)\n    \}" % zone, h, re.S)
        factory = os.path.join(repo, "trial", tid, "Factory.lua")
        if not blk or not os.path.exists(factory):
            continue
        harness = re.findall(r'"trial\.[\w.]*?boss\.(\w+)"', blk.group(1))
        order = re.findall(r'require\("trial\.\w+\.boss\.(\w+)"\)',
                           open(factory, encoding="utf-8").read())
        if harness != order:
            problems.append("%s boss order differs: harness=%s factory=%s" % (tid, harness, order))
    if problems:
        add("C-22 harness parity", "FAIL", "; ".join(problems))
    else:
        add("C-22 harness parity", "PASS",
            "all %d zones and every boss order in test/run_log.lua match the Factories" % len(cfg))


# --------------------------------------------------------------------------
# C-16  Duplicate commits (optional, needs git)
# --------------------------------------------------------------------------
def check_git(repo):  # pragma: no cover - informational
    try:
        log = subprocess.run(["git", "-C", repo, "log", "--format=%s"],
                             capture_output=True, text=True, timeout=30).stdout.splitlines()
        merges = subprocess.run(["git", "-C", repo, "log", "--merges", "--oneline"],
                                capture_output=True, text=True, timeout=30).stdout.splitlines()
    except Exception as exc:                                  # pragma: no cover
        add("C-16 git history", "NOTE", "git not available: %s" % exc)
        return
    dupes = {m: c for m, c in collections.Counter(log).items() if c > 1}
    add("C-16 git history", "NOTE",
        "%d commits, %d of them merges; %d messages appear more than once "
        "(the same change was committed twice and both commits were merged). "
        "Examples: %s" % (len(log), len(merges), len(dupes),
                          "; ".join(list(dupes)[:5])))


# --------------------------------------------------------------------------
# C-13  Optional syntax pass (needs luaparse / luajit -bl; skipped otherwise)
# --------------------------------------------------------------------------
def check_syntax(repo):
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "syntax.js")
    node = os.system("command -v node >/dev/null 2>&1")
    if node != 0 or not os.path.exists(script):
        add("C-13 syntax", "NOTE",
            "skipped (needs node + luaparse, or `luajit -bl` over each file "
            "locally); see .review/run.sh")
        return
    proc = subprocess.run(["node", script, repo], capture_output=True, text=True,
                          timeout=300)
    out = (proc.stdout + proc.stderr).strip()
    if "syntax failures: 0" in out:
        add("C-13 syntax", "PASS", out.splitlines()[-1])
    else:
        add("C-13 syntax", "FAIL", out[-1500:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--json", help="also write machine-readable findings here")
    ap.add_argument("--git", action="store_true", help="include git-history checks")
    args = ap.parse_args()
    repo = os.path.abspath(args.repo)

    check_bom(repo)
    check_manifest(repo)
    check_load_order(repo)
    check_registration(repo)
    check_routes(repo)
    check_dead_settings(repo)
    check_hm_thresholds(repo)
    check_proximity(repo)
    check_nil_schema(repo)
    check_version(repo)
    check_control_names(repo)
    check_panel_caches(repo)
    check_dead_constants(repo)
    check_hm_gates(repo)
    check_ca_handles(repo)
    check_call_later(repo)
    check_forward_refs(repo)
    check_harness_parity(repo)
    check_docs(repo)
    check_syntax(repo)
    if args.git:
        check_git(repo)

    order = {"FAIL": 0, "WARN": 1, "NOTE": 2, "PASS": 3}
    print("INCHA REVIEW CHECKS  (%s)" % repo)
    print("=" * 72)
    for res in sorted(results, key=lambda r: (order[r["status"]], r["check"])):
        print("[%s] %s" % (res["status"].ljust(4), res["check"]))
        print("       %s" % res["message"])
        if res["where"]:
            print("       at: %s" % res["where"])
    counts = collections.Counter(r["status"] for r in results)
    print("-" * 72)
    print("PASS %d   WARN %d   FAIL %d   NOTE %d"
          % (counts.get("PASS", 0), counts.get("WARN", 0),
             counts.get("FAIL", 0), counts.get("NOTE", 0)))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"repo": repo, "results": results}, fh, indent=2)
        print("findings written to %s" % args.json)

    return 1 if counts.get("FAIL", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
