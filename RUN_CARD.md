# Scroll Repair — run card

**v1.4 installed 2026-09-16** over v1.3 (same file name, game was closed).
Pak installed: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ScrollRepair.pak`
SHA256 `57707e27d9053c807d713ac0c9d83dc6ff0a80a98477062e8245cbd6c7bfc407` (9,040 B)

**New in v1.4 (read-only):** about 6 seconds after each area load the mod counts
affected scrolls in that area. If any are found, an on-screen window says how many
and which command repairs them, with a Close button. Clean areas show nothing.
No manual `!scrollrepair_scan` needed when travelling. Nothing is ever changed
without you running `!scrollrepair_fix` yourself. Three adversarial reviews on the
repair, one more on the warning feature (SHIP WITH NOTES, notes applied).

Superseded builds kept in this folder: v1.0 `ScrollRepair.pak`, v1.1, v1.2,
v1.3 `9eb2cb64…`.

## v1.3 details below (steps unchanged)
Source: `C:\Claude Projects\BG3 Mods\ScrollRepair\src\`
Reviews: three adversarial passes; final verdict SHIP WITH NOTES; all notes applied in v1.3.

## Before you start
1. In game, make a **hard save** in a new slot named something like `BACKUP before scroll repair`. Do not overwrite it until step 7 says OK.
2. Quit the game.

## Load order
3. In BG3MM: **deactivate True Scrolls**, **activate "Scroll Repair (True Scrolls residue)"**, export/save the order, launch.
   The repair refuses to run if True Scrolls is still active.

## Dry run (changes nothing)
4. Load the backup save. Wait until you have control. Open the SE console, type `server`, then:
   `!scrollrepair_scan`
   Expect `scrolls seen ~1356, affected ~261`.
5. `!scrollrepair_fix dry`
   Read the summary line: `DRY RUN: scrolls seen N, affected N, to rebuild N, skipped N`.
   - If **to rebuild is 0** and every row says the same SKIP reason, stop and post the output; one of the game queries is not returning what the script expects.
   - Otherwise note the SKIP reasons (story items, loose in the world, trader stock, holder mismatch). Skipped scrolls are left untouched.

## Fix
6. Keep the game **unpaused**, do not save, load, or move to another area. Run:
   `!scrollrepair_fix`
   Wait for the lines starting `VERIFY:` (a few seconds).
7. The last line must read **`VERIFY: OK - ... Safe to save.`**
   - If it says **PROBLEM**, do not save. Copy every `[ScrollRepair]` line and post them. Reload the backup.

## After OK
8. Hover one rebuilt scroll you care about (a Hold Monster scroll, for example) and check the tooltip looks normal.
9. Run `!scrollrepair_scan` again. Rebuilt rows are gone; only skipped rows may remain.
10. Save to a **new** slot. Quit.
11. Trader stock (optional): if skipped rows were trader stock, load the new save and run `!scrollrepair_fix dry traders`, then `!scrollrepair_fix traders`, same OK rule. Or simply never buy those scrolls.
12. Other areas: the scan only sees what is loaded. After travelling to another act/area, run `!scrollrepair_scan` there once.
13. When you are done everywhere: in BG3MM deactivate Scroll Repair, **then** you may delete the pak. Leave True Scrolls deactivated.

Side effects to expect: rebuilt scrolls lose hotbar slots and any stolen/owner marking. Nothing else.
