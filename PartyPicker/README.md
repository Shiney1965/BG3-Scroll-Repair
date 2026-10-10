# Party Picker (BG3)

A Baldur's Gate 3 mod that lets you choose who is in your party from a menu. **Status: first
draft, not yet run in game.**

- **Party tab in Mod Configuration Menu (MCM).** Everyone you have recruited is listed with a
  checkbox. Tick who you want with you and press **Apply**. There are no hotbar spells and no
  talking to companions to invite or dismiss them.
- **Larger parties.** A slider sets the party limit from 4 to 16.
- **The two places the game handles only four:**
  - **Long rest.** The camp has four beds, and the game puts only four party members to bed. If
    your party is larger, End the Day is held and a window asks which four to keep tonight. The
    others wait in camp and rejoin when you wake up. Nobody is sent away to make room for them.
  - **The Grymforge raft (Underdark).** The raft already takes everyone aboard but has only four
    landing spots, so members five and up are left at the old dock. Party Picker adds landing
    spots so the whole party arrives. No choice is needed.

## Requirements

- BG3 Script Extender v29 or newer (developed against v32).
- Mod Configuration Menu 1.41 or newer.

## How it works

Party Picker uses the same story procedures the game's own dialogue and dismiss button use, so the
game's bookkeeping stays correct:

| Task | Story procedure |
|---|---|
| Join | `PROC_GLO_PartyMembers_CheckAdd` (companions), `PROC_Hirelings_TakeFromCamp` (hirelings) |
| Go to camp | `PROC_GLO_PartyMembers_Remove(member, your avatar, 1)`; hirelings also `PROC_Hirelings_SendToCamp` |
| Party limit | `SetMaxPartySizeOverride`, re-applied on each level load |

The two four-member situations are handled with Script Extender listeners and story databases.
No game file is replaced and the executable is not patched:

- **Long rest:** Party Picker adds a story reason to the camp's existing "not ready for night"
  check. This is the mechanism the game itself uses to block resting in some story moments.
- **Raft:** Party Picker adds rows 5–16 to the raft's landing-position table. They reuse the
  existing positions at each dock.

Details and sources are in [docs/RESEARCH.md](docs/RESEARCH.md).

## Layout

```
src/Mods/PartyPicker/
  meta.lsx                       mod info; depends on MCM
  MCM_blueprint.json             Settings tab
  ScriptExtender/Config.json
  ScriptExtender/Lua/
    BootstrapServer.lua          network handlers, console commands
    BootstrapClient.lua          MCM Party tab, picker window, !pp fallback
    Shared/Common.lua            channels, helpers
    Server/Party.lua             roster, apply changes
    Server/Restrictions.lua      long-rest hold/restore, raft landing spots
    Client/PartyTab.lua          the Party tab
    Client/PickFour.lua          the pick-four window
    Client/RosterList.lua        checkbox list used by both
tests/                           mock game + scenarios (python3 tests/run_tests.py)
docs/                            research notes and the in-game test plan
```

## Console commands (testing)

- **Server context:** `!pp_roster`, `!pp_set Shadowheart,Astarion,Gale`, `!pp_restore`, `!pp_size`
- **Client context:** `!pp` opens the Party list without MCM.

## Building the .pak

```
pip install lz4
python3 tools/lspk.py create src PartyPicker.pak
python3 tools/lspk.py list PartyPicker.pak      # inspect
```

`tools/lspk.py` writes LSPK version 18, the format LSLib's Divine writes for BG3 (layout taken
from LSLib's `PackageFormat.cs` and `PackageWriter.cs`). It was checked by rebuilding Scroll
Repair's `src/`: the result is byte-identical to the Divine-built `ScrollRepair.pak`. Divine or
BG3 Modder's Multitool can still be used instead. See [RUN_CARD.md](RUN_CARD.md) to install and test.

## Known limits of this draft

- Not yet tested in game. See [docs/TESTING.md](docs/TESTING.md) for the steps and which hooks are
  most at risk.
- Multiplayer: only the host can change the party. Player characters and anyone another player
  controls are never moved.
- The list is everyone the story counts as recruited (`DB_PartOfTheTeam`). A companion the story
  is keeping in camp for a scene can still be ticked, because the add procedure does not repeat the
  checks the recruitment dialogues make. Whether that causes trouble is untested.
- On the raft's lake stop, members 5+ share the four standing spots on the raft. This is untested.
- Turning the raft setting off does not remove landing spots that were already added. They are
  only used when more than four people ride the raft.
- Dialogue still seats the speaker plus three. That is not changed.
- Quest items carried by member 5+ are sometimes not registered, per Party Limit Begone's notes.
  That is not addressed.

## Licence

MIT.
