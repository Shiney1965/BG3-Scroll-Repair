# Testing

## Outside the game (done)

`python3 tests/run_tests.py` (needs `pip install lupa`):
- compiles every Lua file under Lua 5.4;
- runs the server logic against `tests/mock_game.lua`, a fake of the Osiris databases and story
  procedures as documented in `docs/RESEARCH.md`.

The scenarios cover:
- roster building;
- party changes from the MCM tab;
- the limit check, the host-only check and the combat block;
- the long-rest hold, trim and restore;
- "keep everyone this time";
- the raft hold, trim and restore on landing;
- the settings switches.

A mock is not the game. These tests catch Lua mistakes and logic errors. They cannot show that the
story procedures behave as documented in the current patch.

## In the game (not done yet)

Make a hard save first. With Script Extender's console enabled, all `[PartyPicker]` lines go to the
SE log (`Extender Runtime *.log`).

| # | Step | Expect | Confirms |
|---|---|---|---|
| 1 | Load a save with 4+ recruited companions | Log: `party size limit set to 6`; MCM shows a **Party** tab | `SetMaxPartySizeOverride` on `LevelGameplayStarted`; MCM tab insertion |
| 2 | Server console `!pp_roster` | Everyone recruited, summons absent, your character locked | Roster DBs |
| 3 | Party tab: tick 6, Apply | Two companions walk/teleport in; party portraits show 6 | `PROC_GLO_PartyMembers_CheckAdd` above 4 |
| 4 | Untick one, Apply | They go to camp; they are at camp when you visit | `PROC_GLO_PartyMembers_Remove(…, 1)` |
| 5 | Hirelings: tick one in camp, Apply | They join | `PROC_Hirelings_AddToParty` |
| 6 | With 6 in party, End the Day | Rest does not start; the picker opens | QRY `before` listener + `PROC_Camp_TryEnterNightModeFailed`. **Highest risk:** if the rest starts anyway, the user-QRY listener did not fire as expected |
| 7 | Pick 4, Keep, then End the Day again | Normal rest with 4 in beds | |
| 8 | Wake up | The other 2 rejoin a couple of seconds later | `LongRestFinished` + restore |
| 9 | Act 1 Underdark: use the Ebonlake raft with 6 | The crossing does not start; the picker opens | `SetReadyCheckBlocked` making the ready check fail. **Second risk:** in single player, check that the ready check is not skipped |
| 10 | Pick 4, use the raft again, land | The other 2 rejoin at the dock | `FlagSet` on `UND_EbonLake_State_RaftAtCave/Camp` |
| 11 | Save between steps 7 and 8, reload | Restore still happens after the rest | Mod variable persistence |
| 12 | Multiplayer (host + 1) | Other player's tab is read-only; their characters stay locked | Peer id → user id conversion |

If step 6 or 9 fails, the fallback is still usable. Disable the matching "Ask before..." setting,
trim with the Party tab before resting or crossing, and use **Restore full party** afterwards.
