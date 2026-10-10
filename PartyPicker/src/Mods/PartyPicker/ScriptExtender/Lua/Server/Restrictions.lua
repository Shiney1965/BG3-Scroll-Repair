-- Party Picker (server): the two places where the game's own scripts only
-- handle four party members, and what this mod does about each.
--
-- 1. Long rest. PROC_Camp_PlacePlayersInBed (Shared goal GLO_Camp.txt) puts
--    exactly four players into the four camp beds; anyone else is left out.
--    The camp flow already has a supported way to refuse End the Day with a
--    story reason: QRY_Camp_CheckPlayersReadyForNightModeStoryReasons adds a
--    row to DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason, the request
--    fails, and PROC_Camp_TryEnterNightModeFailed(player, reason) is called.
--    We add our own reason when the party is larger than four, then ask which
--    four to keep. After LongRestFinished the full party is put back.
--
-- 2. The Ebonlake raft to Grymforge (Act 1 goal Act1_UND_EbonLake.txt). The
--    ready check and the seat positions take four players. The script already
--    blocks the ready check for one case (Glut's owner) with
--    SetReadyCheckBlocked(player, 1); we do the same when the party is larger
--    than four, so the check fails cleanly, then ask which four to take. When
--    the raft arrives at the cave or the camp dock the full party is put back.
--
-- Both hooks only use listeners and story databases; no story file is
-- replaced. Both need in-game confirmation (docs/TESTING.md).

local Party = Ext.Require("Server/Party.lua")

local Restrictions = {}

local REST_REASON = "PartyPicker_PartyLargerThanFour"
local RAFT_READY_CHECK = "ReadyCheck_EbonLake"
local RAFT_ARRIVAL_FLAGS = {
    ["beb83efd-711a-4e20-8d87-470050aebee8"] = "cave", -- UND_EbonLake_State_RaftAtCave
    ["526b966d-e826-4290-8331-e4747c1df3a5"] = "camp", -- UND_EbonLake_State_RaftAtCamp
}
local RESTORE_DELAY_MS = 2000

-- Pending trim, saved with the game so a save/load between trimming and
-- restoring does not lose the party: { reason, party = {uuid...}, stage }.
-- stage: "asking" (picker open) or "trimmed" (waiting to restore).
Ext.Vars.RegisterModVariable(ModuleUUID, "Pending", {
    Server = true, Client = false, SyncToClient = false,
})

local raftBlockedFor = nil
-- "Keep everyone this time" in the picker skips the next hold of that kind.
local bypassOnce = {}

local function vars() return Ext.Vars.GetModVariables(ModuleUUID) end

function Restrictions.GetPending()
    local ok, p = pcall(function() return vars().Pending end)
    if ok and type(p) == "table" and p.reason then return p end
    return nil
end

local function setPending(p)
    -- Whole-table assignment: writes to sub-fields are not saved (API.md).
    pcall(function() vars().Pending = p end)
end

function Restrictions.BypassOnce(reason)
    bypassOnce[reason] = true
    setPending(nil)
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
    local existing = Restrictions.GetPending()
    local party = Party.ActiveUuids()
    if existing and existing.stage == "trimmed" and existing.party then
        -- Already trimmed once and not yet restored: keep the original list.
        party = existing.party
    end
    setPending({ reason = reason, party = party, stage = "asking" })
    PP.Net.PickFour:Broadcast({ reason = reason, size = PP.RESTRICTED_SIZE })
end

-- Called by the Apply request handler when the picker's choice is confirmed.
function Restrictions.OnTrimmed(reason)
    local p = Restrictions.GetPending()
    if not p then return end
    p.stage = "trimmed"
    setPending(p)
    if reason == "rest" then
        Restrictions.Notice("Party trimmed to four for the night. Press End the Day again.")
    elseif reason == "raft" then
        Restrictions.Notice("Party trimmed to four for the raft. Use the raft again.")
    end
end

function Restrictions.Cancel()
    setPending(nil)
end

-- Put back the party that was trimmed. Locked members are kept anyway.
function Restrictions.Restore(done)
    local p = Restrictions.GetPending()
    if not p or not p.party then
        return false, "There is no trimmed party to restore."
    end
    local alive = {}
    local roster = Party.Roster()
    local known = {}
    for _, e in ipairs(roster) do
        if not e.dead then known[e.uuid] = true end
    end
    for _, u in ipairs(p.party) do
        if known[u] then alive[#alive + 1] = u end
    end
    local accepted, message = Party.Apply(alive, nil, function(result)
        if result.ok then setPending(nil) end
        if done then done(result) end
    end)
    return accepted, message
end

local function autoRestore(reason)
    local p = Restrictions.GetPending()
    if not p or p.stage ~= "trimmed" or p.reason ~= reason then return end
    if PP.Setting("auto_restore", true) == false then
        Restrictions.Notice("Your full party is waiting in camp. Use Restore on the Party tab to bring them back.")
        return
    end
    Ext.Timer.WaitFor(RESTORE_DELAY_MS, function()
        local accepted, message = Restrictions.Restore(function(result)
            Restrictions.Notice(result.message, result.ok and "info" or "warning")
        end)
        if not accepted then
            Restrictions.Notice("Could not restore the party yet: " .. tostring(message), "warning")
        end
    end)
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
        autoRestore("rest")
    end)

    -- Raft: fail the ready check the way the script does for Glut's owner.
    Ext.Osiris.RegisterListener("PROC_UND_EbonLake_ReadyCheckSpecific", 4, "before", function()
        if PP.Setting("prompt_raft", true) == false then return end
        if not overFour() then return end
        if bypassOnce.raft then bypassOnce.raft = nil; return end
        local host = Party.Host()
        if not host then return end
        local ok, err = pcall(Osi.SetReadyCheckBlocked, host, 1)
        if ok then
            raftBlockedFor = host
            PP.Log("raft crossing held: party is larger than four")
        else
            PP.Log("could not hold the raft crossing: " .. tostring(err))
        end
    end)

    local function releaseRaft()
        if raftBlockedFor then
            pcall(Osi.SetReadyCheckBlocked, raftBlockedFor, 0)
            raftBlockedFor = nil
            return true
        end
        return false
    end

    Ext.Osiris.RegisterListener("ReadyCheckFailed", 1, "after", function(id)
        if id ~= RAFT_READY_CHECK then return end
        if releaseRaft() then ask("raft") end
    end)

    Ext.Osiris.RegisterListener("ReadyCheckPassed", 1, "after", function(id)
        if id == RAFT_READY_CHECK then releaseRaft() end
    end)

    Ext.Osiris.RegisterListener("FlagSet", 3, "after", function(flag)
        if RAFT_ARRIVAL_FLAGS[PP.BareUuid(flag) or ""] then autoRestore("raft") end
    end)
end

return Restrictions
