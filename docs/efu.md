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
  and no more. Put new logic in another overlay (as the raid wipe is, in ov035's `EventFieldContinue_Callback`) or in
  script and data files, which aren't in the overlays.
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
| New game start and the lost-raid check on continue | `src/ov035/event_mapchange.c` |
| Script commands | `src/ov012/scrcmd_pokemon.c`, `EVCMD_TABLE` in `src/ov012/scrcmd_vm.c` from 0x2f3, and a row each in `EVCMD_PERM_TABLE` in `src/ov012/script_sys.c` (without one the command reads past the table and hangs) |

Edit the templates, then run `python3 tools/efu/gen_efu.py` and `python3 tools/efu/build_base.py`. Never edit
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
| `EVENT_WORK_0x41ad` (`EFU_WORK_SAVE_VERSION`) | The save format's version, set on a new game (now 1). |

Free event work values (no script, source file or event data refers to them): 0x410e, 0x410f, 0x4122, 0x413d, 0x4143,
0x4156 to 0x415f, 0x4163, 0x4169, 0x4177, 0x4180, 0x418b, 0x4193, 0x4197 to 0x419e, 0x41a0 to 0x41ab. Take the next
from the top of the list down, and move it into the table above.

## Raids and saving

- The east gate (`ZONE_NACRENE_GATE`) has two triggers. Column 14, by Route 3's door, is live while home
  (`EFU_WORK_RAID` 0): it asks to head out, refuses without a Pokémon that can fight, and on yes sets the raid and
  saves. Column 2, by Nacrene's door, is live while out (`EFU_WORK_RAID` 1): it clears the raid and saves.
- Continuing a save with the raid set (the game was switched off before coming back, or saved from the menu while
  out) empties the party, then `Script_RaidLost` says so, clears the raid, saves and sends the player home.

## Testing

DeSmuME's CLI under Xvfb with xdotool keys (x is A, z is B, s is X, Return is Start). There are no save states, so
each test plays from boot, and inputs are timing-sensitive: give every step its own key press and a pause. `--arm9gdb`
works for reading memory, but breakpoints don't fire under the JIT.
