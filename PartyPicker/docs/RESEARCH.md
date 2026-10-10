# Research notes (2026-10-10)

Gathered for the Party Picker design. **How the sources were checked:** this research ran in a cloud
session whose network policy only allowed GitHub. Nexus Mods, mod.io, Steam, Reddit, X, Hacker News
and bg3.wiki could not be opened. Facts from those sites below come from search-engine summaries and
are marked *(search snippet)*. Anything only on a fan wiki is marked **fan wiki only**. Everything
else was read directly on GitHub.

The mod in your own Mods folder was not available to this session, so it is not reviewed here
specifically.

## 1. Existing party-size mods

| Mod | Nexus | How it works | Hotbar/invite steps |
|---|---|---|---|
| Party Limit Begone (Sildur) | [327](https://www.nexusmods.com/baldursgate3/mods/327) | SE build, plus an exe-patcher for Legacy and multiplayer *(search snippet)* | No, but the Legacy and multiplayer builds patch the executable |
| Aether's No Party Limits | [3479](https://www.nexusmods.com/baldursgate3/mods/3479) | SE; limit 16 *(search snippet)* | No |
| Configurable Party Limit (Volitio) | [11172](https://www.nexusmods.com/baldursgate3/mods/11172) | MCM slider plus a "dismiss all" button *(search snippet)* | No |
| PixellBytes' Adjustable Party Limit | [11939](https://www.nexusmods.com/baldursgate3/mods/11939) | No SE: a passive, set/apply spells, trim and restore spells; blocks the raft and long rest above 4 *(search snippet)* | **Yes** |
| Yet Another Party (Saigofu) | [24894](https://www.nexusmods.com/baldursgate3/mods/24894) | MCM limit; trims for rest and raft, later added raft seats *(search snippet)* | No |
| Extended Boat Crew to 32 | [25546](https://www.nexusmods.com/baldursgate3/mods/25546) | Patches the Ebonlake raft *(search snippet)* | No |
| Brawl (tinybike) | [12614](https://www.nexusmods.com/baldursgate3/mods/12614) | Has an MCM "Max Party Size" slider. Source: [GitHub](https://github.com/tinybike/Brawl) | No |

**No existing mod found uses MCM to choose individual party members.**
- Closest: Configurable Party Limit, Yet Another Party and Brawl set only the limit.
- Creative Mode ([22440](https://www.nexusmods.com/baldursgate3/mods/22440)) recruits from an MCM tab.
- Companion Reserve ([24943](https://www.nexusmods.com/baldursgate3/mods/24943)) manages Custom Companions hirelings *(search snippet)*.

## 2. The two places the game handles only four

Both are in Larian's story scripts. The copies read were third-party extractions on GitHub, not
Larian's own files, so the game patch they match is unknown.

1. **Long rest.** `PROC_Camp_PlacePlayersInBed` queries four players and puts them in beds 4/2/1/3.
   Source: `GLO_Camp.txt` L1729–1750 in
   [Interzoneism/qdnd](https://github.com/Interzoneism/qdnd/blob/b4f963a57b3a0265beac871fbf23dbd09e13cf65/BG3_Data/Shared/Mods/Shared/Story/RawFiles/Goals/GLO_Camp.txt#L1729-L1750).
   - The same file has a supported way for story to refuse End the Day:
     `QRY_Camp_CheckPlayersReadyForNightModeStoryReasons` adds a row to
     `DB_Camp_PlayerNotReadyForNightMode_CustomStoryReason`, after which
     `PROC_Camp_TryEnterNightModeFailed(player, reason)` runs (L3812–3835, L620–648).
   - `_Greevers_Little_Helpers.txt` L3603–3609 uses it to block resting during "REALLY_BlockFastTravel".
2. **Ebonlake raft to Grymforge (Act 1).**
   - `PROC_UND_EbonLake_Raft_ComposeCrew` puts every `DB_Players` member of the party group in the
     crew.
   - `PROC_UND_EbonLake_Raft_Disembark` lands crew members one per index from
     `DB_UND_EbonLake_Raft_Locations_PlayerPositions`. That table only has indexes 1–4 per dock, so
     members 5+ are never teleported.
   - At the cave and camp docks all four indexes use the same trigger. On the lake, each index has
     its own trigger.
   - The ready check (`QRY_UND_EbonLake_GetPlayerInRaftTrigger`) collects only characters of
     *different users* ("we need unique user characters"). In single player the dialog starts
     without a ready check, so the crossing cannot be held there. Adding positions is the fix.
   - Source: `Act1_UND_EbonLake.txt` (L22–36, L210–330, L400–600), as copied inside
     [Yoonmoonsik/CombatLottery](https://github.com/Yoonmoonsik/CombatLottery/blob/ef9213d8d14d664ce9d57019c6dd5aee1955bc3f/Mods/CombatLottery88_87ac7b92-b36f-c190-f587-cbfb40feb304/Story/RawFiles/Goals/Act1_UND_EbonLake.txt).
     That copy sits inside another mod and may have been edited.

Other limits found, which this mod does not handle:
- A multiplayer join force-dismisses a companion (`ForceDismissCompanion`).
- Dialogues seat the speaker plus three.
- The Seeming spell targets four (**fan wiki only**).
- Party Limit Begone's page reports that quest items carried by member 5+ are sometimes not registered *(search snippet)*.

## 3. Engine and story calls used

Signatures are from [LaughingLeader's generated Osi.lua](https://github.com/LaughingLeader/BG3ModdingTools/blob/master/generated/Osi.lua).

**Party size**
- `Osi.SetMaxPartySizeOverride(n)` and `Osi.GetMaxPartySize()` are built-in.
- Brawl re-applies the size on every level start with `SetMaxPartySizeOverride(n)` followed by
  `PROC_CheckPartyFull()` ([State.lua](https://github.com/tinybike/Brawl/blob/master/Brawl/Mods/Brawl/ScriptExtender/Lua/Server/State.lua)).

**Recruit**
- Origins: `PROC_GLO_PartyMembers_CheckAdd(origin, player)`. It only adds while the global flag
  `GEN_MaxPlayerCountReached` is clear, and that flag is recomputed by `PROC_CheckPartyFull`
  ([_GLO_Shared_PartyMembers.txt L103–153, L476–530](https://github.com/Interzoneism/qdnd/blob/b4f963a57b3a0265beac871fbf23dbd09e13cf65/BG3_Data/Shared/Mods/Shared/Story/RawFiles/Goals/_GLO_Shared_PartyMembers.txt)).
- Hirelings: the game brings a hireling back from camp with `PROC_Hirelings_TakeFromCamp(hireling, avatar)`.
  That calls `PROC_Hirelings_AddToParty` and lowers `Hirelings_InCamp_Count`.
- Hirelings to camp: the game calls `PROC_GLO_PartyMembers_Remove(hireling, avatar, 0)`, then
  `PROC_Hirelings_SendToCamp(hireling)`, which sets `Hireling_State_InCamp` and raises the count
  (SharedDev `Hirelings.txt` L447–458, L670–682, L1095–1096).
- Usage in other mods:
  - CheckAdd followed by `TeleportTo` and `AttachToPartyGroup`:
    [Focus Lodestones as patched by DIQ](https://github.com/Difficulty-Immersion-Quality/DIQ-Misc-Patches/blob/main/DIQ%20Misc%20Patches%20-%20Overrides/Mods/FocusLodestones/ScriptExtender/Lua/Shared/RecruitmentManager.lua).
  - `PROC_Hirelings_AddToParty`:
    [ImWayden](https://github.com/ImWayden/RemoveMultiplayerCharacter/blob/main/Mods/RemoveMultiplayerCharacter/ScriptExtender/Lua/Server/RemoveMultiplayerCharacter.lua).

**Send to camp**
- `PROC_GLO_PartyMembers_Remove(member, dismisser, 1)`. For anyone still in `DB_PartOfTheTeam`,
  this ends in `PROC_DismissToCamp`.
- The two-argument overload with `0` calls `DebugBreak`, so it is always called forced.

**Read the party**
- `DB_Players` is the active, controllable party.
- `DB_PartOfTheTeam` is everyone recruited.
- `DB_Avatars`, `DB_InCamp`, `DB_Hirelings_Hired`.
- `DB_PartyMembers` also includes summons and followers, so it is not used.

**Host character**
- `GetHostCharacter` returns the character the host *controls*. That can be a companion: the game's
  own `_GLO_Shared_Origins.txt` tests `GetHostCharacter(_Avatar) AND NOT DB_Avatars(_Avatar)`.
- Party Picker therefore recruits and dismisses "by" the host's avatar, found through `DB_Avatars`
  plus `GetReservedUserID`, and never moves the controlled character.

**Guards**
- Focus Lodestones refuses moves when the character is in `DB_InDangerZone`, any
  `DB_FastTravelBlock_*_StatusSet` (BlockedZone, CantMove, Arrested, CampNightMode,
  FugitiveInPrison), combat, or is incapacitated.
- Party Picker copies the DB and combat checks. It does not copy the incapacitated check.

## 4. Script Extender and MCM

**Script Extender**
- Latest release is v32 (2026-06-21) ([releases](https://github.com/Norbyte/bg3se/releases)).
- Every API below is documented in [Docs/API.md](https://github.com/Norbyte/bg3se/blob/main/Docs/API.md):
  - `Ext.Net.CreateChannel` with `SetHandler`, `SetRequestHandler`, `RequestToServer` and `Broadcast`.
  - `Ext.Osiris.RegisterListener`, which can capture events, user PROCs and user QRYs.
  - `Ext.Timer.WaitFor`.
  - `Ext.Vars.RegisterModVariable`. PersistentVars are documented as deprecated.
- The same API.md says NetChannel handlers receive a *peer* id, while Osiris uses a user id,
  typically `(peer & 0xffff0000) | 1`.

**MCM**
- Version 1.41.0 per its meta.lsx; UUID `755a8a72-407f-4f0d-9a33-274ac0f0b53d`
  ([BG3-MCM](https://github.com/AtilioA/BG3-MCM)).
- The blueprint schema is in `.vscode/schema.json`.
- `MCM.InsertModMenuTab` takes `{ tabName, tabCallback, modUUID?, skipDisclaimer? }` as named
  arguments (`MCMAPIImplementations.lua`). The wiki's positional example is out of date.
- `Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]` and `["MCM_Mod_Tab_Activated"]` both carry `modUUID`.

## 5. Reverse engineering with AI (late September to October 2026)

**Candidate tools**
- **[rehan-remade/universal-modder](https://github.com/rehan-remade/universal-modder)** is the most
  likely match for "the GitHub tool for reverse engineering game binaries with AI".
  - It is Claude Code skills plus tools for modding PC games: recon, Ghidra, IDA MCP, Cheat Engine,
    Frida and more.
  - First commit 2026-09-29. About 6.1k stars on 2026-10-10.
  - A star-spike tracker recorded "+4.7k ⭐" in 7 days on 2026-10-07
    ([issue](https://github.com/hedongli1/reverse-radar/issues/24)).
  - It contains six BG3 field notes dated 2026-10-04/05. None is about party size.
- **[morluto/rea](https://github.com/morluto/rea)** ("Reverse engineer anything with agents") got
  far more attention but is not modding-specific.
  - About 51.5k stars on 2026-10-10.
  - #1 on GitHub Trending on 2026-10-08 per a tracker
    ([issue](https://github.com/onysakura/news-daily/issues/7781)).
  - It wraps Ghidra, IDA and Hopper through MCP. Windows PE support in Ghidra is still described as
    experimental.
- The [official Hex-Rays IDA MCP](https://github.com/HexRaysSA/ida-mcp) also shipped around then.

**Relevance to this mod: probably none needed.**
- The party cap is an engine value that story scripts can already override through
  `SetMaxPartySizeOverride`.
- Both four-member limits live in story scripts, which can be handled with listeners.
- No binary patching is planned.
- Party Limit Begone's multiplayer build patches the executable *(search snippet)*. That is the
  approach this mod avoids.
