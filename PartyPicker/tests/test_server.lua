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

-- The party: Tav (avatar) + 5 companions + 1 hireling, 4 active.
local U = function(n) return string.format("00000000-0000-0000-0000-%012d", n) end
M.host = M.addChar("Tav", U(1))
local names = { "Shadowheart", "Astarion", "Gale", "Laezel", "Karlach" }
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
for _, ch in ipairs({ c.Laezel, c.Karlach, c.Hireling }) do M.db("DB_InCamp")(ch.id) end

dofile(LUA_ROOT .. "/BootstrapServer.lua")
local Party = Ext.Require("Server/Party.lua")
local Restrictions = Ext.Require("Server/Restrictions.lua")

-- 1. Level start applies the limit.
M.fire("LevelGameplayStarted", 2, "after", "WLD_Main_A", 0)
check(M.maxOverride == 6, "limit applied on level start")

-- 2. Roster: 7 characters, summon left out, avatar locked.
local roster = Party.Roster()
check(#roster == 7, "roster has 7 entries, got " .. #roster)
check(roster[1].name == "Tav" and roster[1].locked, "avatar first and locked")
local ids = {}
for _, e in ipairs(roster) do ids[e.name] = e.uuid; check(e.name ~= "Wolf", "summon excluded") end
check(Party.ActiveCount() == 4, "4 active (summon not counted)")

-- 3. Apply a party of six through the network handler, as the MCM tab does.
local reply
M.Ext.Require("Shared/Common.lua")
PP.Net.Apply:RequestToServer({ uuids = { ids.Shadowheart, ids.Astarion, ids.Laezel, ids.Karlach, ids.Hireling } },
    function(r) reply = r end)
check(reply and reply.accepted, "apply accepted: " .. tostring(reply and reply.message))
M.runTimers()
check(M.activeNames() == "Astarion,Hireling,Karlach,Laezel,Shadowheart,Tav,Wolf",
    "six active after apply, got " .. M.activeNames())
check(#M.db("DB_InCamp"):Get(c.Gale.id) == 1, "Gale sent to camp")

-- 4. Over the limit is refused and changes nothing.
PP.Net.Apply:RequestToServer({ uuids = { ids.Shadowheart, ids.Astarion, ids.Laezel, ids.Karlach, ids.Hireling, ids.Gale } },
    function(r) reply = r end)
check(reply and not reply.accepted, "7 of 6 refused")

-- 5. Another player's peer is refused.
M.hostPeer = 131072
PP.Net.Apply:RequestToServer({ uuids = {} }, function(r) reply = r end)
check(reply and not reply.accepted and reply.message:find("host"), "non-host refused")
M.hostPeer = 65536

-- 6. Combat blocks changes.
c.Astarion.inCombat = true
PP.Net.Apply:RequestToServer({ uuids = { ids.Shadowheart } }, function(r) reply = r end)
check(reply and not reply.accepted and reply.message:find("combat"), "combat blocks")
c.Astarion.inCombat = false

-- 7. Long rest: End the Day is held, picker asked, trim, then restore.
M.broadcasts = {}
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
local reasons = M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows
check(#reasons == 1 and reasons[1][1] == "PartyPicker_PartyLargerThanFour", "rest held with our reason")
M.fire("PROC_Camp_TryEnterNightModeFailed", 2, "after", M.host.id, "PartyPicker_PartyLargerThanFour")
check(#M.broadcasts == 1 and M.broadcasts[1].channel == "PickFour" and M.broadcasts[1].data.reason == "rest",
    "picker requested for rest")
check(Restrictions.GetPending() and Restrictions.GetPending().stage == "asking", "pending asking")

PP.Net.Apply:RequestToServer({ uuids = { ids.Shadowheart, ids.Astarion, ids.Karlach, ids.Laezel }, reason = "rest" },
    function(r) reply = r end)
check(reply and not reply.accepted, "5 for a rest of four refused")
PP.Net.Apply:RequestToServer({ uuids = { ids.Shadowheart, ids.Astarion, ids.Karlach }, reason = "rest" },
    function(r) reply = r end)
check(reply and reply.accepted, "trim to four accepted")
M.runTimers()
check(Party.ActiveCount() == 4, "four active for the rest, got " .. Party.ActiveCount())
check(Restrictions.GetPending().stage == "trimmed", "pending trimmed")

-- With four, End the Day is no longer held.
M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason"):Delete(nil)
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 0, "rest not held at four")

M.fire("LongRestFinished", 0, "after")
M.runTimers()
check(M.activeNames() == "Astarion,Hireling,Karlach,Laezel,Shadowheart,Tav,Wolf",
    "full party back after rest, got " .. M.activeNames())
check(Restrictions.GetPending() == nil, "pending cleared after restore")

-- 8. "Keep everyone this time" skips exactly one hold.
PP.Net.Apply:RequestToServer({ reason = "rest", keepAll = true }, function(r) reply = r end)
check(reply and reply.accepted, "keep-all accepted")
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 0, "bypass skips one hold")
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 1, "next hold applies again")
M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason"):Delete(nil)

-- 9. Raft: ready check blocked, released on failure, picker, restore on landing.
M.broadcasts = {}
M.fire("PROC_UND_EbonLake_ReadyCheckSpecific", 4, "before", M.host.id, c.Shadowheart.id, c.Astarion.id, c.Karlach.id)
check(M.readyCheckBlocked[M.host.uuid] == 1, "raft ready check blocked")
M.fire("ReadyCheckFailed", 1, "after", "ReadyCheck_EbonLake")
check(M.readyCheckBlocked[M.host.uuid] == 0, "raft block released")
check(#M.broadcasts == 1 and M.broadcasts[1].data.reason == "raft", "picker requested for raft")
PP.Net.Apply:RequestToServer({ uuids = { ids.Shadowheart, ids.Astarion, ids.Karlach }, reason = "raft" },
    function(r) reply = r end)
M.runTimers()
check(Party.ActiveCount() == 4, "four on the raft")
M.fire("FlagSet", 3, "after", "UND_EbonLake_State_RaftAtLake_8ff8fe26-4546-40e0-94a5-03dba9001650", "", 0)
M.runTimers()
check(Party.ActiveCount() == 4, "no restore mid-lake")
M.fire("FlagSet", 3, "after", "UND_EbonLake_State_RaftAtCave_beb83efd-711a-4e20-8d87-470050aebee8", "", 0)
M.runTimers()
check(Party.ActiveCount() == 6, "full party back at the cave, got " .. Party.ActiveCount())
check(#M.teleported > 0, "returning members brought to the player")

-- 10. Settings off: no hold.
settings.prompt_long_rest = false
M.fire("QRY_Camp_CheckPlayersReadyForNightModeStoryReasons", 0, "before")
check(#M.db("DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason").rows == 0, "setting off: no hold")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error("tests failed") end
