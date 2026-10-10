# Party Picker (BG3)

A Baldur's Gate 3 mod that lets you choose who is in your party from a menu. **Status: first
draft, not yet run in game.**

- **Party tab in Mod Configuration Menu (MCM).** Everyone you have recruited is listed with a
  checkbox. Tick who you want with you and press **Apply**. There are no hotbar spells and no
  talking to companions to invite or dismiss them.
- **Larger parties.** A slider sets the party limit from 4 to 16.
- **Asks when the game needs four.** The game's own scripts handle only four party members in two
  places:
  - **Long rest:** the camp has four beds.
  - **The Grymforge raft** in the Underdark: it has four seats.
  
  If your party is larger, Party Picker holds the rest or the crossing and opens a window asking
  which four to keep. The others wait in camp and rejoin afterwards.

## Requirements

- BG3 Script Extender v29 or newer (developed against v32).
- Mod Configuration Menu 1.41 or newer.

## How it works

Party Picker uses the same story procedures the game's own dialogue and dismiss button use, so the
game's bookkeeping stays correct:

| Task | Story procedure |
|---|---|
| Join | `PROC_GLO_PartyMembers_CheckAdd` (origins), `PROC_Hirelings_AddToParty` (hirelings) |
| Go to camp | `PROC_GLO_PartyMembers_Remove(member, you, 1)` |
| Party limit | `SetMaxPartySizeOverride`, re-applied on each level load |

The two four-member situations are hooked with Script Extender listeners. No game file is replaced
and the executable is not patched:

- **Long rest:** Party Picker adds a story reason to the camp's existing "not ready for night"
  check, which is the same mechanism the game uses to block resting in some story moments.
- **Raft:** Party Picker fails the raft's ready check the same way the script does for Glut's owner.

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
    Server/Restrictions.lua      long rest and raft hooks
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

Pack `src/` with LSLib's Divine (`create-package`; give it absolute paths) or with BG3 Modder's
Multitool. This is the same way Scroll Repair was packed. No `.pak` has been built yet.

## Known limits of this draft

- Not yet tested in game. See [docs/TESTING.md](docs/TESTING.md) for the steps and which hooks are
  most at risk.
- Multiplayer: only the host can change the party, and other players' characters are never moved.
- Dialogue still seats the speaker plus three. That is not changed.
- Quest items carried by member 5+ are sometimes not registered, per Party Limit Begone's notes.
  That is not addressed.

## Licence

MIT.
