# Party Picker: test run card (v0.1.0, first in-game test)

**Pak:** `PartyPicker.pak` (23,707 bytes)
SHA256 `4c003e3ed794c9f56e4d2c194c48f68dd33caf07b966ca008f10890020643269`

**Built with:** `python3 tools/lspk.py create src PartyPicker.pak`. Rebuilding Scroll Repair's
`src/` with the same tool gives a pak byte-identical to the Divine-built `ScrollRepair.pak`.

## Before you start
1. Make a **hard save** in a new slot, e.g. `BACKUP before Party Picker`.
2. Requirements:
   - BG3 Script Extender, with the console on (`"CreateConsole": true`).
   - **Mod Configuration Menu** installed and active. Party Picker lists it as a dependency.
3. Quit the game.

## Install
4. Put `PartyPicker.pak` in `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\`.
5. In BG3 Mod Manager: refresh, activate **Party Picker** with **Mod Configuration Menu** above it,
   then export/save the order.
6. Launch and load the backup.

## Quick checks
7. Open the Script Extender log (`...\Script Extender\Scripe Extender Logs\Extender Runtime *.log`;
   the folder name really is misspelled). Look for:
   - `[PartyPicker] server loaded.`
   - `[PartyPicker] client loaded (Party tab added to MCM).`
   - `[PartyPicker] party size limit set to 6`
8. Open the SE console, type `server`, then `!pp_roster`. Your companions should be listed, your
   character marked `locked(player character)`.
9. Open MCM. Party Picker should have a **Settings** tab and a **Party** tab.

## The tests that matter
Follow `docs/TESTING.md`, steps 3–12. Most important:
- **Step 3:** tick 6, Apply, and check that 6 portraits appear.
- **Step 7:** with 6 in the party, End the Day. The rest should **not** start; the picker window
  should open.
- **Steps 8–9:** pick four, rest, wake. The other two rejoin.

## If something goes wrong
- Do not save over your backup. Reload it.
- Send me every `[PartyPicker]` line from the log and say which step failed.
- To remove the mod: deactivate it in BG3MM, then delete the pak. It adds no items or spells, only
  its own settings and one saved variable.
