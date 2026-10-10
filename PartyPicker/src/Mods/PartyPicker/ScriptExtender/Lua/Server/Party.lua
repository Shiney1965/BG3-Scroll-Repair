-- Party Picker (server): read the roster and change the active party.
--
-- Recruiting and dismissing go through the same story procedures the game's
-- own buttons and dialogs use, so the story's bookkeeping (factions, camp,
-- DB_Players, the party-full flag, hireling flags) stays consistent:
--   origin to party     PROC_GLO_PartyMembers_CheckAdd(origin, avatar)
--   origin to camp      PROC_GLO_PartyMembers_Remove(origin, avatar, 1)
--   hireling to party   PROC_Hirelings_TakeFromCamp(hireling, avatar)   (from camp)
--                       PROC_Hirelings_AddToParty(hireling, avatar)     (otherwise)
--   hireling to camp    PROC_GLO_PartyMembers_Remove(hireling, avatar, 0)
--                       + PROC_Hirelings_SendToCamp(hireling)
-- Sources: Shared goal _GLO_Shared_PartyMembers.txt, SharedDev Hirelings.txt
-- (L447-458, L670-682, L1095-1096). See docs/RESEARCH.md.

local Party = {}

-- Each change waits for the story to finish the previous step.
local ADD_DELAY_MS = 250
local VERIFY_DELAY_MS = 600

local HIRELING_IN_CAMP_FLAG = "Hireling_State_InCamp_e33aa0df-fcfc-4a30-8169-516d3956f02a"

local busy = false

local function column1(dbName)
    local out = {}
    local ok, rows = pcall(function() return Osi[dbName]:Get(nil) end)
    if ok and type(rows) == "table" then
        for _, row in ipairs(rows) do
            if row[1] ~= nil then out[#out + 1] = row[1] end
        end
    end
    return out
end

local function uuidSet(dbName)
    local set = {}
    for _, id in ipairs(column1(dbName)) do
        local u = PP.BareUuid(id)
        if u then set[u] = true end
    end
    return set
end

local function isTrue(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and v == 1
end

local function userOf(id)
    local ok, u = pcall(Osi.GetReservedUserID, id)
    if ok then return u end
    return nil
end

-- The character the host is controlling right now. The game's own scripts
-- note this can be a companion rather than the avatar
-- (_GLO_Shared_Origins.txt: "GetHostCharacter(_Avatar) AND NOT DB_Avatars").
function Party.HostCharacter()
    local ok, host = pcall(Osi.GetHostCharacter)
    if ok then return host end
    return nil
end

-- The host's own avatar: the one to recruit and dismiss "by", as the game's
-- dialogs do. Falls back to the controlled character.
function Party.HostAvatar()
    local controlled = Party.HostCharacter()
    if not controlled then return nil end
    if #Osi.DB_Avatars:Get(controlled) > 0 then return controlled end
    local hostUser = userOf(controlled)
    local players = uuidSet("DB_Players")
    for _, id in ipairs(column1("DB_Avatars")) do
        if userOf(id) == hostUser and players[PP.BareUuid(id)] then return id end
    end
    return controlled
end

function Party.DisplayName(id)
    local name = nil
    pcall(function()
        local handle = Osi.GetDisplayName(id)
        if handle then name = Ext.Loca.GetTranslatedString(handle) end
    end)
    if name == nil or name == "" then
        pcall(function()
            local e = Ext.Entity.Get(PP.BareUuid(id))
            name = e.DisplayName.Name:Get()
        end)
    end
    if name == nil or name == "" then return tostring(id) end
    return name
end

function Party.MaxSize()
    local n = tonumber(PP.Setting("max_party_size", 6)) or 6
    if n < PP.RESTRICTED_SIZE then n = PP.RESTRICTED_SIZE end
    return math.floor(n)
end

-- Re-applied on every level load: the override is not known to survive a
-- save (Brawl re-applies it the same way).
function Party.ApplyMaxSize()
    local n = Party.MaxSize()
    local ok, err = pcall(function()
        Osi.SetMaxPartySizeOverride(n)
        Osi.PROC_CheckPartyFull()
    end)
    if ok then
        PP.Log("party size limit set to " .. n)
    else
        PP.Log("could not set the party size limit: " .. tostring(err))
    end
end

-- Everyone the player could choose from.
-- Each entry: id (Osiris string), uuid, name, active, inCamp, avatar,
-- hireling, dead, locked (this mod never moves them), lockReason.
function Party.Roster()
    local controlled = Party.HostCharacter()
    local hostUser = controlled and userOf(controlled) or nil

    local entries, byUuid = {}, {}
    local function add(id, field)
        local u = PP.BareUuid(id)
        if not u then return end
        local e = byUuid[u]
        if not e then
            e = { id = id, uuid = u }
            byUuid[u] = e
            entries[#entries + 1] = e
        end
        e[field] = true
    end
    for _, id in ipairs(column1("DB_PartOfTheTeam")) do add(id, "team") end
    for _, id in ipairs(column1("DB_Hirelings_Hired")) do add(id, "hireling") end
    for _, id in ipairs(column1("DB_Players")) do add(id, "active") end

    local avatars = uuidSet("DB_Avatars")
    local dismissedAvatars = uuidSet("DB_DismissedAvatar")
    local inCamp = uuidSet("DB_InCamp")
    local controlledUuid = PP.BareUuid(controlled)

    local out = {}
    for _, e in ipairs(entries) do
        if not isTrue(Osi.IsSummon, e.id) then
            e.avatar = avatars[e.uuid] == true
            e.inCamp = inCamp[e.uuid] == true
            e.dead = isTrue(Osi.IsDead, e.id)
            e.name = Party.DisplayName(e.id)
            e.active = e.active == true
            e.hireling = e.hireling == true
            if e.avatar or dismissedAvatars[e.uuid] then
                -- Avatars (including dismissed ones, which stay in
                -- DB_PartOfTheTeam) are never recruited or dismissed here.
                e.avatar = true
                e.locked, e.lockReason = true, "player character"
            elseif e.active and e.dead then
                -- Never send a body to camp; the game handles revival.
                e.locked, e.lockReason = true, "dead"
            elseif e.active and e.uuid == controlledUuid then
                e.locked, e.lockReason = true, "you are controlling them"
            elseif e.active and hostUser ~= nil then
                local user = userOf(e.id)
                if user ~= nil and user ~= hostUser then
                    e.locked, e.lockReason = true, "controlled by another player"
                end
            end
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if a.avatar ~= b.avatar then return a.avatar end
        return a.name < b.name
    end)
    return out
end

function Party.ActiveCount()
    local n = 0
    for _, id in ipairs(column1("DB_Players")) do
        if not isTrue(Osi.IsSummon, id) then n = n + 1 end
    end
    return n
end

function Party.ActiveUuids()
    local out = {}
    for _, e in ipairs(Party.Roster()) do
        if e.active then out[#out + 1] = e.uuid end
    end
    return out
end

-- Why a character cannot be moved right now, or nil. Mirrors the checks the
-- Focus Lodestones recruit/dismiss code makes (see docs/RESEARCH.md).
local BLOCKING_DBS = {
    { "DB_InDangerZone", 2 },
    { "DB_FastTravelBlock_BlockedZone_StatusSet", 1 },
    { "DB_FastTravelBlock_CantMove_StatusSet", 1 },
    { "DB_FastTravelBlock_Arrested_StatusSet", 1 },
    { "DB_FastTravelBlock_CampNightMode_StatusSet", 1 },
    { "DB_FastTravelBlock_FugitiveInPrison_StatusSet", 2 },
}

function Party.BlockedReason(id, checkCombat)
    if checkCombat and isTrue(Osi.IsInCombat, id) then return "is in combat" end
    for _, spec in ipairs(BLOCKING_DBS) do
        local name, arity = spec[1], spec[2]
        local ok, rows = pcall(function()
            if arity == 2 then return Osi[name]:Get(id, nil) end
            return Osi[name]:Get(id)
        end)
        if ok and type(rows) == "table" and next(rows) ~= nil then
            return "cannot travel right now (" .. name .. ")"
        end
    end
    return nil
end

local function sendToCamp(e, avatar)
    if e.hireling then
        pcall(Osi.PROC_GLO_PartyMembers_Remove, e.id, avatar, 0)
        pcall(Osi.PROC_Hirelings_SendToCamp, e.id)
    else
        local ok, err = pcall(Osi.PROC_GLO_PartyMembers_Remove, e.id, avatar, 1)
        if not ok then PP.Log("remove failed for " .. e.name .. ": " .. tostring(err)) end
    end
end

local function bringIn(e, avatar)
    local ok, err
    if e.hireling then
        if isTrue(Osi.GetFlag, HIRELING_IN_CAMP_FLAG, e.id) then
            ok, err = pcall(Osi.PROC_Hirelings_TakeFromCamp, e.id, avatar)
        else
            ok, err = pcall(Osi.PROC_Hirelings_AddToParty, e.id, avatar)
        end
    else
        ok, err = pcall(Osi.PROC_GLO_PartyMembers_CheckAdd, e.id, avatar)
    end
    if not ok then PP.Log("add failed for " .. e.name .. ": " .. tostring(err)) end
end

-- Change the party.
--   wanted:  list of uuids that should end up in the party (locked members
--            are kept regardless).
--   opts.limit:     max total size (default: configured maximum)
--   opts.addOnly:   never send anyone to camp; add `wanted` members who are
--                   not in the party, as far as the limit allows
--   done(result):   called once verified; result = { ok, message, changed }
-- Returns accepted, message. When accepted is false nothing was changed;
-- `nothingToDo` is true when the party already matched.
function Party.Apply(wanted, opts, done)
    opts = opts or {}
    done = done or function() end
    if busy then return false, "A party change is already in progress." end
    local avatar = Party.HostAvatar()
    if not avatar then return false, "No host character found." end
    local limit = opts.limit or Party.MaxSize()

    local roster = Party.Roster()
    local byUuid = {}
    for _, e in ipairs(roster) do byUuid[e.uuid] = e end

    local keep, count = {}, 0
    for _, e in ipairs(roster) do
        if e.locked and e.active then keep[e.uuid] = true; count = count + 1 end
        if opts.addOnly and e.active and not keep[e.uuid] then keep[e.uuid] = true; count = count + 1 end
    end
    for _, u in ipairs(wanted or {}) do
        local e = byUuid[u]
        if e and not keep[u] and not e.dead and not (e.locked and not e.active) then
            if opts.addOnly and count >= limit then break end
            keep[u] = true; count = count + 1
        elseif not e and not opts.addOnly then
            return false, "Unknown character " .. tostring(u) .. "."
        elseif e and e.dead and not opts.addOnly then
            return false, e.name .. " is dead."
        end
    end
    if count > limit and not opts.addOnly then
        return false, string.format("%d selected, but the limit is %d.", count, limit)
    end
    if count == 0 then return false, "Nobody selected." end

    local toRemove, toAdd = {}, {}
    for _, e in ipairs(roster) do
        if e.active and not keep[e.uuid] then toRemove[#toRemove + 1] = e end
        if keep[e.uuid] and not e.active then toAdd[#toAdd + 1] = e end
    end
    if #toRemove == 0 and #toAdd == 0 then
        return false, "The party is already like that.", true
    end

    local checkCombat = PP.Setting("block_in_combat", true) ~= false
    local why = Party.BlockedReason(avatar, checkCombat)
    if why then return false, "Party changes are blocked: your character " .. why .. "." end
    for _, list in ipairs({ toRemove, toAdd }) do
        for _, e in ipairs(list) do
            why = Party.BlockedReason(e.id, checkCombat)
            if why then return false, e.name .. " " .. why .. "." end
        end
    end

    busy = true
    -- Room for the new members before anyone is added: CheckAdd does nothing
    -- while the story's party-full flag is set.
    pcall(Osi.SetMaxPartySizeOverride, math.max(Party.MaxSize(), count))

    for _, e in ipairs(toRemove) do sendToCamp(e, avatar) end
    pcall(Osi.PROC_CheckPartyFull)

    -- Any error in the delayed steps must still release `busy` and report.
    local function guarded(fn)
        return function()
            local ok, err = pcall(fn)
            if not ok then
                busy = false
                PP.Log("party change failed: " .. tostring(err))
                done({ ok = false, changed = true, message = "Party change failed: " .. tostring(err) })
            end
        end
    end

    Ext.Timer.WaitFor(ADD_DELAY_MS, guarded(function()
        for _, e in ipairs(toAdd) do bringIn(e, avatar) end

        Ext.Timer.WaitFor(VERIFY_DELAY_MS, guarded(function()
            local failed = {}
            local avatarInCamp = next(Osi.DB_InCamp:Get(avatar) or {}) ~= nil
            local bring = PP.Setting("teleport_joiners", true) ~= false
            for _, e in ipairs(toAdd) do
                if isTrue(Osi.IsInPartyWith, e.id, avatar) then
                    if bring and not avatarInCamp then
                        -- Same 6-argument form the raft script uses.
                        pcall(Osi.TeleportTo, e.id, avatar, "", 0, 1, 1)
                        pcall(Osi.AttachToPartyGroup, e.id, avatar)
                    end
                else
                    failed[#failed + 1] = e.name .. " did not join"
                end
            end
            for _, e in ipairs(toRemove) do
                if isTrue(Osi.IsInPartyWith, e.id, avatar) then
                    failed[#failed + 1] = e.name .. " did not leave"
                end
            end
            busy = false
            if #failed == 0 then
                done({ ok = true, changed = true,
                    message = string.format("Party updated: %d joined, %d sent to camp.", #toAdd, #toRemove) })
            else
                done({ ok = false, changed = true,
                    message = "Party partly updated. " .. table.concat(failed, "; ") .. "." })
            end
        end))
    end))
    return true, "Changing the party..."
end

return Party
