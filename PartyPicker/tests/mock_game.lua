-- A small fake of the parts of Script Extender and Osiris that Party Picker
-- touches, so the server logic can run outside the game.
-- It models the story procedures only as far as docs/RESEARCH.md documents
-- them; passing here does not prove the mod works in game (see TESTING.md).

local M = {}

M.LUA_ROOT = LUA_ROOT -- set by the runner
M.log = {}
M.timers = {}
M.listeners = {}
M.broadcasts = {}
M.console = {}

local function uuidOf(id) return string.sub(id, -36) end

-- Osiris databases ---------------------------------------------------------
local dbs = {}
local function newDb(name)
    local db = { name = name, rows = {} }
    function db:Get(...)
        local filter = { ... }
        local out = {}
        for _, row in ipairs(self.rows) do
            local match = true
            for i = 1, select("#", ...) do
                if filter[i] ~= nil and uuidOf(tostring(filter[i])) ~= uuidOf(tostring(row[i])) then
                    match = false
                end
            end
            if match then out[#out + 1] = row end
        end
        return out
    end
    function db:Delete(...)
        local filter = { ... }
        local keep = {}
        for _, row in ipairs(self.rows) do
            local match = true
            for i = 1, select("#", ...) do
                if filter[i] ~= nil and uuidOf(tostring(filter[i])) ~= uuidOf(tostring(row[i])) then
                    match = false
                end
            end
            if not match then keep[#keep + 1] = row end
        end
        self.rows = keep
    end
    setmetatable(db, {
        __call = function(self, ...)
            local row = { ... }
            if #self:Get(...) == 0 then self.rows[#self.rows + 1] = row end
        end,
    })
    return db
end

function M.db(name)
    if not dbs[name] then dbs[name] = newDb(name) end
    return dbs[name]
end

-- World state --------------------------------------------------------------
M.chars = {}   -- uuid -> { id, name, user, summon, dead, inCombat }
M.maxOverride = nil
M.readyCheckBlocked = {}
M.teleported = {}

function M.addChar(name, uuid, opts)
    opts = opts or {}
    local c = { id = name .. "_" .. uuid, uuid = uuid, name = name, user = opts.user or 65537,
        summon = opts.summon, dead = opts.dead, inCombat = opts.inCombat }
    M.chars[uuid] = c
    return c
end

local function char(id) return M.chars[uuidOf(id)] end

local function playerCount()
    local n = 0
    for _, row in ipairs(M.db("DB_Players").rows) do
        if not (char(row[1]) or {}).summon then n = n + 1 end
    end
    return n
end

local Osi = {}
M.Osi = Osi

-- The character the host controls; may be a companion (M.controlled).
function Osi.GetHostCharacter() return (M.controlled or M.host).id end
function Osi.GetReservedUserID(id) return (char(id) or {}).user end
function Osi.IsSummon(id) return (char(id) or {}).summon and 1 or 0 end
function Osi.IsDead(id) return (char(id) or {}).dead and 1 or 0 end
function Osi.IsInCombat(id) return (char(id) or {}).inCombat and 1 or 0 end
function Osi.GetDisplayName(id) return "h_" .. uuidOf(id) end
function Osi.GetMaxPartySize() return M.maxOverride or 4 end
function Osi.SetMaxPartySizeOverride(n) M.maxOverride = n end
function Osi.PROC_CheckPartyFull() M.partyFull = playerCount() >= Osi.GetMaxPartySize() end
function Osi.IsInPartyWith(a, b)
    local inP = function(x) return #M.db("DB_Players"):Get(x) > 0 end
    return (inP(a) and inP(b)) and 1 or 0
end
-- Script Extender matches Osiris functions by exact argument count; the
-- header has overloads with 5, 6 and 8 arguments (Osi.lua).
function Osi.TeleportTo(...)
    local n = select("#", ...)
    assert(n == 5 or n == 6 or n == 8, "TeleportTo has no overload with " .. n .. " arguments")
    M.teleported[#M.teleported + 1] = uuidOf((...))
end
M.flags = {}
function Osi.GetFlag(flag, obj) return M.flags[flag .. "|" .. uuidOf(obj)] and 1 or 0 end
M.counters = { Hirelings_InCamp_Count = 0 }
-- SharedDev Hirelings.txt L447-451, L670-675.
function Osi.PROC_Hirelings_SendToCamp(h)
    M.flags["Hireling_State_InCamp_e33aa0df-fcfc-4a30-8169-516d3956f02a|" .. uuidOf(h)] = true
    M.counters.Hirelings_InCamp_Count = M.counters.Hirelings_InCamp_Count + 1
end
function Osi.PROC_Hirelings_TakeFromCamp(h, avatar)
    Osi.PROC_Hirelings_AddToParty(h, avatar)
    M.counters.Hirelings_InCamp_Count = M.counters.Hirelings_InCamp_Count - 1
end
function Osi.AttachToPartyGroup() end
function Osi.SetReadyCheckBlocked(id, v) M.readyCheckBlocked[uuidOf(id)] = v end

-- Story procedures, as far as documented (_GLO_Shared_PartyMembers.txt):
-- CheckAdd only adds when the party-full flag is clear; Remove sends a team
-- member to camp.
function Osi.PROC_GLO_PartyMembers_CheckAdd(origin, player)
    Osi.PROC_CheckPartyFull()
    if M.partyFull then return end
    M.db("DB_Players")(origin)
    M.db("DB_PartOfTheTeam")(origin)
    M.db("DB_InCamp"):Delete(origin)
    Osi.PROC_CheckPartyFull()
end
function Osi.PROC_Hirelings_AddToParty(h, avatar)
    Osi.PROC_CheckPartyFull()
    Osi.PROC_GLO_PartyMembers_CheckAdd(h, avatar)
end
function Osi.PROC_GLO_PartyMembers_Remove(member, dismisser, force)
    assert(dismisser ~= nil and force ~= nil, "two-argument Remove")
    assert(#M.db("DB_Avatars"):Get(member) == 0, "avatar removed")
    M.db("DB_Players"):Delete(member)
    if #M.db("DB_PartOfTheTeam"):Get(member) > 0 then M.db("DB_InCamp")(member) end
    Osi.PROC_CheckPartyFull()
end

setmetatable(Osi, {
    __index = function(_, k)
        if string.sub(k, 1, 3) == "DB_" then return M.db(k) end
        return nil
    end,
})

-- Script Extender ----------------------------------------------------------
local required = {}
local modVars = {}

local function channel(name)
    local ch = { name = name }
    function ch:SetHandler(fn) self.handler = fn end
    function ch:SetRequestHandler(fn) self.requestHandler = fn end
    function ch:Broadcast(data) M.broadcasts[#M.broadcasts + 1] = { channel = name, data = data } end
    function ch:SendToServer(data) return self.handler(data, M.hostPeer) end
    function ch:RequestToServer(data, cb) cb(self.requestHandler(data, M.hostPeer)) end
    return ch
end

M.Ext = {
    Utils = { Print = function(s) M.log[#M.log + 1] = s end },
    Net = {
        CreateChannel = function(_, name) return channel(name) end,
        IsHost = function() return true end,
    },
    Require = function(path)
        if required[path] == nil then
            local fn = assert(loadfile(M.LUA_ROOT .. "/" .. path))
            required[path] = fn() or true
        end
        return required[path]
    end,
    Timer = {
        WaitFor = function(ms, fn) M.timers[#M.timers + 1] = fn end,
        WaitForRealtime = function(ms, fn) M.timers[#M.timers + 1] = fn end,
    },
    Vars = {
        RegisterModVariable = function() end,
        GetModVariables = function() return modVars end,
    },
    Osiris = {
        RegisterListener = function(name, arity, when, fn)
            M.listeners[name .. "/" .. arity .. "/" .. when] = fn
        end,
    },
    Loca = {
        GetTranslatedString = function(h)
            local c = M.chars[string.sub(h, 3)]
            return c and c.name or ""
        end,
    },
    Entity = { Get = function() return nil end },
    ModEvents = { BG3MCM = setmetatable({}, { __index = function()
        return { Subscribe = function() end }
    end }) },
    RegisterConsoleCommand = function(name, fn) M.console[name] = fn end,
}

function M.runTimers()
    local guard = 0
    while #M.timers > 0 do
        guard = guard + 1
        assert(guard < 100, "timer loop")
        local fn = table.remove(M.timers, 1)
        fn()
    end
end

function M.fire(name, arity, when, ...)
    local fn = M.listeners[name .. "/" .. arity .. "/" .. when]
    assert(fn, "no listener " .. name)
    return fn(...)
end

function M.activeNames()
    local out = {}
    for _, row in ipairs(M.db("DB_Players").rows) do out[#out + 1] = char(row[1]).name end
    table.sort(out)
    return table.concat(out, ",")
end

return M
