-- Party Picker (client).
Ext.Require("Shared/Common.lua")
local PartyTab = Ext.Require("Client/PartyTab.lua")
local PickFour = Ext.Require("Client/PickFour.lua")

PP.Net.PickFour:SetHandler(function(data)
    data = data or {}
    PickFour.Show(data.reason, data.size)
end)

PP.Net.Notice:SetHandler(function(data)
    local text = data and data.text or ""
    PP.Log(text)
    PickFour.Notice(text)
    PartyTab.SetStatus(text)
end)

-- The Party tab inside MCM. MCM 1.38+ accepts a table of named arguments
-- (BG3-MCM MCMAPIImplementations.lua, InsertModMenuTab).
local inserted = false
if MCM and MCM.InsertModMenuTab then
    local ok, err = pcall(MCM.InsertModMenuTab, {
        tabName = "Party",
        tabCallback = function(tab) PartyTab.Attach(tab) end,
    })
    inserted = ok
    if not ok then PP.Log("could not add the MCM Party tab: " .. tostring(err)) end

    -- Re-read the party whenever our MCM page is opened.
    pcall(function()
        Ext.ModEvents.BG3MCM["MCM_Mod_Tab_Activated"]:Subscribe(function(payload)
            if payload and payload.modUUID == ModuleUUID then PartyTab.Refresh() end
        end)
    end)
end

-- Fallback without MCM (and handy for testing): client console  !pp
local standalone = nil
Ext.RegisterConsoleCommand("pp", function()
    if standalone == nil then
        standalone = Ext.IMGUI.NewWindow("Party Picker - Party")
        standalone.Closeable = true
        standalone.AlwaysAutoResize = true
        PartyTab.Attach(standalone)
    else
        PartyTab.Attach(standalone)
    end
    standalone.Open = true
end)

PP.Log("client loaded" .. (inserted and " (Party tab added to MCM)" or "") .. ". Client console: !pp")
