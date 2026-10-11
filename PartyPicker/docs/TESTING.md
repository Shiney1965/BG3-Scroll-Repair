# Testing

## Outside the game (done)

`python3 tests/run_tests.py` (needs `pip install lupa`):
- compiles every Lua file under Lua 5.4;
- runs the server logic against `tests/mock_game.lua`, a fake of the Osiris databases and story
  procedures as documented in `docs/RESEARCH.md`. The mock checks `TeleportTo`'s argument count,
  refuses two-argument `Remove` calls and avatar removals, and models the hireling camp counter.

The 56 checks cover:
- roster building and summon filtering;
- a companion the host is controlling;
- party changes from the MCM tab, including hirelings in camp;
- the limit check, the host-only check and the combat block;
- the long-rest hold, trim and restore;
- a recruit joining between trim and restore (kept);
- a hand-picked party replacing a pending trim;
- restore when everyone is already back;
- "keep everyone this time", including that it does not lose an earlier trim;
- an error inside a request handler still reaching the client;
- a dead party member never being sent to camp; dismissed avatars locked;
- restore when the limit was lowered, and when night mode ends after the rest;
- the one-time bypass expiring;
- adding raft landing spots on level start and again just before landing;
- the settings switches.

A mock is not the game. These tests catch Lua mistakes and logic errors. They cannot show that the
story procedures behave as documented in the current patch. The client UI is not covered.

## In the game

**2026-10-11, v0.1.1 (SHA-256 `3187775e...28ef`), MCM 1.40.1:** Alan reported "The mod seems to
work perfectly". v0.1.0 had first shown an MCM "Dependency issue detected" warning (it required MCM
1.41); fixed in v0.1.1. Which of the steps below were exercised is not yet recorded, so none is
marked passed individually.

Make a hard save first. All `[PartyPicker]` lines go to the Script Extender log
(`Extender Runtime *.log`).

| # | Step | Expect | Confirms |
|---|---|---|---|
| 1 | Load a save with 4+ recruited companions | Log: `party size limit set to 6`; MCM has a **Party** tab | `SetMaxPartySizeOverride` on `LevelGameplayStarted`; MCM tab |
| 2 | Server console `!pp_roster` | Everyone recruited, summons absent, your character locked | Roster DBs |
| 3 | Party tab: tick 6, Apply | The new members appear next to you; portraits show 6 | `PROC_GLO_PartyMembers_CheckAdd` above 4; 6-argument `TeleportTo` |
| 4 | Untick one, Apply | They go to camp and are there when you visit | `PROC_GLO_PartyMembers_Remove(…, 1)` |
| 5 | Hireling in camp: tick, Apply; then untick, Apply | Joins; then back in camp; talking to them in camp shows the normal options | Hireling procedures and flags |
| 6 | Switch to controlling a companion, open the Party tab | That companion is shown locked | Host-character handling |
| 7 | With 6 in party, End the Day | Rest does not start; the picker opens | **Highest risk:** the QRY `before` listener plus `PROC_Camp_TryEnterNightModeFailed`. If the rest starts anyway, the user-query listener did not fire as the SE source suggests |
| 8 | Pick 4, Keep, then End the Day again | Normal rest, four in beds | |
| 9 | Wake up | The other 2 rejoin a few seconds later (after the camp returns to day) | `LongRestFinished` / end of night mode + add-only restore |
| 10 | Trim to four, save before pressing End the Day, reload, rest, wake | Restore still happens | Mod variable persistence |
| 11 | Act 1 Underdark: Ebonlake raft with 6 in party, to Grymforge and back | All 6 arrive at each dock | Raft landing spots 5–16. Log: `raft: added … landing positions` (at a level load or just before landing) |
| 11b | Same, through the lake encounter (Duergar raft) | All 6 stay on the raft and continue | **Risk:** on the lake, members 5+ share the four on-raft spots; if the game pushes someone off the raft they may be left behind |
| 12 | Multiplayer (host + 1) | Other player's tab is read-only; their characters stay locked | Peer id → user id conversion |

If step 7 fails, there is a fallback. Turn off "Ask before a long rest", trim with the Party tab
before resting, and tick everyone again afterwards.
