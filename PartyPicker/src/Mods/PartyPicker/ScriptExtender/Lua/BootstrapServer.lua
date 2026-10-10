-- Party Picker (server).
Ext.Require("Shared/Common.lua")
local Party = Ext.Require("Server/Party.lua")
local Restrictions = Ext.Require("Server/Restrictions.lua")

local function rosterReply()
    local entries = {}
    for _, e in ipairs(Party.Roster()) do
        entries[#entries + 1] = {
            uuid = e.uuid, name = e.name, active = e.active, inCamp = e.inCamp,
            avatar = e.avatar, hireling = e.hireling, dead = e.dead,
            locked = e.locked == true, lockReason = e.lockReason,
        }
    end
    local pending = Restrictions.GetPending()
    return {
        entries = entries,
        maxSize = Party.MaxSize(),
        pending = pending and { reason = pending.reason, stage = pending.stage } or nil,
    }
end

-- Only the host may change the party; in multiplayer other players' clients
-- see the tab read-only (the client checks Ext.Net.IsHost too).
-- NetChannel handlers receive a network peer id, while Osiris uses a user id;
-- bg3se Docs/API.md gives the conversion (peer & 0xffff0000) | 0x0001.
local function peerToUserId(peer)
    if math.type(peer) ~= "integer" then return nil end
    return (peer & 0xffff0000) | 0x0001
end

local function isHostUser(peer)
    local host = Party.Host()
    if not host then return false end
    local ok, hostUser = pcall(Osi.GetReservedUserID, host)
    if not ok or hostUser == nil then return false end
    return hostUser == peer or hostUser == peerToUserId(peer)
end

PP.Net.Roster:SetRequestHandler(function()
    local ok, reply = pcall(rosterReply)
    if ok then return reply end
    PP.Log("roster failed: " .. tostring(reply))
    return { entries = {}, maxSize = Party.MaxSize(), error = tostring(reply) }
end)

-- data = { uuids = {...}, reason = nil | "rest" | "raft", keepAll = bool }
PP.Net.Apply:SetRequestHandler(function(data, user)
    if not isHostUser(user) then
        return { accepted = false, message = "Only the host can change the party." }
    end
    data = data or {}
    if data.keepAll and data.reason then
        Restrictions.BypassOnce(data.reason)
        return { accepted = true, message = "Keeping everyone this time. Try again to continue." }
    end
    local limit = nil
    if data.reason then limit = PP.RESTRICTED_SIZE end
    local accepted, message = Party.Apply(data.uuids or {}, limit, function(result)
        Restrictions.Notice(result.message, result.ok and "info" or "warning")
        if result.ok and data.reason then Restrictions.OnTrimmed(data.reason) end
    end)
    return { accepted = accepted, message = message }
end)

PP.Net.Restore:SetRequestHandler(function(_, user)
    if not isHostUser(user) then
        return { accepted = false, message = "Only the host can change the party." }
    end
    local accepted, message = Restrictions.Restore(function(result)
        Restrictions.Notice(result.message, result.ok and "info" or "warning")
    end)
    return { accepted = accepted, message = message }
end)

Restrictions.Register()

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function()
    Party.ApplyMaxSize()
end)

-- MCM fires this in both contexts (BG3-MCM Server/MCMServer.lua).
pcall(function()
    Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(function(payload)
        if not payload or payload.modUUID ~= ModuleUUID then return end
        if payload.settingId == "max_party_size" then Party.ApplyMaxSize() end
    end)
end)

-- Console fallback (server context): !pp_roster, !pp_size, !pp_restore,
-- !pp_set Name1,Name2,...   Names are matched case-insensitively.
Ext.RegisterConsoleCommand("pp_roster", function()
    for _, e in ipairs(Party.Roster()) do
        PP.Log(string.format("%-24s %s%s%s%s%s", e.name,
            e.active and "ACTIVE " or "camp   ",
            e.avatar and "avatar " or "",
            e.hireling and "hireling " or "",
            e.dead and "dead " or "",
            e.locked and ("locked(" .. tostring(e.lockReason) .. ")") or ""))
    end
    PP.Log(string.format("active %d, limit %d (game reports %s)", Party.ActiveCount(), Party.MaxSize(),
        tostring(select(2, pcall(Osi.GetMaxPartySize)))))
end)

Ext.RegisterConsoleCommand("pp_size", function()
    Party.ApplyMaxSize()
end)

Ext.RegisterConsoleCommand("pp_restore", function()
    local accepted, message = Restrictions.Restore(function(result) PP.Log(result.message) end)
    PP.Log(message)
end)

Ext.RegisterConsoleCommand("pp_set", function(_, ...)
    local text = table.concat({ ... }, " ")
    local wanted, missing = {}, {}
    local roster = Party.Roster()
    for name in string.gmatch(text, "[^,]+") do
        name = string.lower((name:gsub("^%s+", ""):gsub("%s+$", "")))
        local found = nil
        for _, e in ipairs(roster) do
            if string.lower(e.name) == name then found = e end
        end
        if found then wanted[#wanted + 1] = found.uuid else missing[#missing + 1] = name end
    end
    if #missing > 0 then
        PP.Log("not found: " .. table.concat(missing, ", ") .. " (see !pp_roster)")
        return
    end
    local accepted, message = Party.Apply(wanted, nil, function(result) PP.Log(result.message) end)
    PP.Log(message)
end)

PP.Log("server loaded. Console (server context): !pp_roster  !pp_set Name1,Name2  !pp_restore  !pp_size")
