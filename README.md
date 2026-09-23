# BG3 Scroll Repair

A one-off repair mod for **Baldur's Gate 3**. It fixes spell scrolls that were left broken in a
save after the mod **True Scrolls - 5e RAW** ([Nexus 13894](https://www.nexusmods.com/baldursgate3/mods/13894))
was uninstalled. Using one of those scrolls crashes the game to desktop.

This is not a replacement for True Scrolls, and it is not affiliated with it. It does one job and
then you remove it.

## The problem

True Scrolls implements its rules by pointing each covered scroll's use action at its own spell
variant, for example `Target_HoldMonster_TrueScrolls`. A scroll **item** records the spell it grants
at the moment the item is created, and that record is saved inside the item.

Remove the mod, and those spell definitions are gone, but the saved items still name them. Using such
a scroll makes the engine follow a reference to a spell that does not exist, and the game crashes.

What the player sees:

- Using an affected scroll from inventory or hotbar: hard crash to desktop, no error dialog.
- The scroll survives, because it was never consumed, and crashes again on the next attempt.
- The same spell cast from a spell slot works fine.
- Other scrolls, including newer scrolls of the same spell, work fine.

That mix makes the cause very hard to guess. In the save this mod was written for, 108 scrolls across
34 spells were affected, and it took three crashes over two weeks to trace.

## Is my save affected?

With the Script Extender console open in **server** context:

```lua
local n,b=0,0 for _,e in ipairs(Ext.Entity.GetAllEntitiesWithComponent("SpellBook")) do if e.Use and e.Use.ItemUseType=="Scroll" and e.SpellBook then n=n+1 for _,s in ipairs(e.SpellBook.Spells) do if string.find(tostring(s.Id.OriginatorPrototype),"TrueScrolls") then b=b+1 end end end end _P("scrolls seen", n, "still poisoned", b)
```

A second number of 0 means the save is clean and you do not need this mod.

## Try the mod's own repair first

If you still have True Scrolls, its author built a repair for exactly this and it costs nothing to try:

1. Re-activate True Scrolls and load the save.
2. In MCM, set **Static Spell Save DC** to **off**. That rewrites the scroll templates back to the
   vanilla spells and recreates mismatched scrolls.
3. Re-run the check above. If it reports 0, save, then remove True Scrolls. Done.

In the save this mod was written for that did not work: re-enabling the mod with the setting on
converted more scrolls (108 to 261 of 1,356 scrolls), and turning the setting off, even across a save
and a full restart, left 261. Hence this mod.

## What this mod does

For each scroll whose stored spell still names a `_TrueScrolls` variant, it deletes the item and
re-adds the same root template to the same holder with the same stack size. That is the same method
True Scrolls uses in its own `RecreateScrolls()`, but it runs with True Scrolls **inactive**, so the
templates in memory are vanilla and the rebuilt items are clean.

It only acts when you type a command. It changes nothing on its own.

### Safety

The repair script went through three adversarial code reviews before it was ever run on a save, and
the on-screen warning through a fourth. It:

- rebuilds a scroll only if the item, its holder and its root template all verifiably exist, the
  stack size is read rather than guessed, the recorded holder really is the item's direct inventory
  owner, the template matches what the game reports, and the item is verifiably not a story item;
- skips trader stock unless you ask for it (`traders`), because rebuilt items lose trade-stock and
  ownership marking;
- skips scrolls lying loose in the world;
- deletes and re-adds each item under its own error guard, and re-adds a group only after every item
  in it is confirmed gone;
- proves nothing was lost by summing actual stack quantities per holder and scroll type before and
  after. Any unreadable value, any change, any leftover affected scroll is reported as a PROBLEM.
  Only a completely clean result prints OK.

It cannot repair scrolls that are not loaded, which in practice means scrolls in other areas. The
on-screen warning (below) tells you when you walk into an area that still has some.

## Install and use

1. **Make a hard save you do not overwrite.**
2. **Deactivate True Scrolls.** The repair refuses to run while it is loaded.
3. Put `ScrollRepair.pak` in `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\` and activate
   **Scroll Repair (True Scrolls residue)** in BG3 Mod Manager.
4. Load your save. Open the SE console, type `server`, then:

   | Command | Effect |
   |---|---|
   | `!scrollrepair_scan` | lists affected scrolls in this area, changes nothing |
   | `!scrollrepair_fix dry` | shows exactly what the fix would do, changes nothing |
   | `!scrollrepair_fix` | rebuilds them, then verifies |
   | `!scrollrepair_fix dry traders` / `!scrollrepair_fix traders` | same, including trader stock |

5. Keep the game unpaused and do not save, load or change area until the `VERIFY:` lines appear.
6. Only if the last line reads **`VERIFY: OK`**, save to a new slot. If it says **PROBLEM**, do not
   save; reload your backup and open an issue with the `[ScrollRepair]` lines from the Script
   Extender log.
7. Repeat the scan once in each other area you visit. Then deactivate the mod in BG3MM and delete
   the pak.

### On-screen warning

About six seconds after each area loads, the mod counts affected scrolls there. If it finds any, a
small window appears with the count and the command to fix them. Each area warns once per session,
clean areas show nothing, and the check never changes an item.

## Side effects

Rebuilt scrolls lose their hotbar slots and any stolen or ownership marking. Trader stock, if you
include it, may no longer behave as generated stock on restock. Nothing else changed in testing.

## Result in the save it was built for

174 scrolls rebuilt, 0 delete or add failures, 1,356 scrolls seen before and after, every holder and
scroll-type quantity unchanged, and the 87 remaining were the trader stock deliberately skipped.

## Requirements

BG3 Script Extender v29 or newer, with the console enabled (`"CreateConsole": true` in
`ScriptExtenderSettings.json`). Built and tested against game version 4.1.1.7398727 and SE v32.

## Credits and licence

Repair method modelled on `RecreateScrolls()` in **True Scrolls - 5e RAW** by **jjdoorframe**. Thanks
for a good mod; this exists only to clean up after uninstalling it, and the author is welcome to take
any of it into True Scrolls itself.

MIT licence, see [LICENSE](LICENSE).
