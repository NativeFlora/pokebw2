# Escape from Unova

A White 2 hack built on this decomp: a post-apocalyptic Unova with Tarkov-style raids. This file is the hack's own
notes. The decomp's rules in the README and `CLAUDE.md` are about matching the original; the hack doesn't match, so it
builds with `python3 configure.py --modded w2_us && ninja` (only White 2, US).

## Build constraints

- **ARM9 main must keep its size.** Its first 0x4000 bytes are the DSi secure area, whose stored values can't be
  recomputed without the ARM7 BIOS, so any shift in main fails `dsd rom build` with "the ARM9 secure area has
  changed". Don't add code to `src/gfl`, `src/system` or anything else linked into main, and don't remove calls from
  overlays to main functions that only those calls keep alive (the linker drops the function and main shrinks). That
  is why `EventFieldFirst_Callback` still calls `SetActorFlag` with flag 0.
- **ov012 can barely grow.** Its end sets the arena start that main holds, so a few more bytes of code or data in
  ov012 also trips the secure area check. It had room for `Scrcmd_Efu_PokePartyRecoverHalf` and one row of each table,
  and no more. Put new logic in another overlay or in script and data files, which aren't in the overlays. The party
  wipe is script command 0x2db (`Scrcmd_Efu_PokePartyClear` in ov036), which took over `UnityTowerSetFloor`'s row
  (Unity Tower can't be reached) so the table didn't grow.
- **ov035 and ov036 grow at a risk.** Main points into ov036's later code and into the overlays after it (ov037 on
  start where ov036's code and BSS end), so growing either moves those pointers, and main's compressed size, kept in
  the secure area, may change with them. It is luck: some sizes pass and some don't, so build after every change to
  them and, if the check fails, change the size a little (natural code, never padding) and try again. ov035 has stayed
  at its v1 size (11520 bytes); ov036 is 354080 bytes now (the original's 352672). ov167 (battle) grew for fleeing and passed too.
- Only files marked complete in `config/w2_us/**/delinks.txt` are built from source; edit those.

## Where things are

| What | Where |
| --- | --- |
| Constants (script IDs, saved work values, save version) | `include/efu.h` |
| Scripts (global IDs 11000 to 11099) | `tools/efu/efu.s.in` → `res/field/scripts/efu.s` |
| Script text | `tools/efu/efu.txt.in` → `res/text/script/efu.txt` |
| Starter list (first stages that evolve, no legendaries, babies or pseudo-legendaries) | `tools/efu/starters.py` |
| Nacrene base: matrix, zone, doors, rubble, interiors, gate | `tools/efu/build_base.py` (reads the originals from `origin/main`) |
| Grim intro | `src/ov294/intro_script.c`, `res/text/system/game_start.txt`, `src/ov162/game_start.c` |
| New game start, the lost-raid check on continue, and the seasons (one per raid from winter, not the clock) | `src/ov035/event_mapchange.c` (`Efu_GetSeason`) |
| Blacking out: home, the team gone, a new Pokémon, a save | `src/ov012/event_battle_lose.c`, `FieldMapControl_LoadBlackoutZone` in `src/ov035/event_mapchange.c`, `Script_Blackout` |
| Options on a new game (fastest text, Set battle style, no battle animations) | `Config_Init` in `src/system/config.c` |
| The base's beach and sea (Undella's sand and surf textures) | `tools/efu/build_coast.py`, run by `build_base.py` |
| Route 3, the first raid zone: wild Pokémon at 10 to 20, the scavs at 40 to 60 and their lines | `tools/efu/build_raid.py` |
| The scavs' pursuit | `EventTrainerEye_EfuPursue` in `src/ov036/event_trainer_eye.c`, called each step from `src/ov036/fieldmap_event.c` |
| Script commands | `src/ov012/scrcmd_pokemon.c`, `EVCMD_TABLE` in `src/ov012/scrcmd_vm.c` from 0x2f3, and a row each in `EVCMD_PERM_TABLE` in `src/ov012/script_sys.c` (without one the command reads past the table and hangs) |

Edit the templates, then run `python3 tools/efu/gen_efu.py`, and from `tools/efu`, `python3 build_base.py` and
`python3 build_raid.py`. Never edit
`efu.s` or `efu.txt` by hand.

Script gotchas: `VMJumpIf CMP_STACK` jumps when the comparison is false, so use `WorkCmpConst` with
`VMJumpIf CMP_EQ`; movement data needs `.balign 4, 0` before its label; a background event's height (`z`, world
units) must be within 2 of the player's; a short tap of a direction only turns the player.

## Saves across builds

A save made on one build must load on the next. The rules:

1. **Never change the save's layout.** No new fields in saved structs, no size changes, no reordering. The save is
   the original game's.
2. **Keep the hack's state in event work values and flags the original never uses.** They are saved already, so a
   new one costs nothing in the layout. Once one is given a meaning, it keeps it forever: never move, reuse or
   repurpose one, even if the feature goes away.
3. **Bump `EFU_SAVE_VERSION` when a build changes what a saved value means**, and add an upgrade step on continue that
   rewrites older saves (`EFU_WORK_SAVE_VERSION` holds the version a save was made with; 0 means a save from before it
   existed).
4. **Script and zone IDs are fine to add, but a saved position must stay valid.** Don't delete or renumber zones,
   and keep the warps of the base map in their order (interiors refer to Nacrene's warps by number), so a save made
   anywhere in the base still lands somewhere real.

Taken so far:

| Value | Meaning |
| --- | --- |
| `EVENT_WORK_0x41ac` (`EFU_WORK_RAID`) | 1 while out on a raid. Set and saved on leaving through the east gate, cleared and saved on coming back. Continuing a save with it set loses the raid. |
| `EVENT_WORK_0x41ad` (`EFU_WORK_SAVE_VERSION`) | The save format's version, set on a new game and on heading out on a raid (now 3). |
| `EVENT_WORK_0x41ab` (`EFU_WORK_RAID_COUNT`) | Raids set out on, which picks the season (`EFU_SEASON`). Version 2; a version 1 save has 0, so winter. |
| `EVENT_WORK_0x41aa` (`EFU_WORK_EXPLORE_START`) | The play time in seconds (wrapping at 0x10000), plus 1, at the first step of this exploration; 0 until then. Version 3. |
| `EVENT_WORK_0x41a9` (`EFU_WORK_SCAVS_OUT`) | Scavs that have come out on this exploration. Version 3. |
| `EVENT_FLAG_0x0a80` to `0x0a8f` (`EFU_FLAG_SCAV_FIRST`) | Each scav NPC's hide flag, in the order `build_raid.py` gives them. All set on heading out. Version 3. |

Free event flags (nothing refers to them) include 0x0a90 to 0x0a9f; take them upward from there.

Free event work values (no script, source file or event data refers to them): 0x410e, 0x410f, 0x4122, 0x413d, 0x4143,
0x4156 to 0x415f, 0x4163, 0x4169, 0x4177, 0x4180, 0x418b, 0x4193, 0x4197 to 0x419e, 0x41a0 to 0x41a8. Take the next
from the top of the list down, and move it into the table above.

## Raids and saving

- The east gate (`ZONE_NACRENE_GATE`) has two triggers. Column 14, by Route 3's door, is live while home
  (`EFU_WORK_RAID` 0): it asks to head out, refuses without a Pokémon that can fight, and on yes sets the raid and
  saves. Column 2, by Nacrene's door, is live while out (`EFU_WORK_RAID` 1): it clears the raid and saves.
  Heading out also counts the raid (the season moves on) and gives the running shoes, for saves from version 1.
- Continuing a save with the raid set (the game was switched off before coming back, or saved from the menu while
  out) runs `Script_RaidLost`: it empties the party, says so, clears the raid, gives a new Pokémon, saves and sends
  the player home.
- Blacking out sends the player home (`FieldMapControl_LoadBlackoutZone`), and `Script_Blackout` fades in, clears the
  raid, empties the party, gives a new Pokémon and saves.
- The new Pokémon, on a new game and after every loss, is a random one from the starter list at level
  `EFU_LOST_SOUL_LEVEL` (5; `L_LostSoul`, generated by `gen_efu.py`), "as lost as you are".

## The scavs

Route 3's Trainers, made single battles, evolved to their levels, dressed as Team Plasma Grunts (the classes renamed
Scav) and given new lines by `build_raid.py`, start hidden: heading out sets their flags. Each step the player takes,
`EventTrainerEye_EfuPursue` runs before the original sight check:

- `EfuScav_Spawn` starts the exploration's clock on its first step, and once `EFU_SCAV_SPAWN_SECONDS` (10 minutes) of
  play time have passed, and again each time that much more has, brings out the hidden scav furthest from the player
  on the current map, with its defeat on an earlier exploration forgotten.
- A wandering scav that sees the player (nothing in the way on the straight line between them) within
  `EFU_SCAV_CATCH` tiles whichever way it faces, or up to `EFU_SCAV_SIGHT` (7) tiles away in the quarter it faces,
  shows a "!" and gives chase.
- A chasing scav takes one walking step (`ACMD_WALK_8F`, so it falls behind a running player) toward the tile the
  player stepped onto, the longer way first, the other if that's blocked, or to the side when the player is straight
  ahead and the way is blocked. It moves only when the player steps. Within `EFU_SCAV_CATCH` tiles it starts its
  battle, and after `EFU_SCAV_LOSE_STEPS` steps in a row out of sight it shows a "?" and goes back to wandering. The
  chase lives in the actor's user parameters 1 and 2, which the event data leaves 0.

## Fleeing

Running from a wild battle always works (`btl_server_flow.c`): when the original would fail ("Couldn't get away!",
or trapped), the escape count is set to `EFU_ESCAPE_PENDING`, the rest of the turn happens (the wild Pokémon attacks),
and `ActionOrder_Run` gets the player away at its end. If the player's Pokémon faints first, the next try always
works.

## Testing

DeSmuME's CLI under Xvfb with xdotool keys (x is A, z is B, s is X, Return is Start). There are no save states, so
each test plays from boot, and inputs are timing-sensitive: give every step its own key press and a pause. `--arm9gdb`
works for reading memory, but breakpoints don't fire under the JIT.
