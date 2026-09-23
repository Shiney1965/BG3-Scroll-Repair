-- Scroll Repair (client): shows the on-screen warning when the server finds
-- scrolls in this area that still point at a removed mod's spells.
-- Read-only: this file never changes an item, it only draws a window.

local CHANNEL = "ScrollRepair_Warn"
local TITLE = "Scroll Repair"
local window = nil

local function say(lines)
    local ok, err = pcall(function()
        if window == nil then
            window = Ext.IMGUI.NewWindow(TITLE)
            window.Closeable = true
            window.AlwaysAutoResize = true
            local size = Ext.IMGUI.GetViewportSize()
            if size and size[1] and size[2] then
                -- FirstUseEver so the window stays draggable afterwards.
                window:SetPos({ math.floor(size[1] * 0.5) - 260, math.floor(size[2] * 0.25) }, "FirstUseEver")
            end
        else
            -- Redraw: drop the previous text so the counts do not stack up.
            -- Children is a live array; copy it first, because destroying an
            -- element shifts the rest and a direct walk would skip half.
            local kids = {}
            for _, child in ipairs(window.Children or {}) do kids[#kids + 1] = child end
            for _, child in ipairs(kids) do pcall(function() child:Destroy() end) end
        end
        for _, line in ipairs(lines) do window:AddText(line) end
        local close = window:AddButton("Close")
        close.OnClick = function() window.Open = false end
        window.Open = true
    end)
    if not ok then
        Ext.Utils.Print("[ScrollRepair] could not draw the warning window: " .. tostring(err))
    end
end

Ext.RegisterNetListener(CHANNEL, function(_, payload)
    local ok, data = pcall(Ext.Json.Parse, payload)
    if not ok or type(data) ~= "table" then return end
    local count = tonumber(data.count) or 0
    if count < 1 then return end
    say({
        string.format("%d scroll(s) in this area are broken.", count),
        "",
        "They still point at spells from True Scrolls, which is no longer",
        "installed. Using one crashes the game to desktop.",
        "",
        "To repair them: open the Script Extender console, type",
        "server, then run:    !scrollrepair_fix",
        "",
        "Nothing has been changed. This is only a warning.",
    })
end)
