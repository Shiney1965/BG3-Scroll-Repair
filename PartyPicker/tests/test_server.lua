-- Server-side scenarios for Party Picker against tests/mock_game.lua.
-- Run with: python3 tests/run_tests.py

local M = dofile(TEST_ROOT .. "/mock_game.lua")
M.LUA_ROOT = LUA_ROOT

-- Globals the mod expects from Script Extender.
Ext = M.Ext
Osi = M.Osi
ModuleUUID = "f8e3db24-5fe8-40e0-a2d5-eaaf1013aea9"
local settings = { max_party_size = 6 }
MCM = { Get = function(id) return settings[id] end }

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- The party: Tav (avatar) + 6 companions + 1 hireling, 4 active + a summon.
local U = function(n) return string.format("00000000-0000-0000-0000-%012d", n) end
M.host = M.addChar("Tav", U(1))
local names = { "Shadowheart", "Astarion", "Gale", "Laezel", "Karlach", "Wyll" }
local c = {}
for i, n in ipairs(names) do c[n] = M.addChar(n, U(10 + i)) end
c.Hireling = M.addChar("Hireling", U(30))
local wolf = M.addChar("Wolf", U(40), { summon = true })
M.hostPeer = 65536 -- network peer id; Osiris user id is 65537

for _, ch in pairs(M.chars) do
    if not ch.summon then M.db("DB_PartOfTheTeam")(ch.id) end
end
M.db("DB_Avatars")(M.host.id)
M.db("DB_Hirelings_Hired")(c.Hireling.id)
for _, ch in ipairs({ M.host, c.Shadowheart, c.Astarion, c.Gale, wolf }) do M.db("DB_Players")(ch.id) end
for _, ch in ipairs({ c.Laezel, c.Karlach, c.Wyll, c.Hireling }) do M.db("DB_InCamp")(ch.id) end
Osi.PROC_Hirelings_SendToCamp(c.Hireling.id) -- the hireling was parked in camp by the game

-- Raft goal rows as in Act1_UND_EbonLake.txt: four positions per dock.
local RAFT = "DB_UND_EbonLake_Raft_Locations_PlayerPositions"
local docks = {
    cave = "UND_EbonLake_State_RaftAtCave_beb83efd-711a-4e20-8d87-470050aebee8",
    lake = "UND_EbonLake_State_RaftAtLake_8ff8fe26-4546-40e0-94a5-03dba9001650",
}
for i = 1, 4 do
    M.db(RAFT)(docks.cave, i, "S_UND_DarkLake_BoatPassengerPositionAtCave_906d8dc6-3824-4d37-a09a-40d49831ef74")
    M.db(RAFT)(docks.lake, i, "S_UND_DarkLake_PlayerPositionOnBoat_00" .. i .. "_" .. U(500 + i))
end

dofile(LUA_ROOT .. "/BootstrapServer.lua")
local Party = Ext.Require("Server/Party.lua")
local Restrictions = Ext.Require("Server/Restrictions.lua")

local function apply(data)
    local reply
    PP.Net.Apply:RequestToServer(data, function(r) reply = r end)
    M.runTimers()
    return reply
end

-- 1. Level start applies the limit and extends the raft.
M.fire("LevelGameplayStarted", 2, "after", "WLD_Main_A", 0)
check(M.maxOverride == 6, "limit applied on level start")
check(#M.db(RAFT):Get(docks.cave, nil, nil) == 16, "cave dock has 16 landing positions")
local lake9 = M.db(RAFT):Get(docks.lake, 9, nil)[1]
check(lake9 and lake9[3] == M.db(RAFT):Get(docks.lake, 1, nil)[1][3], "position 9 reuses position 1")
M.fire("LevelGameplayStarted", 2, "after", "WLD_Main_A", 0)
check(#M.db(RAFT).rows == 32, "second level start adds nothing")

-- 2. Roster: 8 characters, summon left out, avatar locked.
local roster = Party.Roster()
check(#roster == 8, "roster has 8 entries, got " .. #roster)
check(roster[1].name == "Tav" and roster[1].locked, "avatar first and locked")
local ids = {}
for _, e in ipairs(roster) do ids[e.name] = e.uuid; check(e.name ~= "Wolf", "summon excluded") end
check(Party.ActiveCount() == 4, "4 active (summon not counted)")

-- 3. Apply a party of six, including the hireling from camp.
local reply = apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Laezel, ids.Karlach, ids.Hireling } })
check(reply and reply.accepted, "apply accepted: " .. tostring(reply and reply.message))
check(M.activeNames() == "Astarion,Hireling,Karlach,Laezel,Shadowheart,Tav,Wolf",
    "six active after apply, got " .. M.activeNames())
check(#M.db("DB_InCamp"):Get(c.Gale.id) == 1, "Gale sent to camp")
check(M.counters.Hirelings_InCamp_Count == 0, "hireling taken from camp through the game's procedure")
check(#M.teleported > 0, "joiners brought to the player with a valid TeleportTo overload")

-- 4. Over the limit is refused and changes nothing.
reply = apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Laezel, ids.Karlach, ids.Hireling, ids.Gale } })
check(reply and not reply.accepted, "7 of 6 refused")

-- 5. Another player's peer is refused.
M.hostPeer = 131072
reply = apply({ uuids = {} })
check(reply and not reply.accepted and reply.message:find("host"), "non-host refused")
M.hostPeer = 65536

-- 6. Combat blocks changes.
c.Astarion.inCombat = true
reply = apply({ uuids = { ids.Shadowheart } })
check(reply and not reply.accepted and reply.message:find("combat"), "combat blocks")
c.Astarion.inCombat = false

-- 7. While the host controls a companion, that companion is locked and the
--    avatar is still the one recruiting.
M.controlled = c.Shadowheart
roster = Party.Roster()
for _, e in ipairs(roster) do
    if e.name == "Shadowheart" then check(e.locked, "controlled companion locked") end
end
check(Party.HostAvatar() == M.host.id, "host avatar found while controlling a companion")
M.controlled = nil

-- 8. Long rest: End the Day is held, picker asked, trim, then restore.
M.broadcasts = {}
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
local reasons = M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows
check(#reasons == 1 and reasons[1][1] == "PartyPicker_PartyLargerThanFour", "rest held with our reason")
M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason"):Delete(nil) -- the story removes it
M.fire("PROC_Camp_TryEnterNightModeFailed", 2, "after", M.host.id, "PartyPicker_PartyLargerThanFour")
check(#M.broadcasts == 1 and M.broadcasts[1].channel == "PickFour" and M.broadcasts[1].data.reason == "rest",
    "picker requested for rest")
check(Restrictions.GetPending() and not Restrictions.GetPending().trimmed, "pending, not yet trimmed")

reply = apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Karlach, ids.Laezel }, reason = "rest" })
check(reply and not reply.accepted, "5 for a rest of four refused")
reply = apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Karlach }, reason = "rest" })
check(reply and reply.accepted, "trim to four accepted")
check(Party.ActiveCount() == 4, "four active for the rest, got " .. Party.ActiveCount())
check(Restrictions.GetPending().trimmed, "pending trimmed")
check(M.counters.Hirelings_InCamp_Count == 1, "hireling sent to camp through the game's procedure")

M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 0, "rest not held at four")

-- A recruit joins during the night; the restore must not send them away.
Osi.PROC_GLO_PartyMembers_CheckAdd(c.Wyll.id, M.host.id)
M.fire("LongRestFinished", 0, "after")
M.runTimers()
check(#M.db("DB_Players"):Get(c.Wyll.id) == 1, "night-time recruit kept by the restore")
check(Party.ActiveCount() == 6, "restore filled up to the limit, got " .. Party.ActiveCount())
check(Restrictions.GetPending() == nil, "pending cleared after restore")

-- 9. Trim, put everyone back by hand, rest: no stale record survives.
M.fire("PROC_Camp_TryEnterNightModeFailed", 2, "after", M.host.id, "PartyPicker_PartyLargerThanFour")
apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Wyll }, reason = "rest" })
check(Restrictions.GetPending().trimmed, "trimmed again")
apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Wyll, ids.Laezel, ids.Karlach } })
check(Restrictions.GetPending() == nil, "a hand-picked party clears the trim record")
M.fire("LongRestFinished", 0, "after")
M.runTimers()
check(Party.ActiveCount() == 6, "nothing changed by a later rest")

-- 10. Restore when everyone is already back clears the record.
M.fire("PROC_Camp_TryEnterNightModeFailed", 2, "after", M.host.id, "PartyPicker_PartyLargerThanFour")
apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Wyll }, reason = "rest" })
Osi.PROC_GLO_PartyMembers_CheckAdd(c.Laezel.id, M.host.id)  -- the game itself brings them back
Osi.PROC_GLO_PartyMembers_CheckAdd(c.Karlach.id, M.host.id)
local ok, message = Restrictions.Restore()
check(ok and message:find("already back"), "restore with nothing to do succeeds")
check(Restrictions.GetPending() == nil, "and clears the record")

-- 11. "Keep everyone this time" skips exactly one hold and keeps an earlier trim.
reply = apply({ reason = "rest", keepAll = true })
check(reply and reply.accepted, "keep-all accepted")
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 0, "bypass skips one hold")
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 1, "next hold applies again")
M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason"):Delete(nil)

M.fire("PROC_Camp_TryEnterNightModeFailed", 2, "after", M.host.id, "PartyPicker_PartyLargerThanFour")
apply({ uuids = { ids.Shadowheart, ids.Astarion, ids.Wyll }, reason = "rest" })
M.fire("PROC_Camp_TryEnterNightModeFailed", 2, "after", M.host.id, "PartyPicker_PartyLargerThanFour")
apply({ reason = "rest", keepAll = true })
check(Restrictions.GetPending() and Restrictions.GetPending().trimmed, "keep-all does not lose an earlier trim")
Restrictions.Restore()
M.runTimers()
check(Party.ActiveCount() == 6, "earlier trim still restorable")

-- 12. A handler error still produces a reply.
local realRoster = Party.Roster
Party.Roster = function() error("boom") end
reply = apply({ uuids = { ids.Shadowheart } })
check(reply and reply.accepted == false and tostring(reply.message):find("boom"), "error reaches the client")
Party.Roster = realRoster

-- 13. Settings off: no hold, no raft change.
settings.prompt_long_rest = false
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 0, "setting off: no hold")
settings.extend_raft = false
check(Restrictions.ExtendRaft() == 0, "setting off: raft untouched")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error("tests failed") end
