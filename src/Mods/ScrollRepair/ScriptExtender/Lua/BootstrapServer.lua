-- Scroll Repair: rebuild scrolls whose saved SpellBook still points at a
-- True Scrolls spell variant (X_TrueScrolls). With True Scrolls removed those
-- spells do not exist, and using such a scroll crashes the game.
--
-- Method: the same one True Scrolls uses in its own RecreateScrolls(). Delete
-- the item, then TemplateAddTo the same root template, same holder, same stack
-- amount. Runs ONLY with True Scrolls inactive, so the template in memory is
-- vanilla and the rebuilt item is clean.
--
-- Safety (v1.3, after three adversarial reviews):
--   * rebuild a row only if item, holder and root template verifiably exist,
--     the stack amount is read (never guessed), the recorded holder is the
--     item's direct inventory owner, and the item is verifiably not a story item
--   * trader stock (direct holder OR top-level owner tagged TRADER) is skipped
--     unless "traders" is passed
--   * each delete and add is individually protected; an add happens only after
--     the old item is confirmed gone (re-checked, bounded retries)
--   * verification sums actual stack amounts of scrolls per holder+template
--     before and after (independent of TemplateIsInInventory); any unreadable
--     value, any mismatch, any leftover affected scroll => PROBLEM, never OK
--   * only entities loaded in the current level are seen
--
-- Server console:
--   !scrollrepair_scan               list affected scrolls, change nothing
--   !scrollrepair_fix dry            show exactly what the fix would do
--   !scrollrepair_fix                rebuild, then verify
--   !scrollrepair_fix dry traders    same, including trader stock
--   !scrollrepair_fix traders

local TRUESCROLLS_UUID = "deffc003-29da-4d9e-8967-64f3dc4c1b32"
local TRADER_TAG = "91d5ebc6-91ea-44db-8a51-216860d69b5b"
local TAG = "[ScrollRepair] "
local DELETE_CHECK_MS = 500
local DELETE_CHECK_TRIES = 10

local function log(msg) Ext.Utils.Print(TAG .. msg) end

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function osiTrue(fn) return safe(fn) == 1 end
local function osiFalse(fn) return safe(fn) == 0 end

local function lower(s) return s and string.lower(tostring(s)) or nil end

local function isScroll(e)
    return safe(function() return e.Use and e.Use.ItemUseType == "Scroll" end) == true
end

local function holderOf(e)
    return lower(safe(function()
        return e.InventoryMember.Inventory.InventoryIsOwned.Owner.Uuid.EntityUuid
    end))
end

local function templateOf(e)
    return lower(safe(function() return e.GameObjectVisual.RootTemplateId end))
end

local function keyOf(holder, template) return tostring(holder) .. "|" .. tostring(template) end

-- One pass over every loaded scroll: the affected rows, the total scrolls
-- seen, and the summed stack amount per holder+template for ALL scrolls
-- (affected and clean). A sum that could not be fully read is marked false.
local function collect(countOnly)
    local found, seen, sums = {}, 0, {}
    for _, e in ipairs(Ext.Entity.GetAllEntitiesWithComponent("SpellBook")) do
        if isScroll(e) then
            seen = seen + 1
            local uuid = lower(safe(function() return e.Uuid.EntityUuid end))
            local holder = holderOf(e)
            local tpl = templateOf(e)
            local amount = (not countOnly) and uuid
                and safe(function() return Osi.GetStackAmount(uuid) end) or nil

            if holder and tpl and not countOnly then
                local k = keyOf(holder, tpl)
                if type(amount) == "number" and sums[k] ~= false then
                    sums[k] = (sums[k] or 0) + amount
                else
                    sums[k] = false
                end
            end

            local spells = safe(function() return e.SpellBook.Spells end) or {}
            local bad = nil
            for _, s in ipairs(spells) do
                local proto = safe(function() return tostring(s.Id.OriginatorPrototype) end) or ""
                if string.find(proto, "TrueScrolls", 1, true) then
                    bad = proto
                    break
                end
            end
            if bad and countOnly then
                found[#found + 1] = { uuid = uuid, spell = bad, template = tpl, owner = holder }
            elseif bad then
                found[#found + 1] = {
                    uuid = uuid,
                    spell = bad,
                    template = tpl,
                    owner = holder,
                    direct = uuid and lower(safe(function() return Osi.GetDirectInventoryOwner(uuid) end)) or nil,
                    top = uuid and lower(safe(function() return Osi.GetInventoryOwner(uuid) end)) or nil,
                    osiTemplate = uuid and lower(safe(function() return Osi.GetTemplate(uuid) end)) or nil,
                    amount = amount,
                }
            end
        end
    end
    return found, seen, sums
end

local function describe(r)
    return string.format("%s  spell=%s  template=%s  osiTemplate=%s  holder=%s  amount=%s",
        tostring(r.uuid), tostring(r.spell), tostring(r.template), tostring(r.osiTemplate),
        tostring(r.owner), tostring(r.amount))
end

-- Fails closed: only a readable 0 counts as "not tagged".
local function verifiablyUntagged(guid, tag)
    return osiFalse(function() return Osi.IsTagged(guid, tag) end)
end

local function endsWith(s, suffix)
    return s ~= nil and suffix ~= nil and #s >= #suffix and string.sub(s, -#suffix) == suffix
end

-- nil = eligible; otherwise the reason this row is skipped.
local function skipReason(r, includeTraders)
    if not r.uuid or not osiTrue(function() return Osi.Exists(r.uuid) end) then return "item does not exist" end
    if not r.owner then return "not in an inventory (loose in the world)" end
    if not osiTrue(function() return Osi.Exists(r.owner) end) then return "holder does not exist" end
    if not r.direct or string.find(r.direct, r.owner, 1, true) == nil then
        return "holder mismatch (direct owner " .. tostring(r.direct) .. ")"
    end
    if not r.template or safe(function() return Ext.Template.GetRootTemplate(r.template) end) == nil then
        return "root template not found"
    end
    if not endsWith(r.osiTemplate, r.template) then
        return "template mismatch (game reports " .. tostring(r.osiTemplate) .. ")"
    end
    if type(r.amount) ~= "number" or r.amount < 1 then return "stack amount unreadable" end
    if not osiFalse(function() return Osi.IsStoryItem(r.uuid) end) then return "story item (or unreadable)" end
    if not includeTraders then
        local topGuid = r.top and string.match(r.top, "(%x+%-%x+%-%x+%-%x+%-%x+)$") or nil
        if not verifiablyUntagged(r.owner, TRADER_TAG)
            or (topGuid ~= nil and not verifiablyUntagged(topGuid, TRADER_TAG)) then
            return "trader stock or trader tag unreadable (pass 'traders' to include)"
        end
    end
    return nil
end

local function scan()
    local found, seen = collect()
    log(string.format("scrolls seen %d, affected %d (current level only)", seen, #found))
    for _, r in ipairs(found) do log("  " .. describe(r)) end
end

local busy = false

local function finish(state)
    local ok, err = pcall(function()
        local left, seenAfter, sumsAfter = collect()
        local problems = 0
        log(string.format("VERIFY: scrolls seen before %d, after %d; still affected %d; not deleted %d; add failures %d",
            state.seenBefore, seenAfter, #left, state.notDeleted, state.addFailures))
        if state.notDeleted > 0 then problems = problems + 1 end
        if state.addFailures > 0 then problems = problems + 1 end

        for k, before in pairs(state.sumsBefore) do
            local after = sumsAfter[k]
            if type(after) ~= "number" then
                problems = problems + 1
                log(string.format("  COUNT UNREADABLE AFTER %s  before=%s after=%s", k, tostring(before), tostring(after)))
            elseif after ~= before then
                problems = problems + 1
                log(string.format("  COUNT CHANGED %s  before=%d after=%d", k, before, after))
            end
        end

        -- Leftovers on keys we rebuilt mean a new stack merged into a skipped
        -- broken one, or the rebuild did not take.
        for _, r in ipairs(left) do
            local k = keyOf(r.owner, r.template)
            if r.uuid and state.deletedUuids[r.uuid] then
                problems = problems + 1
                log("  DELETED ITEM STILL PRESENT: " .. describe(r))
            elseif state.sumsBefore[k] ~= nil then
                problems = problems + 1
                log("  STILL AFFECTED on a rebuilt holder/template: " .. describe(r))
            else
                log("  still affected (was skipped, left untouched): " .. describe(r))
            end
        end

        if problems == 0 then
            log("VERIFY: OK - every rebuilt holder/template has the same scroll quantity as before. Safe to save.")
        else
            log(string.format("VERIFY: PROBLEM (%d) - do NOT save over your backup. Post these lines.", problems))
        end
    end)
    if not ok then log("VERIFY step errored (treat as PROBLEM, do not save): " .. tostring(err)) end
    busy = false
end

local function addAll(state, tries)
    -- Group by holder|template. A group is re-added only when EVERY row in it
    -- is confirmed gone, so a new stack cannot merge into a sibling stack that
    -- is still waiting to be deleted.
    local groups, order = {}, {}
    for _, r in ipairs(state.deleted) do
        if not r.added then
            local k = keyOf(r.owner, r.template)
            if not groups[k] then groups[k] = {} order[#order + 1] = k end
            table.insert(groups[k], r)
        end
    end
    local pending = {}
    for _, k in ipairs(order) do
        local allGone = true
        for _, r in ipairs(groups[k]) do
            if not osiFalse(function() return Osi.Exists(r.uuid) end) then allGone = false break end
        end
        if allGone then
            for _, r in ipairs(groups[k]) do
                local ok, err = pcall(function() Osi.TemplateAddTo(r.template, r.owner, r.amount, 0) end)
                r.added = true
                if not ok then
                    state.addFailures = state.addFailures + 1
                    log("  ADD FAILED (item deleted, NOT re-added): " .. describe(r) .. "  error=" .. tostring(err))
                end
            end
        else
            for _, r in ipairs(groups[k]) do pending[#pending + 1] = r end
        end
    end
    if #pending > 0 and tries < DELETE_CHECK_TRIES then
        Ext.Timer.WaitFor(DELETE_CHECK_MS, function()
            local ok, err = pcall(function() addAll(state, tries + 1) end)
            if not ok then
                log("ADD step errored (treat as PROBLEM, do not save): " .. tostring(err))
                busy = false
            end
        end)
        return
    end
    for _, r in ipairs(pending) do
        -- Deletion unconfirmed: nothing was added for this group. The item may
        -- or may not be gone, so this is always reported as a PROBLEM.
        state.notDeleted = state.notDeleted + 1
        log("  DELETE UNCONFIRMED after waiting, nothing re-added for its group: " .. describe(r))
    end
    Ext.Timer.WaitFor(2000, function() finish(state) end)
end

local function fix(dry, includeTraders)
    if Ext.Mod.IsModLoaded(TRUESCROLLS_UUID) then
        log("REFUSING: True Scrolls is loaded. Deactivate it first, or the rebuilt scrolls come back broken.")
        return
    end
    if busy then
        log("a fix is already in progress; wait for the VERIFY lines")
        return
    end
    local found, seenBefore, sums = collect()
    if #found == 0 then
        log(string.format("nothing to fix (scrolls seen %d)", seenBefore))
        return
    end

    local todo, skipped, need = {}, 0, {}
    for _, r in ipairs(found) do
        local why = skipReason(r, includeTraders)
        if why then
            skipped = skipped + 1
            log("  SKIP (" .. why .. "): " .. describe(r))
        else
            todo[#todo + 1] = r
            local k = keyOf(r.owner, r.template)
            need[k] = (need[k] or 0) + r.amount
        end
    end

    -- Only rebuild holder/template groups whose total quantity is readable
    -- and covers what we are about to delete.
    local final, sumsBefore = {}, {}
    for _, r in ipairs(todo) do
        local k = keyOf(r.owner, r.template)
        local s = sums[k]
        if type(s) == "number" and s >= need[k] then
            final[#final + 1] = r
            sumsBefore[k] = s
        else
            skipped = skipped + 1
            log("  SKIP (quantity for this holder/template unreadable): " .. describe(r))
        end
    end

    log(string.format("%s: scrolls seen %d, affected %d, to rebuild %d, skipped %d",
        dry and "DRY RUN" or "FIXING", seenBefore, #found, #final, skipped))
    for _, r in ipairs(final) do
        log("  " .. (dry and "would rebuild " or "rebuild ") .. describe(r))
    end
    if dry or #final == 0 then return end

    log("DO NOT SAVE, LOAD OR CHANGE AREA until the VERIFY lines appear (a few seconds; keep the game unpaused).")
    busy = true
    local state = {
        deleted = {}, deletedUuids = {}, seenBefore = seenBefore, sumsBefore = sumsBefore,
        addFailures = 0, notDeleted = 0,
    }
    -- Delete everything first, then add only once each item is confirmed
    -- gone, so a new stack cannot merge into an item that is about to go.
    for _, r in ipairs(final) do
        local ok, err = pcall(function() Osi.RequestDelete(r.uuid) end)
        if ok then
            state.deleted[#state.deleted + 1] = r
            state.deletedUuids[r.uuid] = true
        else
            log("  DELETE FAILED, left untouched: " .. describe(r) .. "  error=" .. tostring(err))
        end
    end
    Ext.Timer.WaitFor(DELETE_CHECK_MS, function()
        local ok, err = pcall(function() addAll(state, 1) end)
        if not ok then
            log("ADD step errored (treat as PROBLEM, do not save): " .. tostring(err))
            busy = false
        end
    end)
end

-- Read-only watch: after each area load, count affected scrolls here and, if
-- any, tell the client to show a warning window. Changes nothing.
local WARN_CHANNEL = "ScrollRepair_Warn"
local WARN_DELAY_MS = 6000
local warnPending = false
local warnedLevels = {}   -- one warning per area per session, not per load

local function warnIfAffected(level)
    warnPending = false
    if busy then return end
    local ok, err = pcall(function()
        local found, seen = collect(true)
        log(string.format("area check (%s): scrolls seen %d, affected %d", tostring(level), seen, #found))
        if #found > 0 then
            warnedLevels[level or "?"] = true
            Ext.ServerNet.BroadcastMessage(WARN_CHANNEL, Ext.Json.Stringify({ count = #found }))
        end
    end)
    if not ok then log("area check failed: " .. tostring(err)) end
end

local function scheduleWarn(level)
    level = level or "?"
    if warnPending or busy or warnedLevels[level] then return end
    warnPending = true
    Ext.Timer.WaitFor(WARN_DELAY_MS, function() warnIfAffected(level) end)
end

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function(level, _)
    scheduleWarn(level)
end)

Ext.RegisterConsoleCommand("scrollrepair_scan", function() scan() end)
Ext.RegisterConsoleCommand("scrollrepair_fix", function(_, a1, a2)
    local dry = (a1 == "dry" or a2 == "dry")
    local traders = (a1 == "traders" or a2 == "traders")
    fix(dry, traders)
end)

Ext.Events.SessionLoaded:Subscribe(function()
    log("v1.4.1 loaded. Commands: !scrollrepair_scan | !scrollrepair_fix dry | !scrollrepair_fix")
    -- Timers do not survive a save load, so clear the latch before scheduling.
    warnPending = false
    scheduleWarn()
end)
