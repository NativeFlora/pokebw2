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
  at its v1 size (11520 bytes); ov036 is 354944 bytes now (the original's 352672). ov167 (battle) grew for fleeing and passed too.
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
| The base's beach and sea (Undella's sand and surf textures), and the grass filled in where cutting off the north left the ground bare | `tools/efu/build_coast.py`, run by `build_base.py` |
| The first exploration zone's map (`MAP_MATRIX_EFU_ZONE_1`, which `ZONE_ROUTE_3` uses): Route 3 with Route 20 lowered into Striaton's place, forest everywhere else | `tools/efu/build_zone.py` |
| The zone's events, wild Pokémon (2 to 15 on the route, 8 to 18 in the caves, 12 to 22 in the target), the scavs (teams of 2 to 6 at 65 to 90% of the cap, 14 to 20) and their lines, the caves and the target, the childcare centre, Route 3's Day Care, Nurse Joy, and the loot spots (`tools/efu/loot.json`) | `tools/efu/build_raid.py` |
| The one-item bag (one item a Pokémon can hold at a time; Key Items and TMs are free) | `include/efu_bag.h`, used by `Scrcmd_Item_ItemCheckSpace` (`src/ov036/scrcmd_item.c`), taking a held item in `src/ov165/plist_sys.c` and in the PC in `src/ov255/box2_seq.c`, and buying in `src/ov036/scrcmd_shop.c` |
| The bag's pockets (Items, TMs and Key Items; Medicine and Berries show as Items), Give first, A in the empty Items pocket for the party screen, the quicker animations, and the toss to the ground | `src/ov142/itemmenu.c`, `src/ov142/itemmenu_disp.c`, `tools/efu/build_bag.py` (the items' `field_pocket`) |
| Items on the ground, the party's total level, the Day Care's growth (`EfuSpecial`, script command 0x15f) | `Scrcmd_Efu_Special` in `src/ov036/scrcmd_field_actor.c`, `Efu_DayCareGrow` in `src/ov036/day_care.c` |
| The base's people: Nurse Joy, the clerk and the Day Care Lady, and the gate's guide | `build_interiors` in `tools/efu/build_base.py`, `Script_Nurse` and below in `tools/efu/efu.s.in`, the mart's prices in `src/ov036/scrcmd_shop.c` |
| The loot tables and the scripts that roll them | `LOOT` in `tools/efu/gen_efu.py`, `Script_Loot*` in `tools/efu/efu.s.in` |
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
| `EVENT_WORK_0x41ad` (`EFU_WORK_SAVE_VERSION`) | The save format's version, set on a new game and on heading out on a raid (now 3). |
| `EVENT_WORK_0x41ab` (`EFU_WORK_RAID_COUNT`) | Raids set out on, which picks the season (`EFU_SEASON`). Version 2; a version 1 save has 0, so winter. |
| `EVENT_WORK_0x41aa` (`EFU_WORK_EXPLORE_START`) | The play time in seconds (wrapping at 0x10000), plus 1, at the first step of this exploration; 0 until then. Version 3. |
| `EVENT_WORK_0x41a9` (`EFU_WORK_SCAVS_OUT`) | Scavs that have come out on this exploration. Version 3. |
| `EVENT_FLAG_0x0a80` to `0x0a8f` (`EFU_FLAG_SCAV_FIRST`) | Each scav NPC's hide flag, in the order `build_raid.py` gives them. All set on heading out. Version 3. |
| `EVENT_FLAG_0x0a90` to `0x0a92` (`EFU_FLAG_LOOT_FIRST`) | The hide flags of the item balls put where the original had none (the Cave of Being's three). Rolled on heading out. |
| `EVENT_FLAG_0x0a93` (`EFU_FLAG_CHILDCARE_SCAV`) | The childcare centre's scav's hide flag, rolled on each entry (30% out). |
| `EVENT_WORK_0x41a8` (`EFU_WORK_TOSSED_ITEM`) | The item the bag tossed last, until `Script_Toss` puts it on the ground; 0 after. |
| `EVENT_FLAG_0x0a94` (`EFU_FLAG_JOY_JOINED`) | Nurse Joy has joined the base (and her forest NPC's hide flag). |
| `EVENT_FLAG_0x0a95` (`EFU_FLAG_BASE_JOY_HIDDEN`) | Her base NPC's hide flag, set from the above on entering the Pokémon Center. |
| `EVENT_FLAG_0x0a96` (`EFU_FLAG_CLERK_MET`) | The clerk has told their story (and the waiting-area clerk's hide flag). |
| `EVENT_FLAG_0x0a97` (`EFU_FLAG_BASE_CLERK_HIDDEN`) | The counter clerk's hide flag, set from the above on entering the Pokémon Center. |
| `EVENT_FLAG_0x0a98` (`EFU_FLAG_DAYCARE_JOINED`) | The Day Care Lady has joined the base (and her Route 3 NPC's hide flag). |
| `EVENT_FLAG_0x0a99` (`EFU_FLAG_BASE_DAYCARE_HIDDEN`) | Her NPC's hide flag in her warehouse (`NACRENE_CITY_7`), set from the above on entering it. |
| `EVENT_FLAG_0x0a9a` to `0x0a9d` (`EFU_FLAG_DOOR_FIRST`) | The hide flags of the boulders in front of the zone's doors that can be shut (`DOORS` in `build_raid.py`), rolled on heading out. |
| `EVENT_FLAG_0x0a9e` (`EFU_FLAG_GUIDE_MET`) | The guide has been met on Route 3 (and their Route 3 NPC's hide flag). |
| `EVENT_FLAG_0x0a9f` (`EFU_FLAG_BASE_GUIDE_HIDDEN`) | The gate guide's hide flag, set from the above on entering the gate. |
| `EVENT_FLAG_0x0a40` to `0x0a42` (`EFU_FLAG_TARGET_SCAV_FIRST`) | The target's scavs' hide flags, rolled on each entry (40% out each). |

The original item balls of the zone, its caves and its target keep their own flags (the original's meaning, set when
the ball is taken), and heading out rolls them again too.

Free event flags (nothing refers to them) include 0x0a43 to 0x0a4f, 0x0a01 to 0x0a3f and 0x091e to 0x095f; take
them upward from 0x0a43. (0x0aa0 and up are daily flags, which the game clears each day.)

Free event work values (no script, source file or event data refers to them): 0x410e, 0x410f, 0x4122, 0x413d, 0x4143,
0x4156 to 0x415f, 0x4163, 0x4169, 0x4177, 0x4180, 0x418b, 0x4193, 0x4197 to 0x419e, 0x41a0 to 0x41a7. Take the next
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

## The exploration zone

The east gate opens on `ZONE_ROUTE_3`, whose matrix is the hack's own (`build_zone.py`): Route 3's five chunks where
they always were, so a position saved on Route 3 by an older build still stands, and Route 20's four south of Route
3's east end, where Striaton was, joined where Route 3's road south meets Route 20's north path. Everything else is
forest (`MAP_OUTTREE`), so no town can be reached. Route 20's chunks are copies (`efu_zone_1_*`), 32 units lower so
their ground meets Route 3's; each terrain plane takes the height table's entry nearest the lowered plane
(`MAP_HEIGHT_OFFSET_TABLE`), and cliff faces close the edges where a river or cliff used to run on into the next
chunk. Five tree textures of Route 20's are imported into Striaton's texture sets, season by season.

Its doors: the gate home, Route 3's two houses, Wellspring Cave (both floors), the Cave of Being (Route 20's mound) and
the target, Pinwheel Forest's inner forest, through Route 20's old gate to Virbank. The caves and the forest keep
only their item balls and their way back; their Trainers, story triggers and other exits are gone, except the
forest's gate to Skyarrow Bridge (`EXIT_GATES`), which is a second way home: it opens on the east gate's Route 3 door,
from where the player walks into the base as from the route.

Four of the doors can be shut (`DOORS`: the two houses, Wellspring Cave and the Cave of Being): heading out
(`L_DoorRoll`) puts a boulder in front of each on `EFU_DOOR_SHUT_CHANCE` (30) percent of explorations. The boulders
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

The field bag shows the party on the lower screen, in two columns of three where the pocket tabs were (hidden, their
OBJ palettes reused: `ItemMenuDisp_EfuCreateParty`), each with its held item mark. Tapping a Pokémon, or picking one
with the keys after Give in an item's menu or A in the empty Items pocket (`ItemMenu_StateEfuPickParty`), gives it the
bag's item, swapping for the one it holds, or takes its item when the bag has none (`ItemMenu_EfuPartyAction`). Eggs
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


## The base's people

- **Nurse Joy** waits in the northwest of the target (`JOY` in `build_raid.py`). She heals the team on the spot for a
  dollar a level of the party (`EFU_SPECIAL_PARTY_LEVELS`; an egg counts its level), then offers to join the base for
  `EFU_JOY_HIRE` ($1000). Once she has, she's at the base Pokémon Center's counter, healing for the same price.
- **The clerk** sits in the Pokémon Center's waiting area. The first time the player talks to them, they tell what
  happened and move to the Poké Mart counter, which then buys anything at the usual half price and sells
  `MART` (`build_base.py`; Poké and Great Balls, Potions, Super Potions, Revives, Full Heals, Repels and Escape Ropes)
  at `EFU_MART_PRICE_FACTOR` (5) times the price. It is Nacrene's old mail counter's list (`EFU_MART_SHOP_ID`), run by
  the original clerk's script (global 10110).
- **The Day Care Lady** is in Route 3's Day Care. For `EFU_DAYCARE_HIRE` ($1000) she moves into the abandoned
  warehouse east of the Pokémon Center (`NACRENE_CITY_7`, `DAYCARE_DOOR`), whose door a boulder blocks until she
  has, and where the original Day Care Lady's script (global 2201) runs her. The Day Care no longer grows
  its Pokémon by steps or makes eggs (`DayCare_Update`); instead each raid's return gives each one a level, up to
  `EFU_LEVEL_CAP` (22, the zone's highest wild level), and withdrawing charges the original's $100 a level plus $100.
- **The gate's guide** is first met on Route 3, then waits behind the east gate's counter. They will take the player
  to the farther zones; for now they say Route 3 is as far as anyone goes.

The player's warehouse (`NACRENE_CITY_8`) is theirs alone. The title menu offers only Continue and New Game
(`StartMenu_InitItems`). A Pokémon taken out of the PC (withdrawn, moved or swapped into the party) comes out with half
its HP and half of each move's PP, rounded up (`Efu_RecoverHalf` in `box2_main.c`).

Each base NPC is hidden by its own flag, which the zone's init script (`Script_PokecenInit`, `Script_DayCareInit`, `Script_GateInit`) sets
from whether that person has joined, so the base needs no save upgrade.

## The scavs

Route 3's and Route 20's Trainers, made single battles with two to six Pokémon from the zone's wild ones at 65 to 90%
of its level cap (14 to 20), evolved to their levels, dressed as Team Plasma Grunts (the classes renamed
Scav) and given new lines by `build_raid.py`, start hidden: heading out sets their flags. Each step the player takes,
`EventTrainerEye_EfuPursue` runs before the original sight check:

- `EfuScav_Spawn` starts the exploration's clock on its first step, and once `EFU_SCAV_SPAWN_SECONDS` (10 minutes) of
  play time have passed, and again each time that much more has, brings out the hidden scav furthest from the player
  on the current map, with its defeat on an earlier exploration forgotten.
- A scav that is out stands where it came out, looking around (`MOVE_CODE_TURN_RANDOM`), and never steps until it
  has seen the player: a scav wandering by its move code could be caught between two tiles when a chase or battle
  began, and the game locked up.
- Distances are in steps without diagonal ones, and `EFU_SCAV_CATCH` is 1, so only a scav straight beside the player
  fights. After a win, `Script_ScavDrop` (called from the Trainer battle scripts in `global_3000.s`) gives an item of
  the target's table, or puts it on the ground beside the player when the bag is full.
- A scav that sees the player (nothing in the way on the straight line between them) within
  `EFU_SCAV_CATCH` tiles whichever way it faces, or up to `EFU_SCAV_SIGHT` (7) tiles away in the quarter it faces,
  shows a "!" and gives chase.
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
