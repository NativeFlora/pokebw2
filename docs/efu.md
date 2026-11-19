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
  at its v1 size (11520 bytes); ov036 is 355744 bytes now (the original's 352672). ov167 (battle) grew for fleeing and passed too, and
  ov162 (the title menu) is 19680 bytes (the original's 19648) after one failed try at the same size with other code.
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
| An exploration's own hour of the day and its downfall | `Efu_GetDaySeconds` in `src/ov036/fieldmap.c` (with `src/ov036/field_encount.c`), `GetDefaultWeatherValue` in `src/ov012/field_encount_st.c` |
| Blacking out: home, the team gone, a new Pokémon, a save | `src/ov012/event_battle_lose.c`, `FieldMapControl_LoadBlackoutZone` in `src/ov035/event_mapchange.c`, `Script_Blackout` |
| Options on a new game (fastest text, Set battle style, no battle animations) | `Config_Init` in `src/system/config.c` |
| The base's beach and sea (Undella's sand and surf textures), and the grass filled in where cutting off the north left the ground bare | `tools/efu/build_coast.py`, run by `build_base.py` |
| The first exploration zone's maps (`MAP_MATRIX_EFU_ZONE_1`: Route 3, Striaton's garden and Route 2; `MAP_MATRIX_EFU_ZONE_2`: Route 19, Route 20 and Floccesy Ranch), forest everywhere else | `tools/efu/build_zone.py` |
| The zone's events, wild Pokémon (`WILD_LEVELS` and `PLACE_LEVELS`: 2 to 15 on Route 3, 4 to 16 on Route 2, 10 to 20 on Routes 19 and 20, 12 to 22 in Floccesy Ranch, 8 to 18 in the caves, 12 to 22 in the target), the scavs (teams of 2 to 6 at 65 to 90% of the cap, 14 to 20) and their lines, the caves and the target, the childcare centre, Route 3's Day Care, Nurse Joy, and the loot spots (`tools/efu/loot.json`) | `tools/efu/build_raid.py` |
| The one-item bag (one item a Pokémon can hold at a time; Key Items and TMs are free) | `include/efu_bag.h`, used by `Scrcmd_Item_ItemCheckSpace` (`src/ov036/scrcmd_item.c`), taking a held item in `src/ov165/plist_sys.c` and in the PC in `src/ov255/box2_seq.c`, and buying in `src/ov036/scrcmd_shop.c` |
| The bag's pockets (Items, TMs and Key Items; Medicine and Berries show as Items), Give first, A in the empty Items pocket for the party screen, the quicker animations, and the toss to the ground | `src/ov142/itemmenu.c`, `src/ov142/itemmenu_disp.c`, `tools/efu/build_bag.py` (the items' `field_pocket`) |
| Items on the ground, the party's total level, the Day Care's growth, the locker's held items and sell price (`EfuSpecial`, script command 0x15f) | `Scrcmd_Efu_Special` in `src/ov036/scrcmd_field_actor.c`, `Efu_DayCareGrow` in `src/ov036/day_care.c` |
| The locker: its furniture and tiles, its script, and the routines that read and write its slots | `LOCKERS` and `build_lockers` in `tools/efu/build_base.py`, `Script_Locker` in `tools/efu/efu.s.in`, `LOCKER_WORKS` in `tools/efu/gen_efu.py` |
| The base's people: Nurse Joy, the clerk and the Day Care Lady, and the gate's guide | `build_interiors` in `tools/efu/build_base.py`, `Script_Nurse` and below in `tools/efu/efu.s.in`, the mart's prices in `src/ov036/scrcmd_shop.c` |
| The loot tables and the scripts that roll them | `LOOT` in `tools/efu/gen_efu.py`, `Script_Loot*` in `tools/efu/efu.s.in` |
| The closed warehouses' shut doors, and the Day Care Lady's, which goes once she has joined | `CLOSED_WAREHOUSES` in `tools/efu/build_coast.py`, `Efu_IsOpenedDoor` in `src/ov036/field_buildmodel.c`, `Efu_IsShutDoor` in `src/ov036/fieldmap_event.c`, the door signs in `tools/efu/build_base.py` |
| Wild Pokémon that count as equivalent, by egg group | `tools/efu/wild_groups.py` → `tools/efu/wild_groups.json` |
| The scavs' pursuit | `EventTrainerEye_EfuPursue` in `src/ov036/event_trainer_eye.c`, called each step from `src/ov036/fieldmap_event.c` |
| Script commands | `src/ov012/scrcmd_pokemon.c`, `EVCMD_TABLE` in `src/ov012/scrcmd_vm.c` from 0x2f3, and a row each in `EVCMD_PERM_TABLE` in `src/ov012/script_sys.c` (without one the command reads past the table and hangs); 0x2db and 0x15f took over unused commands' rows, so the tables keep their size |

Edit the templates, then from `tools/efu` run `python3 build_base.py`, `python3 build_zone.py`, `python3 build_raid.py`,
`python3 build_bag.py` and `python3 gen_efu.py`, in that order (`gen_efu.py` reads `build_raid.py`'s `loot.json`). Never edit
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
| `EVENT_WORK_0x41ad` (`EFU_WORK_SAVE_VERSION`) | The save format's version, set on a new game and on heading out on a raid (now 4). Heading out with a save from before version 4 fills its Pokédex. |
| `EVENT_WORK_0x41ab` (`EFU_WORK_RAID_COUNT`) | Raids set out on, which picks the season (`EFU_SEASON`). Version 2; a version 1 save has 0, so winter. |
| `EVENT_WORK_0x41aa` | Retired in version 4: the play time the exploration started at, for the scavs' old 10-minute clock. Not to be reused. |
| `EVENT_WORK_0x4169` (`EFU_WORK_SCAV_PENDING`) | 1 when a scav is to come out on the route at the next step (`Script_RouteEnter`); 0 after, and on heading out. Version 4. |
| `EVENT_WORK_0x415e` (`EFU_WORK_DEV_TEST`) | 1 on a game started from the title menu's Dev Test: its first Pokémon is a level 100 Volcarona. |
| `EVENT_WORK_0x41a9` (`EFU_WORK_SCAVS_OUT`) | Scavs that have come out on this exploration. Version 3. |
| `EVENT_FLAG_0x0a80` to `0x0a8f`, `0x0a49` to `0x0a4e` | Retired: the routes' scavs' hide flags before they came out at spots (versions 3 and 4). Not to be reused. |
| `EVENT_FLAG_0x0a01` to `0x0a3f` (`EFU_FLAG_SPOT_FIRST`) | Each route spot's scav's hide flag, in the order `build_raid.py` gives them (Route 3's with the garden's, Route 20's, Route 2's, Route 19's; 47 so far). All set on heading out; one is cleared when its scav comes out, and set again when it is beaten. |
| `EVENT_FLAG_0x0a4f` (`EFU_FLAG_GARDEN_SCAV`) | The garden's scav's hide flag: cleared on heading out, set when it is beaten. |
| `EVENT_FLAG_0x0a90` to `0x0a92` (`EFU_FLAG_LOOT_FIRST`) | The hide flags of the item balls put where the original had none (the Cave of Being's three). Rolled on heading out. |
| `EVENT_FLAG_0x0a93` (`EFU_FLAG_CHILDCARE_SCAV`) | The childcare centre's scav's hide flag: out on each entry while the Day Care Lady's quest is open, then by chance as the target's (75% on the first entry, 25% after); set on heading out and when it is beaten. |
| `EVENT_WORK_0x41a8` (`EFU_WORK_TOSSED_ITEM`) | The item the bag tossed last, until `Script_Toss` puts it on the ground; 0 after. |
| `EVENT_FLAG_0x0a94` (`EFU_FLAG_JOY_JOINED`) | Nurse Joy has joined the base (and her forest NPC's hide flag). |
| `EVENT_FLAG_0x0a95` (`EFU_FLAG_BASE_JOY_HIDDEN`) | Her base NPC's hide flag, set from the above on entering the Pokémon Center. |
| `EVENT_FLAG_0x0a96` (`EFU_FLAG_CLERK_MET`) | The clerk has told their story (and the waiting-area clerk's hide flag). |
| `EVENT_FLAG_0x0a97` (`EFU_FLAG_BASE_CLERK_HIDDEN`) | The counter clerk's hide flag, set from the above on entering the Pokémon Center. |
| `EVENT_FLAG_0x0a98` (`EFU_FLAG_DAYCARE_JOINED`) | The Day Care Lady has joined the base (and her Route 3 NPC's hide flag). |
| `EVENT_FLAG_0x0a99` (`EFU_FLAG_BASE_DAYCARE_HIDDEN`) | Her NPC's hide flag in her warehouse (`NACRENE_CITY_7`), set from the above on entering it. |
| `EVENT_FLAG_0x0a9a` to `0x0a9c` (`EFU_FLAG_DOOR_FIRST`) | The hide flags of the boulders in front of the zone's doors that can be shut (`DOORS` in `build_raid.py`), rolled on heading out. `0x0a9d` was the Day Care's, whose door is never shut now; an older save may have it set, and nothing reads it. |
| `EVENT_FLAG_0x0a43` (`EFU_FLAG_DAYCARE_DEPOSIT_ONLY`) | Set while the Day Care Lady's original script runs for her Route 3 NPC, which leaves Withdraw out of its menu. Cleared after. |
| `EVENT_FLAG_0x0a45` | Retired: set on the first entry to Route 3 on an exploration, when the first entry brought no scav (version 4). Not to be reused. |
| `EVENT_FLAG_0x0a44` (`EFU_FLAG_DAYCARE_QUEST_DONE`) | Set once the childcare centre's scav (trainer 401) has been beaten: the Day Care Lady's quest. |
| `EVENT_FLAG_0x0a9e` (`EFU_FLAG_GUIDE_MET`) | The guide has been met on Route 3 (and their Route 3 NPC's hide flag). |
| `EVENT_FLAG_0x0a9f` (`EFU_FLAG_BASE_GUIDE_HIDDEN`) | The gate guide's hide flag, set from the above on entering the gate. |
| `EVENT_FLAG_0x0a40` to `0x0a42` (`EFU_FLAG_TARGET_SCAV_FIRST`) | The target's scavs' hide flags: set on heading out, then each one still hidden comes out on an entry by chance (75% on the first entry, 25% after); set again only when it is beaten. |
| `EVENT_FLAG_0x0a46` (`EFU_FLAG_TARGET_ENTERED`) | Set on the first entry to the target on an exploration, cleared on heading out. Version 4. |
| `EVENT_FLAG_0x0a47` (`EFU_FLAG_CHILDCARE_ENTERED`) | The same for the childcare centre. Version 4. |
| `EVENT_FLAG_0x0a48` (`EFU_FLAG_DOWNFALL`) | Set for an exploration that drew downfall (30%, `EFU_DOWNFALL_CHANCE`): rain, or snow in winter, wherever the sky is open. Cleared when it ends. Version 4. |
| `EVENT_WORK_0x4163` (`EFU_WORK_CLERK_CALLED`) | 1 once the clerk has met the player, which turns off the trigger inside the Pokémon Center's door. Version 4. |
| `EVENT_WORK_0x415f` (`EFU_WORK_RAID_HOUR`) | The exploration's hour of the day plus 1, rolled on heading out; 0 at home, for the real clock's. Version 4. |
| `EVENT_WORK_0x41a7` to `0x41a0`, `0x419e` to `0x4197`, `0x4193`, `0x418b`, `0x4180`, `0x4177` (`LOCKER_WORKS` in `gen_efu.py`) | The locker's 20 slots, in that order: each the item plus its count shifted left 10 (up to 63), 0 when empty. Kept packed, used slots first. A save from before the locker has them all 0, an empty locker. |

The original item balls of the zone, its caves and its target keep their own flags (the original's meaning, set when
the ball is taken), and heading out rolls them again too.

Free event flags (nothing refers to them) include 0x091e to 0x095f; take them upward from 0x091e. (0x0aa0 and up are daily flags, which the game clears each day.)

Free event work values (no script, source file or event data refers to them): 0x410e, 0x410f, 0x4122, 0x413d, 0x4143,
0x4156 to 0x415d. Take the next from the end of the list back, and move it into the table above.

## Raids and saving

- The east gate (`ZONE_NACRENE_GATE`) has two triggers. Column 14, by Route 3's door, is live while home
  (`EFU_WORK_RAID` 0): it asks to head out, refuses without a Pokémon that can fight, and on yes sets the raid and
  saves. Column 2, by Nacrene's door, is live while out (`EFU_WORK_RAID` 1): it clears the raid and saves.
  Heading out also counts the raid (the season moves on) and gives the running shoes, for saves from version 1.
- Heading out also rolls the exploration's hour (`EFU_WORK_RAID_HOUR`) and whether it has downfall
  (`EFU_FLAG_DOWNFALL`, 30%). The field's light, its day period and the battles' backgrounds read the hour through
  `Efu_GetDaySeconds` (`src/ov036/fieldmap.c`), with the minutes still the clock's; the clock itself and main are left
  alone, since main's size is held by the secure area. The downfall is `GetDefaultWeatherValue`'s
  (`src/ov012/field_encount_st.c`, a stub in the original): rain, or snow in winter, in every zone the player can fly
  from whose own weather is clear. Coming home, losing the raid or blacking out puts both back (`L_RaidOver`).
- Continuing a save with the raid set (the game was switched off before coming back, or saved from the menu while
  out) runs `Script_RaidLost`: it empties the party, says so, clears the raid, gives a new Pokémon, saves and sends
  the player home.
- Blacking out sends the player home (`FieldMapControl_LoadBlackoutZone`), and `Script_Blackout` fades in, clears the
  raid, empties the party, gives a new Pokémon and saves.
- The new Pokémon, on a new game and after every loss, is a random one from the starter list at level
  `EFU_LOST_SOUL_LEVEL` (5; `L_LostSoul`, generated by `gen_efu.py`), "as lost as you are".

## The exploration zone

The first zone runs from the east gate through Route 3, Route 2 and Pinwheel Forest to Route 19 and Route 20, with
Rumination Field off the forest (Tom's map of 19 November). Its maps are two matrices of the hack's own
(`build_zone.py`), each the overworld's size with every chunk where the overworld has it unless it moved, and forest
(`MAP_OUTTREE`, all of it blocked) everywhere else, so no town can be reached:

- `MAP_MATRIX_EFU_ZONE_1`: Route 3's five chunks, Striaton's west chunk (its garden, at the end of Route 3's road
  south) and Route 2's three. Their ground meets as it always did, and their events keep their coordinates, so a
  position saved by an older build still stands. A short path is cut south through the trees at the garden's foot
  (`CUTS`: everything above the ground in the rectangle goes, grass is laid and its tiles copy the nearest walkable
  ones; the tree rows at its sides stay as its walls) to the forest's way in. The garden's road east and Route 2's
  path north end in the forest, and Route 2's ground no longer meets the garden's.
- `MAP_MATRIX_EFU_ZONE_2`: Route 19 moved one chunk east and one north, into Floccesy Town's place, and raised 16
  units (`RAISED`, with cliff faces down from its edges), so its path east meets Route 20's path west; Route 20 and
  Floccesy Ranch where they are. Two tiles of Route 19's high ground at that seam are blocked (`BLOCKED`).

Each matrix carries its chunks' zones (garden with Route 3), so walking from Route 19 into Route 20 changes zone without a fade: the new zone's events load and its init script runs (`Script_RouteEnter`, the
25% chance of a scav). The changed chunks are copies (`efu_zone_1_*`, `efu_zone_2_*`).

Its ways (`build_raid.py`, A to C on Tom's map):

- the east gate's Route 3 door, home;
- the end of the path cut south from the garden (a walk-into warp on the trees' first row past it) into Pinwheel
  Forest's inner forest at A, its old way out to the outer forest;
- the garden's road east (a walk-into warp on the forest's first column) to Route 2's south end, the dead end below
  its path by the old gate to Accumula (a walk-into warp on the row below), and back;
- the forest's top gate (B, once to Skyarrow Bridge) out to Route 19, where Route 19's old gate to Aspertia was: its
  path now runs into the trees;
- the forest's C, as in the original, to Rumination Field and back;
- Route 2's old gate to Accumula Town: a ride home for $100 (`Script_PaidExit`, a trigger in front of its door, while
  out on a raid), which ends the exploration at the east gate's Route 3 door, from where the player walks into the base
  as from the route; without the money or on no, a step back;
- Route 20's old gate to Virbank, a free way home to the same door;
- Route 3's two houses, Wellspring Cave (both floors), the Cave of Being (Route 20's mound) and Floccesy Ranch's barn.

The caves and the forest keep only their item balls and their ways; their Trainers and story triggers are gone, and
so are Route 19's and Route 20's story triggers.

Three of the doors can be shut (`DOORS`: the childcare centre, Wellspring Cave and the Cave of Being; the Day Care's
never is): heading out
(`L_DoorRoll`) puts a boulder in front of each on `EFU_DOOR_SHUT_CHANCE` (30) percent of explorations, except the
childcare centre's while the Day Care Lady's quest to beat its scav is open. The boulders
are `OBJ_CODE_MODEL_3`, the strength boulder with a drawn model (the other rock codes draw nothing), one for each
tile of a wide way in. Strength can push one aside; the game saves no position for them outside its own puzzle rooms,
so the next zone load puts it back.

The guide waits on Route 3 near the gate (`GUIDE`, `Script_GuideMeet`). Meeting them sets `EFU_FLAG_GUIDE_MET`, and
from then on they stand behind the east gate's counter (`Script_GateInit`). The gate's news board says how many
explorations the player has set out on (`EFU_WORK_RAID_COUNT`, `GimmickGate_AddDateMessage`).

## Loot

Every item ball of the zone, its caves and its target runs a loot script of its place (route, cave or target,
`EFU_SCRIPT_LOOT_*`), which picks a tier by the place's chances, rolls the item from the tier's table, and hands it to
the original item ball script (global 7400) to give and to hide the ball. Heading out rolls every spot again
(`L_LootRoll`): the ball is out unless the place's empty chance comes up. `gen_efu.py` has the tables (`LOOT_TIERS`,
`LOOT_PLACES`):

| Place | Empty | Common | Uncommon | Rare | Valuable |
| --- | --- | --- | --- | --- | --- |
| Route | 40% | 85% | 15% | | |
| Cave | 25% | 50% | 40% | 10% | |
| Target | 15% | 15% | 50% | 32% | 3% |
| A scav's drop | | | 45% | 45% | 10% |

Common is Tiny Mushrooms, Poké Balls, Oran Berries, Potions, Repels and the status cures; Uncommon Great Balls, Super
Potions, Pearls, Stardust, Full Heals, Sitrus Berries, Big Mushrooms, Super Repels, Ethers and Fresh Water; Rare Ultra
Balls, Hyper Potions, Revives, Nuggets, Big Pearls, Lum Berries, Elixirs, a Rare Candy or a Heart Scale; Valuable Star
Pieces, Max Revives, Full Restores, PP Ups, Big Nuggets, Comet Shards and four held items. The childcare centre's
Rare Candy is its own place, out on 10% of explorations. The hidden items of these places are gone, since the dowsing
table ties them to their original places. `FieldScript_CheckSCRID` (ov012) lets actors run the hack's scripts (above
the original's last, 10913), or talking to a loot ball would do nothing.

## The one-item bag

The bag carries one item that a Pokémon can hold: one item of the Items, Medicine or Berries pockets (Poké Balls are
in Items), counting each of a stack. Key Items and TMs and HMs are free. To carry more, give items to the team. Main's
bag code can't change, so `Efu_BagHasRoom` (`include/efu_bag.h`) is asked where items come in:

- `ItemCheckSpace` (script command), which the item ball script (7400), hidden items and most gifts ask first, so a
  loot ball asks first too (`L_LootSwapOut`): with the bag's item carried it leaves it on the ball's tile for what's in
  the ball, unseen and without asking, and what the ball holds is rolled only when it is taken, so it can't be peeked
  at and rolled again. A loot ball gives its item with one message over the item fanfare, not through the original's
  item ball script (global 7400) with its two messages and pickup pose. `ItemAdd`
  isn't gated: ov036's size is luck, and every way into the bag in the zone and the base asks `ItemCheckSpace` first.
- Taking a held item, or a held mail, in the party menu, which says the bag is full.
- Taking a held item in the PC, in either mode, which keeps it on the Pokémon.
- Buying in a shop (`ShopUI_TryBuyItem`), one at a time.

Giving an item to a Pokémon that holds one swaps them, which keeps the count, so it is allowed. In battle, an item
chosen and then cancelled goes back to the bag, which is also allowed.

The bag shows three pockets: Items, TMs and HMs, and Key Items. Main's table of pockets (`sItemPockets`) can't change,
so medicine and berries still go in their own pockets in the save, and the bag shows whichever of the Items, Medicine
and Berries pockets holds the one item as Items (`Efu_BagItemPocket`, named and tabbed as Items by
`Efu_BagShownPocket`); the item data's `field_pocket` says Items for them too, for the pickup messages
(`build_bag.py`). There is no Free Space. The fades, the cursor's flash and the pocket arrows are quicker. Trash is Toss,
and tossing a single item doesn't ask.

The field bag shows the party on the upper screen in place of the item's description, as the party screen's grid and
plates (BGs 4, 5 and 7, `ItemMenuDisp_EfuCreateParty`), each with the Pokémon's name and level and, where the party
screen has its HP and sex, its held item's icon and name; the lower screen is the bag's own. Picking a Pokémon with the
keys after Give in an item's menu or A in the empty Items pocket (`ItemMenu_StateEfuPickParty`, its plate lit) gives it
the bag's item, swapping for the one it holds, or takes its item when the bag has none (`ItemMenu_EfuPartyAction`). Eggs
and mail are left alone. Arceus's and Genesect's forms follow the item as in the party screen.

## Items on the ground

Tossing an item from the bag opened in the field puts it on the ground: the bag keeps the item in
`EFU_WORK_TOSSED_ITEM` and reserves `Script_Toss`, which runs once the field is back and puts it in an item ball on
the first free tile of the eight around the player (below, left, right, above, then the corners), or says it's gone
when none is free. The balls are actors that `EfuSpecial` makes (IDs from `EFU_GROUND_ID_FIRST`, 16 at most), with
the item in user parameter 0 and `Script_GroundItem` as their script: it gives the item if the bag has room, or else
swaps the bag's item for it without asking, leaving the bag's item in its place. A scav's drop that doesn't fit lands
beside the player the same way. The balls are the zone's actors, so they last through menus and battles but are gone
once the player leaves the zone.


## The locker

The player's storage: 20 slots, each one kind of item, up to 63 of it, in event work values of their own
(`LOCKER_WORKS`), so one locker shared by its three spots. It is Nimbasa's stadium locker (field prop 126, `shelf06`) in
three places: upstairs in the player's warehouse, against the back wall right of the bed; in the Pokémon Center,
its back to the Poké Mart counter's west side; and in the east gate's northwest corner, where its bin and two chairs
were (`remove_props` drops them from the gate's model, which only that gate uses, edited in place). Its tiles are blocked and talking to either runs `Script_Locker`.
The warehouse's is in a copy of the warehouse's map model (`efu_home`, its own matrix), since the Day Care Lady's
warehouse shares the original; the Pokémon Center's model is edited in place (a skinned model, which the packer can't
write whole), so every Pokémon Center has the locker, though no other can be reached.

The locker lists its items with their counts, then Store everything and Close, with the player's money in the corner.
Store everything moves the bag's item and every held item of the party (eggs' and mail aside) into the locker,
stacking onto a slot of the same item, and says when the locker is full. An item offers Take (one into the bag, or a
message if the bag already has its item) or Sell (one, for half its price, the usual sell price). Neither asks to
confirm, and B closes either menu.

## The base's people

- **Nurse Joy** waits in the northwest of the target (`JOY` in `build_raid.py`). She heals the team on the spot for a
  dollar a level of the party (`EFU_SPECIAL_PARTY_LEVELS`; an egg counts its level), then offers to join the base for
  `EFU_JOY_HIRE` ($1000). Once she has, she's at the base Pokémon Center's counter, healing for the same price.
- **The clerk** sits in the Pokémon Center's waiting area. The first time the player steps inside, the clerk notices
  them, walks over and tells what happened (`Script_ClerkCall`, a trigger inside the door that
  `EFU_WORK_CLERK_CALLED` turns off), then moves to the Poké Mart counter, which then buys anything at the usual half
  price and sells `MART` (`build_base.py`; Poké and Great Balls, Potions, Super Potions, Revives, Full Heals, Repels
  and Escape Ropes) at the normal prices. It is Nacrene's old mail counter's list (`EFU_MART_SHOP_ID`), run by
  the original clerk's script (global 10110).
- **The Day Care Lady** is in Route 3's Day Care, whose door is never shut. There she takes Pokémon in but gives
  none back (`Script_DayCareJoin` runs her original script, global 2201, with `EFU_FLAG_DAYCARE_DEPOSIT_ONLY` set,
  which `build_raid.py` patches into `global_2200.s` to leave Withdraw out of its menu): an early form of the
  insurance broker. Until she has joined, she asks the player to drive out the scav in the childcare centre next
  door, which is always there while her quest is open; once it is beaten (`EFU_FLAG_DAYCARE_QUEST_DONE`, from its
  trainer flag) she moves into the abandoned warehouse east of the Pokémon Center (`NACRENE_CITY_7`, `DAYCARE_DOOR`)
  and keeps coming out to the route after. Until then the warehouse's doorway has a shut door like the other closed
  warehouses' (`build_coast.py`), its two door warps (`EFU_DAYCARE_WARP`, `EFU_DAYCARE_UPPER_WARP`) lead nowhere
  (`Efu_IsShutDoor` in `fieldmap_event.c`'s `GetWarpForWalkIn`), and a sign on each says the door is locked. Once she
  has joined, `Efu_IsOpenedDoor` leaves the door prop out each time its chunk loads, which shows the warehouse's own
  open doorway, and the warps, which never move, work: the top floor's door comes out at the top of the stairs
  outside. (Warps can't be moved by an init script: the player's arrival on one is worked out before those run.)
  Inside, her original script runs her with Withdraw, the only place Pokémon come back. The Day Care no longer grows
  its Pokémon by steps or makes eggs (`DayCare_Update`); instead each raid's return gives each one a level, up to
  `EFU_LEVEL_CAP` (22, the zone's highest wild level), and withdrawing charges the original's $100 a level plus $100.
- **The gate's guide** is first met on Route 3, then waits behind the east gate's counter. They will take the player
  to the farther zones; for now they say Route 3 is as far as anyone goes.

The player's warehouse (`NACRENE_CITY_8`) is theirs alone. The title menu offers only Continue, New Game and Dev Test
(`StartMenu_InitItems`; Dev Test is the Mic Test's item, renamed), a new game for play testing that starts with a
level 100 Volcarona instead of a random level 5 Pokémon (`NewGame_Init` sets `EFU_WORK_DEV_TEST`, which
`Script_NewGameStart` reads). A Pokémon taken out of the PC (withdrawn, moved or swapped into the party) comes out with half
its HP and half of each move's PP, rounded up (`Efu_RecoverHalf` in `box2_main.c`).

Each base NPC is hidden by its own flag, which the zone's init script (`Script_PokecenInit`, `Script_DayCareInit`, `Script_GateInit`) sets
from whether that person has joined, so the base needs no save upgrade.

## The Pokédex

A new game starts with the national Pokédex, every species seen (`L_PokedexFill`, with `EFU_SPECIAL_FILL_POKEDEX`;
heading out with a save from before version 4 fills it too). Every entry is whole: `pokedex_info.c` shows the
category, height, weight, description and footprint whether or not the player has caught the Pokémon, and the
search's type and size orders take any seen species (`pokedex_search_engine.c`). The caught marks are the player's
own: the ball in the list, the caught label on the entry and the ball by a wild Pokémon's HP bar in battle show only
species the player has caught. Catching a new species neither says its data was added (`btl_server_flow_sub.c`) nor
shows its entry (`event_battle_return.c`).

## Wild groups

`tools/efu/wild_groups.json` (written by `wild_groups.py` from the species' data) sorts every Pokémon that can be met
in the wild into groups that count as equivalent, by first egg group: 13 groups, 601 species. Those the egg groups
leave out are placed by hand: a baby goes with its evolution (Pichu with Pikachu, in Field), Nidorina and Nidoqueen
with Nidoran F (Monster), Ditto with the shapeless Pokémon (Amorphous) and Unown with the living objects (Mineral).
The 48 legendary and mythical Pokémon (Undiscovered with no evolution, and Manaphy and Phione) are in none, since none
can be caught in the wild. Nothing in the game reads the groups yet.

## The scavs

Each route has a scav at every spot where one of its own people stood in the original (its Trainers and passers-by,
not objects or Pokémon; Route 3's include Striaton's people in the garden; 47 spots in all), each fighting as one of
its route's Trainers in turn (Route 19, with none, takes Route 20's; Floccesy Ranch has none yet). The Trainers are
made single battles with two to six Pokémon from the zone's wild ones at 65 to 90% of its level cap (14 to 20),
evolved to their levels, dressed as Team Plasma Grunts (the classes renamed Scav) and given new lines by
`build_raid.py`. Every spot's scav starts hidden: heading out sets their flags (`EFU_FLAG_SPOT_FIRST`). The garden's
own scav, on the Pokémon Breeder's spot, is out from the start of every raid (`EFU_FLAG_GARDEN_SCAV`). Each step the
player takes, `EventTrainerEye_EfuPursue` runs before the original sight check:

- Every entry to a route, the first from the east gate too, `Script_RouteEnter` (every route's init script) asks for
  a scav on `EFU_ROUTE_SCAV_CHANCE` (25%) of entries, and at the next step `EfuScav_Spawn` brings one out at a random
  spot of the route's that can take one: hidden, at least `EFU_SCAV_SPAWN_DIST` (6) steps from the player, and with
  no scav of the same Trainer out. None comes out while `EFU_ROUTE_SCAV_MAX` (3) are out on the route already, the
  garden's counting on Route 3. Its defeat on an earlier exploration is forgotten. The side areas' own scavs (the
  target's three and the childcare centre's) each come out on `EFU_SIDE_SCAV_CHANCE` (75%) of first entries and
  `EFU_ROUTE_SCAV_CHANCE` (25%) of later ones.
- Scavs only ever add up over an exploration: leaving an area and coming back never hides one that is out. Only
  beating one takes it away (`EFU_SPECIAL_SCAV_GONE`, from `Script_ScavDrop`, sets its hide flag and removes its
  actor), until heading out again hides them all.
- A scav that is out stands where it came out, looking around (`MOVE_CODE_TURN_RANDOM`), and never steps until it
  has seen the player: a scav wandering by its move code could be caught between two tiles when a chase or battle
  began, and the game locked up.
- Distances are in steps without diagonal ones, and `EFU_SCAV_CATCH` is 1, so only a scav straight beside the player
  fights. After a win, `Script_ScavDrop` (called from the Trainer battle scripts in `global_3000.s`) gives an item of
  the target's table, or puts it on the ground beside the player when the bag is full.
- A scav that sees the player (nothing in the way on the straight line between them) within
  `EFU_SCAV_CATCH` tiles whichever way it faces, or up to `EFU_SCAV_SIGHT` (12) tiles away in the quarter it faces,
  shows a "!" and gives chase: the soft detection. The hard detection, a battle, is only straight beside the player
  (`EFU_SCAV_CATCH`, which is also the scavs' Trainer sight range in the event data, so the original's sight check
  never starts one further off).
- A chasing scav takes one walking step (`ACMD_WALK_8F`, so it falls behind a running player) toward the tile the
  player stepped onto, the longer way first, the other if that's blocked, or to the side when the player is straight
  ahead and the way is blocked. It moves only when the player steps. Within `EFU_SCAV_CATCH` tiles it starts its
  battle, and after `EFU_SCAV_LOSE_STEPS` steps in a row out of sight it shows a "?" and goes back to looking around where it stopped. The
  chase lives in the actor's user parameters 1 and 2, which the event data leaves 0.

## Fleeing

Running from a wild battle always works (`btl_server_flow.c`): when the original would fail ("Couldn't get away!",
or trapped), the escape count is set to `EFU_ESCAPE_PENDING`, the rest of the turn happens (the wild Pokémon attacks),
and `ActionOrder_Run` gets the player away at its end. If the player's Pokémon faints first, the next try always
works.

## Fewer waits

- **Wild battles start sooner.** The model encounter effects (ov149) flash once, fade sooner and play their model at
  double speed, and the cutins (ov146) flash once (`FLASH_COUNT`). In battle, the opening sweep (effect 000), the
  camera's turn to the player (001) and the send-out (003) are quicker, and the messages no longer wait for the cries.
- **Fewer questions.** Giving an item to a Pokémon that holds one swaps them without asking (`plist_sys.c`). The PC
  takes a held item without asking (`box2_seq.c`), and leaving the PC doesn't ask whether to go on (except in the Dream
  World mode). The bag tosses a single item without asking (`ItemMenu_TossNow`). Loot and ground balls swap without
  asking (above).

## Testing

DeSmuME's CLI under Xvfb with xdotool keys (x is A, z is B, s is X, Return is Start). There are no save states, so
each test plays from boot, and inputs are timing-sensitive: give every step its own key press and a pause. `--arm9gdb`
works for reading memory, but breakpoints don't fire under the JIT.
