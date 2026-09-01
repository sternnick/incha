local Difficulty = require("core.Difficulty")

local TrialContext = {}
TrialContext.__index = TrialContext

function TrialContext.new(trialId)
    return setmetatable({
        trialId       = trialId,
        bossId        = nil,
        bossKey       = nil,
        difficulty    = Difficulty.NONE,
        isHM          = false,   -- pre-computed; kept in sync with difficulty
        stage         = 1,
        -- boss1..boss4 tag the active boss occupies (nil = unknown). Mechanics
        -- that name or poll the boss must use this, not a literal "boss1".
        bossUnitTag   = nil,
        inCombat      = false,
        healthPercent = 0,
    }, TrialContext)
end

--- @param boss    table|nil  active boss instance (nil = no boss)
--- @param unitTag string|nil boss1..boss4 tag it was matched on (nil = unknown)
function TrialContext:setBoss(boss, unitTag)
    self.bossUnitTag = boss and unitTag or nil
    if boss then
        self.bossId = boss.id
        self.bossKey = boss.key
        self.stage = boss.stage or 1
    else
        self.bossId = nil
        self.bossKey = nil
        self.stage = 1
    end
end

function TrialContext:setDifficulty(difficulty)
    self.difficulty = difficulty or Difficulty.NONE
    self.isHM       = (self.difficulty == Difficulty.HARDMODE)
end

package.loaded["core.TrialContext"] = TrialContext
return TrialContext
