-- Party Picker: things both the server and the client need.
-- Loaded first by both bootstrap files.

PP = PP or {}

PP.MOD = "PartyPicker"
-- The four-member situations are hard limits in the game's own scripts
-- (four beds in camp, four raft seats), so this is not a setting.
PP.RESTRICTED_SIZE = 4

function PP.Log(msg)
    Ext.Utils.Print("[" .. PP.MOD .. "] " .. tostring(msg))
end

-- Osiris hands out "Name_<uuid>" strings; the entity system and our own
-- bookkeeping use the bare uuid. A uuid is always the last 36 characters.
function PP.BareUuid(id)
    if type(id) ~= "string" or #id < 36 then return nil end
    return string.sub(id, -36)
end

-- MCM may be missing or not loaded yet; never let a settings read break gameplay.
function PP.Setting(id, fallback)
    if MCM == nil or MCM.Get == nil then return fallback end
    local ok, value = pcall(MCM.Get, id)
    if not ok or value == nil then return fallback end
    return value
end

-- The same channels must exist in both contexts (bg3se Docs/API.md, NetChannel API).
PP.Net = PP.Net or {
    -- client -> server request: returns the roster for the picker UI
    Roster = Ext.Net.CreateChannel(ModuleUUID, "Roster"),
    -- client -> server request: make the active party exactly this set
    Apply = Ext.Net.CreateChannel(ModuleUUID, "Apply"),
    -- client -> server request: put back the party that was trimmed to four
    Restore = Ext.Net.CreateChannel(ModuleUUID, "Restore"),
    -- server -> clients message: the game needs a party of four, ask the host
    PickFour = Ext.Net.CreateChannel(ModuleUUID, "PickFour"),
    -- server -> clients message: one-line status for the host
    Notice = Ext.Net.CreateChannel(ModuleUUID, "Notice"),
}

-- The trimmed party waiting to be restored; saved with the game, server-only.
-- Registered in both contexts as bg3se Docs/API.md recommends.
pcall(function()
    Ext.Vars.RegisterModVariable(ModuleUUID, "Pending", {
        Server = true, Client = false, SyncToClient = false,
    })
end)

return PP
