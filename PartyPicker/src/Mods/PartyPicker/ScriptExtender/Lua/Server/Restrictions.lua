-- Party Picker (server): the two places where the game's own scripts only
-- handle four party members, and what this mod does about each.
--
-- 1. Long rest. PROC_Camp_PlacePlayersInBed (Shared goal GLO_Camp.txt) puts
--    exactly four players into the four camp beds; anyone else is left out,
--    and other party-size mods report rests going wrong as a result.
--    The camp flow has a supported way to refuse End the Day with a story
--    reason: QRY_Camp_CheckPlayersReadyForNightModeStoryReasons adds a row to
--    DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason, the request fails,
--    and PROC_Camp_TryEnterNightModeFailed(player, reason) is called (the game
--    uses this for "REALLY_BlockFastTravel"). We add our own reason when the
--    party is larger than four, ask which four to keep, and put the others
--    back after LongRestFinished.
--
-- 2. The Ebonlake raft to Grymforge (Act 1 goal Act1_UND_EbonLake.txt). The
--    raft takes the whole party aboard (PROC_UND_EbonLake_Raft_ComposeCrew
--    adds every DB_Players member in the party group) but lands them by index
--    from DB_UND_EbonLake_Raft_Locations_PlayerPositions, which has indexes
--    1-4 per dock; members 5+ are never teleported and stay behind. No choice
--    is needed here: we add indexes 5-16, reusing the existing positions, so
--    everyone lands. The single-player raft path starts the dialog without a
--    ready check, so holding the crossing is not possible anyway.
--
-- Both use listeners and story databases only; no story file is replaced.

local Party = Ext.Require("Server/Party.lua")

local Restrictions = {}

local REST_REASON = "PartyPicker_PartyLargerThanFour"
local RAFT_POSITIONS_DB = "DB_UND_EbonLake_Raft_Locations_PlayerPositions"
local RAFT_MAX_INDEX = 16
local RESTORE_DELAY_MS = 2000
local RESTORE_RETRY_MS = 3000
local RESTORE_TRIES = 5

-- Pending trim, saved with the game so a save/load between trimming and
-- restoring does not lose the party (registered in Shared/Common.lua):
--   { party = {uuid...}  members before the trim,
--     trimmed = bool     true once someone was actually sent to camp,
--     reason = "rest" }
local function vars() return Ext.Vars.GetModVariables(ModuleUUID) end

function Restrictions.GetPending()
    local ok, p = pcall(function() return vars().Pending end)
    if ok and type(p) == "table" and type(p.party) == "table" then return p end
    return nil
end

local function setPending(p)
    -- Whole-table assignment: writes to sub-fields are not saved (API.md).
    pcall(function() vars().Pending = p end)
end

function Restrictions.ClearPending() setPending(nil) end

-- "Keep everyone this time" skips the next hold of that kind.
local bypassOnce = {}

local BYPASS_EXPIRES_MS = 120000

function Restrictions.BypassOnce(reason)
    bypassOnce[reason] = true
    -- Only for the End the Day press that follows, not one much later.
    Ext.Timer.WaitForRealtime(BYPASS_EXPIRES_MS, function() bypassOnce[reason] = nil end)
    local p = Restrictions.GetPending()
    -- Only drop a record nobody was trimmed for; an earlier trim still
    -- waiting to be restored must survive.
    if p and not p.trimmed then setPending(nil) end
end

function Restrictions.Notice(text, kind)
    PP.Log(text)
    pcall(function() PP.Net.Notice:Broadcast({ text = text, kind = kind or "info" }) end)
end

local function overFour()
    return Party.ActiveCount() > PP.RESTRICTED_SIZE
end

-- Ask the host which four to keep.
local function ask(reason)
    local p = Restrictions.GetPending()
    if p and p.trimmed then
        -- Already trimmed once and not yet restored: keep the original list.
        p.reason = reason
    else
        p = { reason = reason, party = Party.ActiveUuids(), trimmed = false }
    end
    setPending(p)
    PP.Net.PickFour:Broadcast({ reason = reason, size = PP.RESTRICTED_SIZE })
end

-- Called after the picker's choice was carried out (fully or partly).
function Restrictions.OnTrimmed(reason, result)
    local p = Restrictions.GetPending()
    if not p then return end
    if result and result.changed then
        p.trimmed = true
        setPending(p)
    end
    if result and result.ok and reason == "rest" then
        Restrictions.Notice("Party trimmed to four for the night. Press End the Day again.")
    end
end

-- Bring back the members who were sent to camp by a trim. Never sends
-- anyone to camp: whoever is in the party now stays, and returning members
-- only fill free places up to the limit.
function Restrictions.Restore(done)
    local p = Restrictions.GetPending()
    if not p then
        return false, "There is no trimmed party to restore."
    end
    local accepted, message, nothingToDo = Party.Apply(p.party, { addOnly = true }, function(result)
        if result.ok then setPending(nil) end
        if done then done(result) end
    end)
    if nothingToDo then
        setPending(nil)
        return true, "Everyone is already back."
    end
    return accepted, message
end

local function autoRestore()
    local p = Restrictions.GetPending()
    if not p or not p.trimmed then return end
    if PP.Setting("auto_restore", true) == false then
        Restrictions.Notice("The rest of your party is waiting in camp. Use Restore on the Party tab to bring them back.")
        return
    end
    local tries = 0
    local function attempt()
        -- Another trigger (or the player) may have finished the job already.
        local current = Restrictions.GetPending()
        if not current or not current.trimmed then return end
        tries = tries + 1
        local accepted, message = Restrictions.Restore(function(result)
            Restrictions.Notice(result.message, result.ok and "info" or "warning")
        end)
        if accepted then
            if message == "Everyone is already back." then Restrictions.Notice(message) end
            return
        end
        if tries < RESTORE_TRIES then
            Ext.Timer.WaitFor(RESTORE_RETRY_MS, attempt)
        else
            Restrictions.Notice("Could not bring the party back yet (" .. tostring(message)
                .. "). Use Restore on the Party tab.", "warning")
        end
    end
    Ext.Timer.WaitFor(RESTORE_DELAY_MS, attempt)
end

-- Raft: add landing positions 5..16 for every dock, cycling through the
-- existing positions 1..4 of that dock. Only runs where the raft goal's rows
-- exist; inserting an existing row is a no-op.
function Restrictions.ExtendRaft()
    if PP.Setting("extend_raft", true) == false then return 0 end
    local ok, rows = pcall(function() return Osi[RAFT_POSITIONS_DB]:Get(nil, nil, nil) end)
    if not ok or type(rows) ~= "table" or #rows == 0 then return 0 end
    local byFlag = {}
    for _, row in ipairs(rows) do
        local flag, index, trigger = row[1], tonumber(row[2]), row[3]
        if flag and index and trigger then
            byFlag[flag] = byFlag[flag] or {}
            byFlag[flag][index] = trigger
        end
    end
    local added = 0
    for flag, positions in pairs(byFlag) do
        if positions[1] and positions[2] and positions[3] and positions[4] then
            for i = 5, RAFT_MAX_INDEX do
                if not positions[i] then
                    local trigger = positions[((i - 1) % 4) + 1]
                    local okInsert = pcall(function() Osi[RAFT_POSITIONS_DB](flag, i, trigger) end)
                    if okInsert then added = added + 1 end
                end
            end
        end
    end
    if added > 0 then PP.Log("raft: added " .. added .. " landing positions") end
    return added
end

function Restrictions.Register()
    -- Long rest: refuse End the Day while the party is larger than four.
    -- "before" so our row is added after QRY_Camp_CheckPlayersReadyForNightMode
    -- has cleared old reasons and before the readiness test reads them.
    Ext.Osiris.RegisterListener("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before", function()
        if PP.Setting("prompt_long_rest", true) == false then return end
        if not overFour() then return end
        if bypassOnce.rest then bypassOnce.rest = nil; return end
        local ok, err = pcall(function()
            Osi.DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason(REST_REASON)
        end)
        if not ok then PP.Log("could not hold the long rest: " .. tostring(err)) end
    end)

    Ext.Osiris.RegisterListener("PROC_Camp_TryEnterNightModeFailed", 2, "after", function(_, reason)
        if reason ~= REST_REASON then return end
        PP.Log("long rest held: party is larger than four")
        ask("rest")
    end)

    Ext.Osiris.RegisterListener("LongRestFinished", 0, "after", function()
        autoRestore()
    end)

    -- Party changes are blocked during camp night (CampNightMode); try again
    -- once the camp switches back to day (GLO_Camp.txt DB_Camp_NightMode).
    Ext.Osiris.RegisterListener("DB_Camp_NightMode", 1, "afterDelete", function()
        autoRestore()
    end)

    -- The raft goal's rows may only appear after the level started (the
    -- Underdark is in the Act 1 level), so extend again just before the
    -- crew is landed: PROC_UND_EbonLake_DisembarkCrew reads the table.
    Ext.Osiris.RegisterListener("PROC_UND_EbonLake_DisembarkCrew", 1, "before", function()
        Restrictions.ExtendRaft()
    end)
end

return Restrictions
