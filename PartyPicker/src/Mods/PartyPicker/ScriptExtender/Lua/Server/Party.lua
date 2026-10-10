-- Party Picker (server): read the roster and change the active party.
--
-- Recruiting and dismissing go through the same story procedures the game's
-- own buttons and dialogs use, so the story's bookkeeping (factions, camp,
-- DB_Players, the party-full flag) stays consistent:
--   add      PROC_GLO_PartyMembers_CheckAdd(origin, player)
--            PROC_Hirelings_AddToParty(hireling, avatar)
--   to camp  PROC_GLO_PartyMembers_Remove(member, dismisser, 1)
-- Source: Shared story goal _GLO_Shared_PartyMembers.txt and SharedDev
-- Hirelings.txt; documented in docs/RESEARCH.md.

local Party = {}

-- Each change waits for the story to finish the previous step.
local ADD_DELAY_MS = 250
local VERIFY_DELAY_MS = 600

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

function Party.Host()
    local ok, host = pcall(Osi.GetHostCharacter)
    if ok then return host end
    return nil
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
-- hireling, dead, locked (cannot be benched by this mod), lockReason.
function Party.Roster()
    local host = Party.Host()
    local hostUser = nil
    if host then
        local ok, u = pcall(Osi.GetReservedUserID, host)
        if ok then hostUser = u end
    end

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
    local inCamp = uuidSet("DB_InCamp")

    local out = {}
    for _, e in ipairs(entries) do
        if not isTrue(Osi.IsSummon, e.id) then
            e.avatar = avatars[e.uuid] == true
            e.inCamp = inCamp[e.uuid] == true
            e.dead = isTrue(Osi.IsDead, e.id)
            e.name = Party.DisplayName(e.id)
            e.active = e.active == true
            e.hireling = e.hireling == true
            if e.avatar and e.active then
                e.locked, e.lockReason = true, "player character"
            elseif e.active and hostUser ~= nil then
                local ok, user = pcall(Osi.GetReservedUserID, e.id)
                if ok and user ~= nil and user ~= hostUser then
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
    { "DB_FastTravelBlock_FugitiveInPrison_StatusSet", 2 },
}

local function blockedReason(id, checkCombat)
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

-- Make the active party exactly `wanted` (a list of uuids) plus any locked
-- members. `limit` defaults to the configured maximum. `done(result)` is
-- called once the change has been verified; result = { ok, message }.
-- Returns accepted, message: false if nothing was changed.
function Party.Apply(wanted, limit, done)
    done = done or function() end
    if busy then return false, "A party change is already in progress." end
    local host = Party.Host()
    if not host then return false, "No host character found." end
    limit = limit or Party.MaxSize()

    local roster = Party.Roster()
    local byUuid = {}
    for _, e in ipairs(roster) do byUuid[e.uuid] = e end

    local keep = {}
    local count = 0
    for _, e in ipairs(roster) do
        if e.locked then keep[e.uuid] = true; count = count + 1 end
    end
    for _, u in ipairs(wanted or {}) do
        local e = byUuid[u]
        if not e then return false, "Unknown character " .. tostring(u) .. "." end
        if e.dead then return false, e.name .. " is dead." end
        if not keep[u] then keep[u] = true; count = count + 1 end
    end
    if count > limit then
        return false, string.format("%d selected, but the limit is %d.", count, limit)
    end
    if count == 0 then return false, "Nobody selected." end

    local toRemove, toAdd = {}, {}
    for _, e in ipairs(roster) do
        if e.active and not keep[e.uuid] then toRemove[#toRemove + 1] = e end
        if keep[e.uuid] and not e.active then toAdd[#toAdd + 1] = e end
    end
    if #toRemove == 0 and #toAdd == 0 then
        return false, "The party is already like that."
    end

    local checkCombat = PP.Setting("block_in_combat", true) ~= false
    for _, e in ipairs({ { name = "You", id = host } }) do
        local why = blockedReason(e.id, checkCombat)
        if why then return false, "Party changes are blocked: your character " .. why .. "." end
    end
    for _, list in ipairs({ toRemove, toAdd }) do
        for _, e in ipairs(list) do
            local why = blockedReason(e.id, checkCombat)
            if why then return false, e.name .. " " .. why .. "." end
        end
    end

    busy = true
    -- Room for the new members before anyone is added: CheckAdd does nothing
    -- while the story's party-full flag is set.
    pcall(function()
        Osi.SetMaxPartySizeOverride(math.max(Party.MaxSize(), count))
    end)

    for _, e in ipairs(toRemove) do
        local ok, err = pcall(Osi.PROC_GLO_PartyMembers_Remove, e.id, host, 1)
        if not ok then PP.Log("remove failed for " .. e.name .. ": " .. tostring(err)) end
    end
    pcall(Osi.PROC_CheckPartyFull)

    -- Any error in the delayed steps must still release `busy` and report.
    local function guarded(fn)
        return function()
            local ok, err = pcall(fn)
            if not ok then
                busy = false
                PP.Log("party change failed: " .. tostring(err))
                done({ ok = false, message = "Party change failed: " .. tostring(err) })
            end
        end
    end

    Ext.Timer.WaitFor(ADD_DELAY_MS, guarded(function()
        for _, e in ipairs(toAdd) do
            local ok, err
            if e.hireling then
                ok, err = pcall(Osi.PROC_Hirelings_AddToParty, e.id, host)
            else
                ok, err = pcall(Osi.PROC_GLO_PartyMembers_CheckAdd, e.id, host)
            end
            if not ok then PP.Log("add failed for " .. e.name .. ": " .. tostring(err)) end
        end

        Ext.Timer.WaitFor(VERIFY_DELAY_MS, guarded(function()
            local failed = {}
            local hostInCamp = next(Osi.DB_InCamp:Get(host) or {}) ~= nil
            local bring = PP.Setting("teleport_joiners", true) ~= false
            for _, e in ipairs(toAdd) do
                if isTrue(Osi.IsInPartyWith, e.id, host) then
                    if bring and not hostInCamp then
                        pcall(Osi.TeleportTo, e.id, host)
                        pcall(Osi.AttachToPartyGroup, e.id, host)
                    end
                else
                    failed[#failed + 1] = e.name .. " did not join"
                end
            end
            for _, e in ipairs(toRemove) do
                if isTrue(Osi.IsInPartyWith, e.id, host) then
                    failed[#failed + 1] = e.name .. " did not leave"
                end
            end
            busy = false
            if #failed == 0 then
                done({ ok = true, message = string.format("Party updated: %d joined, %d sent to camp.", #toAdd, #toRemove) })
            else
                done({ ok = false, message = "Party partly updated. " .. table.concat(failed, "; ") .. "." })
            end
        end))
    end))
    return true, "Changing the party..."
end

return Party
