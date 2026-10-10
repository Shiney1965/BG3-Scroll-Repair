-- Party Picker (client): the window that appears when the game needs a party
-- of four (long rest) and the party is larger.

local RosterList = Ext.Require("Client/RosterList.lua")

local PickFour = {}

local window = nil

local INTRO = {
    rest = {
        "The camp has four beds, and the game only puts four party members to bed.",
        "Choose who stays with you tonight. The others wait in camp",
        "and rejoin when you wake up.",
    },
}

local function ensureWindow()
    if window then
        RosterList.Clear(window)
        return window
    end
    window = Ext.IMGUI.NewWindow("Party Picker")
    window.Closeable = true
    window.AlwaysAutoResize = true
    pcall(function()
        local size = Ext.IMGUI.GetViewportSize()
        if size and size[1] and size[2] then
            -- FirstUseEver so the player can still drag it elsewhere.
            window:SetPos({ math.floor(size[1] * 0.5) - 250, math.floor(size[2] * 0.2) }, "FirstUseEver")
        end
    end)
    return window
end

local function close()
    if window then window.Open = false end
end

local function showMessage(text)
    local w = ensureWindow()
    w:AddText(tostring(text))
    local ok = w:AddButton("OK")
    ok.OnClick = close
    w.Open = true
end

local function render(reason, size, reply)
    local w = ensureWindow()
    for _, line in ipairs(INTRO[reason] or { "Choose " .. size .. " party members." }) do
        w:AddText(line)
    end
    w:AddSeparator()

    -- Start from the members already in the party, in roster order
    -- (your own character first), up to the size.
    local entries = reply.entries or {}
    local taken = 0
    for _, e in ipairs(entries) do
        if e.locked and e.active then taken = taken + 1 end
    end
    local pre = {}
    for _, e in ipairs(entries) do
        if e.active and not e.locked and not e.dead and taken < size then
            pre[e.uuid] = true
            taken = taken + 1
        end
    end

    -- Only party members (and camp companions, in case someone swapped) can be chosen.
    local available = 0
    for _, e in ipairs(entries) do
        if not e.dead and (e.active or not e.locked) then available = available + 1 end
    end
    local need = math.min(size, available)
    local lockedCount = 0
    for _, e in ipairs(entries) do
        if e.locked and e.active then lockedCount = lockedCount + 1 end
    end
    if lockedCount > size then
        -- Several players' characters: this mod never moves those.
        w:AddText(string.format("%d characters belong to players and cannot be sent to camp,", lockedCount))
        w:AddText("so the party cannot be trimmed to four here.")
    end

    local countText, confirm
    local function onChange(n)
        if countText then countText.Label = string.format("Selected %d of %d", n, need) end
        if confirm then confirm.Disabled = (n ~= need) or lockedCount > size end
    end

    local list = RosterList.Draw(w, entries, {
        preselect = function(e) return pre[e.uuid] == true end,
        onChange = onChange,
    })

    w:AddSeparator()
    countText = w:AddText("")
    local status = w:AddText("")

    confirm = w:AddButton("Keep these " .. need)
    confirm.OnClick = function()
        status.Label = "Changing the party..."
        PP.Net.Apply:RequestToServer({ uuids = list:Selected(), reason = reason }, function(resp)
            if resp and resp.accepted then
                -- The server sends a Notice with the outcome; it replaces this window.
                status.Label = resp.message or ""
            else
                status.Label = (resp and resp.message) or "No reply."
            end
        end)
    end

    local keepAll = w:AddButton("Keep everyone this time")
    keepAll.SameLine = true
    keepAll.OnClick = function()
        PP.Net.Apply:RequestToServer({ reason = reason, keepAll = true }, function(resp)
            RosterList.Clear(w)
            showMessage((resp and resp.message) or "No reply.")
        end)
    end

    onChange(list:Count())
    w.Open = true
end

function PickFour.Show(reason, size)
    if not Ext.Net.IsHost() then return end
    size = size or 4
    PP.Net.Roster:RequestToServer({}, function(reply)
        local ok, err = pcall(render, reason, size, reply or {})
        if not ok then PP.Log("could not draw the picker: " .. tostring(err)) end
    end)
end

-- Outcome of a party change started from this window.
function PickFour.Notice(text)
    if window and window.Open then
        RosterList.Clear(window)
        showMessage(text)
    end
end

return PickFour
