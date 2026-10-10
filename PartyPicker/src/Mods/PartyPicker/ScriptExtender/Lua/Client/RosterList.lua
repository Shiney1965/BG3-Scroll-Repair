-- Party Picker (client): one checkbox per character, used by both the MCM
-- Party tab and the pick-four window.

local RosterList = {}

-- Children is a live array; copy before destroying or half are skipped.
function RosterList.Clear(parent)
    local kids = {}
    for _, child in ipairs(parent.Children or {}) do kids[#kids + 1] = child end
    for _, child in ipairs(kids) do pcall(function() child:Destroy() end) end
end

local function label(e)
    local tags = {}
    if e.avatar then tags[#tags + 1] = "you" end
    if e.hireling then tags[#tags + 1] = "hireling" end
    if e.dead then tags[#tags + 1] = "dead" end
    if not e.active and e.inCamp then tags[#tags + 1] = "in camp" end
    if e.locked and e.lockReason and not e.avatar then tags[#tags + 1] = e.lockReason end
    if #tags == 0 then return e.name end
    return e.name .. "  (" .. table.concat(tags, ", ") .. ")"
end

-- Draws the list into `parent`.
-- opts.limit: how many may be ticked in total (locked members count).
-- opts.preselect(entry) -> bool: initial tick for unlocked entries.
-- opts.readOnly: draw everything disabled.
-- opts.onChange(count): called after every tick change.
-- Returns an object with :Selected() (unlocked uuids ticked) and :Count().
function RosterList.Draw(parent, entries, opts)
    opts = opts or {}
    local ticked = {}
    local list = { entries = entries }

    local function count()
        local n = 0
        for _, e in ipairs(entries) do
            if ticked[e.uuid] then n = n + 1 end
        end
        return n
    end

    for _, e in ipairs(entries) do
        local initial
        if e.locked then
            -- Locked members stay as they are: ticked if in the party.
            initial = e.active == true
        elseif opts.preselect then
            initial = opts.preselect(e) == true
        else
            initial = e.active == true
        end
        if e.dead then initial = false end
        ticked[e.uuid] = initial

        local cb = parent:AddCheckbox(label(e), initial)
        pcall(function() cb.IDContext = "pp_" .. e.uuid end)
        if e.locked or e.dead or opts.readOnly then cb.Disabled = true end
        cb.OnChange = function(_, checked)
            ticked[e.uuid] = checked == true
            if opts.onChange then opts.onChange(count()) end
        end
    end

    function list:Selected()
        local out = {}
        for _, e in ipairs(entries) do
            if ticked[e.uuid] and not e.locked then out[#out + 1] = e.uuid end
        end
        return out
    end

    function list:Count() return count() end

    return list
end

return RosterList
