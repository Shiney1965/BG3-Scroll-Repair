-- Party Picker (client): the "Party" tab inside Mod Configuration Menu.
-- Lists everyone recruited; tick who should be in the party and press Apply.

local RosterList = Ext.Require("Client/RosterList.lua")

local PartyTab = {}

local root = nil       -- the IMGUI container we draw into
local statusText = nil -- last message from the server

local function setStatus(text)
    if statusText then pcall(function() statusText.Label = tostring(text or "") end) end
end

local function render(reply)
    if not root then return end
    RosterList.Clear(root)
    statusText = nil

    local isHost = Ext.Net.IsHost()
    local entries = reply.entries or {}
    local limit = reply.maxSize or 4

    if reply.error then
        root:AddText("Could not read the party: " .. tostring(reply.error))
    end
    if not isHost then
        root:AddText("Only the host can change the party.")
    end
    root:AddText(string.format("Tick who should be in your party. Limit: %d (change it in Settings).", limit))
    root:AddSeparator()

    local countText
    local applyButton
    local function onChange(n)
        if countText then
            countText.Label = string.format("Selected %d of %d", n, limit)
        end
        if applyButton then applyButton.Disabled = (not isHost) or n > limit or n == 0 end
    end

    local list = RosterList.Draw(root, entries, { readOnly = not isHost, onChange = onChange })
    if #entries == 0 then root:AddText("Nobody recruited yet.") end

    root:AddSeparator()
    countText = root:AddText("")
    applyButton = root:AddButton("Apply")
    applyButton.OnClick = function()
        setStatus("Changing the party...")
        PP.Net.Apply:RequestToServer({ uuids = list:Selected() }, function(resp)
            setStatus(resp and resp.message or "No reply.")
            -- The change takes about a second; show the result afterwards.
            Ext.Timer.WaitForRealtime(1500, PartyTab.Refresh)
        end)
    end
    local refresh = root:AddButton("Refresh")
    refresh.SameLine = true
    refresh.OnClick = PartyTab.Refresh

    if reply.pending and reply.pending.stage == "trimmed" then
        root:AddSeparator()
        root:AddText("Your party was trimmed to four (" .. tostring(reply.pending.reason) .. ").")
        local restore = root:AddButton("Restore full party")
        restore.Disabled = not isHost
        restore.OnClick = function()
            setStatus("Restoring...")
            PP.Net.Restore:RequestToServer({}, function(resp)
                setStatus(resp and resp.message or "No reply.")
                Ext.Timer.WaitForRealtime(1500, PartyTab.Refresh)
            end)
        end
    end

    statusText = root:AddText("")
    onChange(list:Count())
end

function PartyTab.Refresh()
    if not root then return end
    PP.Net.Roster:RequestToServer({}, function(reply)
        local ok, err = pcall(render, reply or {})
        if not ok then PP.Log("could not draw the Party tab: " .. tostring(err)) end
    end)
end

function PartyTab.SetStatus(text) setStatus(text) end

-- Draw into any IMGUI container (the MCM tab, or a standalone window).
function PartyTab.Attach(container)
    root = container
    root:AddText("Loading...")
    PartyTab.Refresh()
end

return PartyTab
