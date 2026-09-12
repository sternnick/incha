--- Incha's own SavedVariables.
---
--- IMPORTANT: Settings.init() must be called inside EVENT_ADD_ON_LOADED
--- before any other module calls Settings.get() or Settings.trial().
--- ESO does not populate SavedVars until that event fires.
---
--- The manifest (incha.txt) must declare:  ## SavedVariables: &lt;ADDON_SV&gt; (set in bootstrap.lua)

local Settings = {}

-- Schema version. Increment this when the DEFAULTS shape changes in a
-- way that requires a clean reset (ZO_SavedVars will wipe and re-apply).
local SCHEMA_VERSION = 1

-- Full default schema  -  defines every key the rest of the addon may read.
-- ZO_SavedVars deep-merges this, so adding new keys here is safe without
-- a schema version bump as long as you don't need to remove old ones.
local DEFAULTS = {
    debug = false,

    overlay = {
        locked   = false,
        scale    = 1.0,
        -- -1 = "not yet positioned by user"; Panel uses a default anchor on
        -- first show and saves real pixel coords here after the first
        -- OnMoveStop, at which point both values will be >= 0.
        offsetX  = -1,   -- tracker panel
        offsetY  = -1,
        alertX   = -1,   -- alert panel
        alertY   = -1,
    },

    trials = {
        ka = {
            enabled          = true,
            showPercent      = true,   -- hp% milestone alerts (Falgravn etc.)
            portalIconVrol   = true,   -- floor icon on Vrol portal spawn
            posIconsFalgravn = true,   -- connection-node / blood-ball / torturer floor markers
            bosses = {
                yandir   = true,
                vrol     = true,
                falgravn = true,
            },
        },
        ss = {
            enabled = true,
            bosses  = {
                lokke  = true,
                yolna  = true,
                nahvii = true,
            },
        },
        rg = {
            enabled = true,
            bosses  = {
                oaxiltso = true,
                bahsei   = true,
                xalvakka = true,
            },
        },
        dsr = {
            enabled = true,
            bosses  = {
                lylanar       = true,
                reef_guardian = true,
                taleria       = true,
            },
        },
        as = {
            enabled     = true,
            showPercent = true,   -- Olms jump-threshold pre-warnings
            bosses      = {
                olms = true,
            },
        },
        cr = {
            enabled       = true,
            posIconsZmaja = true,   -- OSI Frost/Gale mechanic icons
            bosses        = {
                zmaja = true,
            },
        },
        se = {
            enabled     = true,
            showPercent = true,   -- Yaseyla phase / add-wave milestones
            bosses      = {
                yaseyla = true,
                chimera = true,
                ansuul  = true,
            },
        },
        lc = {
            enabled = true,
            bosses  = {
                ryelaz   = true,
                dariel   = true,
                orphic   = true,
                xynizata = true,
                xoryn    = true,
            },
        },
        oc = {
            enabled = true,
            bosses  = {
                jynorah = true,
                kazpian = true,
                shaper  = true,
            },
        },
    },

    -- Set true once we've attempted a one-time import from BSCHTKA.SV_ACC.
    -- Stays false across sessions until BSCHTKA is actually present so we
    -- retry automatically if load-order prevented it the first time.
    migratedFromBSCHTKA = false,
}

-- Private live reference; populated by init().
local _sv = nil

--- Must be called once during EVENT_ADD_ON_LOADED.
function Settings.init()
    _sv = ZO_SavedVars:NewAccountWide(ADDON_SV, SCHEMA_VERSION, nil, DEFAULTS)

    -- One-time import from the legacy BSCHTKA addon so existing users keep
    -- their preferences when they first run Incha without BSCHTKA.
    -- We only attempt this when BSCHTKA is loaded AND has its SV table,
    -- and retry on the next session if it wasn't available this time.
    if not _sv.migratedFromBSCHTKA and BSCHTKA and BSCHTKA.SV_ACC then
        local acc = BSCHTKA.SV_ACC

        if acc.SHOW_UI_PERCENT ~= nil then _sv.trials.ka.showPercent    = acc.SHOW_UI_PERCENT end
        if acc.PORTAL_ICON_VROL ~= nil then _sv.trials.ka.portalIconVrol = acc.PORTAL_ICON_VROL end

        _sv.migratedFromBSCHTKA = true
    end

    -- Wire the debug logger to our saved flag so it survives reloads.
    local Log = require("lib.Log")
    Log.setEnabled(_sv.debug)
end

--- Returns the live SavedVars table.
--- Callers may read any key; writes are automatically persisted by ESO.
function Settings.get()
    return _sv
end

--- Convenience accessor for a trial's sub-table, e.g.:
---   local ka = Settings.trial("ka")
---   if ka.showPercent then ... end
--- Asserts that Settings.init() has been called and that trialId is a known
--- key, so misuse surfaces immediately as a visible chat error rather than a
--- silent nil-index panic somewhere deep in boss code.
function Settings.trial(trialId)
    assert(_sv,                    "[Incha] Settings.trial() called before Settings.init()")
    assert(_sv.trials[trialId],    "[Incha] Settings.trial(): unknown trial id '" .. tostring(trialId) .. "'")
    return _sv.trials[trialId]
end

package.loaded["core.Settings"] = Settings
return Settings
