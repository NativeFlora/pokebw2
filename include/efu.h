#ifndef POKEBW2_EFU_H
#define POKEBW2_EFU_H

// The scripts include this file too, so the C headers are only for C
#ifndef __ASSEMBLER__
#include "types.h"
#include "system/season.h"
#endif

// Escape from Unova: the hack's own constants

// The global scripts of res/field/scripts/efu.s, from 11000 in its order (GLOBAL_SCRIPT_TABLE in script_sys.c)
#define EFU_SCRIPT_FIRST 11000
#define EFU_SCRIPT_NEW_GAME_SETUP (EFU_SCRIPT_FIRST + 0)
#define EFU_SCRIPT_NEW_GAME_START (EFU_SCRIPT_FIRST + 1)
#define EFU_SCRIPT_BOARDED_DOOR (EFU_SCRIPT_FIRST + 2)
#define EFU_SCRIPT_BED (EFU_SCRIPT_FIRST + 3)
#define EFU_SCRIPT_RAID_DEPART (EFU_SCRIPT_FIRST + 4)
#define EFU_SCRIPT_RAID_RETURN (EFU_SCRIPT_FIRST + 5)
#define EFU_SCRIPT_RAID_LOST (EFU_SCRIPT_FIRST + 6)
#define EFU_SCRIPT_BLACKOUT (EFU_SCRIPT_FIRST + 7)
// An item ball of an exploration zone, by the tier of its place: what it holds is rolled when it is picked up
#define EFU_SCRIPT_LOOT_ROUTE (EFU_SCRIPT_FIRST + 8)
#define EFU_SCRIPT_LOOT_CAVE (EFU_SCRIPT_FIRST + 9)
#define EFU_SCRIPT_LOOT_TARGET (EFU_SCRIPT_FIRST + 10)
// Run (RTCallGlobal) after each win against a scav (global_3000.s): it drops an item from the target's table
#define EFU_SCRIPT_SCAV_DROP (EFU_SCRIPT_FIRST + 11)
// The Route 3 childcare centre's init script: a scav there on 30% of entries
#define EFU_SCRIPT_CHILDCARE (EFU_SCRIPT_FIRST + 12)
// The script of an item on the ground (EfuGround): picking it up, or swapping the bag's item for it
#define EFU_SCRIPT_GROUND_ITEM (EFU_SCRIPT_FIRST + 13)
// Reserved by the bag (itemmenu.c) when it tosses an item, to put it on the ground back in the field
#define EFU_SCRIPT_TOSS (EFU_SCRIPT_FIRST + 14)
#define EFU_SCRIPT_LAST (EFU_SCRIPT_FIRST + 99)

// Saved event work values the original game never uses, so a save keeps them across builds (docs/efu.md). Only ever
// add new ones from the free list there; never move or reuse one
// Whether the player is out on a raid: set and saved on leaving through the east gate, cleared and saved on coming
// back. A save that is continued with it set was left mid-raid, and the raid counts as lost
#define EFU_WORK_RAID 0x41ac
// The save format's version, set on a new game. A later build that changes what the hack keeps in the save checks it
// on continuing and upgrades the old save
#define EFU_WORK_SAVE_VERSION 0x41ad
#define EFU_SAVE_VERSION 3
// How many raids the player has set out on (from save version 2). The season moves on one with each raid, from winter
#define EFU_WORK_RAID_COUNT 0x41ab
// The play time (in seconds, wrapping at 0x10000) the exploration started at, plus 1; 0 until the first step out
#define EFU_WORK_EXPLORE_START 0x41aa
// How many scavs have come out on this exploration
#define EFU_WORK_SCAVS_OUT 0x41a9
// The item the bag tossed last, for EFU_SCRIPT_TOSS to put on the ground; 0 once it has
#define EFU_WORK_TOSSED_ITEM 0x41a8
// The level of the Pokémon that joins a player with none
#define EFU_LOST_SOUL_LEVEL 5
#define EFU_SEASON(raids) ((SEASON_WINTER + (raids)) % SEASON_COUNT)

// The scavs' pursuit (event_trainer_eye.c): how far they see, the distance at which they notice the player whichever
// way they face and a chase becomes a battle (straight beside them), and the steps out of sight before they give up.
// Distances are in steps without diagonal ones
#define EFU_SCAV_SIGHT 7
#define EFU_SCAV_CATCH 1
#define EFU_SCAV_LOSE_STEPS 6
// The Trainer actor's user parameters that keep its chase (they are 0 in the event data)
#define EFU_SCAV_PARAM_CHASE 1
#define EFU_SCAV_PARAM_MOVE_CODE 2
// The scavs come out one at a time, the first after the player has been out exploring this long (play time, in
// seconds), and one more each time it passes again. Each scav's NPC is hidden by its own flag from EFU_FLAG_SCAV_FIRST
// (build_raid.py), all set on heading out
#define EFU_SCAV_SPAWN_SECONDS (10 * 60)
#define EFU_FLAG_SCAV_FIRST 0xa80
#define EFU_SCAV_MAX 16
// The hide flags of the item balls placed where the original had none (build_raid.py's NEW_BALLS), from this one.
// Heading out rolls every loot spot's flag again, these and the original balls' (tools/efu/loot.json)
#define EFU_FLAG_LOOT_FIRST 0xa90
// The hide flag of the scav in Route 3's childcare centre, rolled on each entry (Script_ChildcareEnter)
#define EFU_FLAG_CHILDCARE_SCAV 0xa93

// Items on the ground (EfuGround, Scrcmd_Efu_Ground in scrcmd_field_actor.c): item ball actors made where an item
// was tossed or swapped, each holding its item in its user parameter 0, with actor IDs from EFU_GROUND_ID_FIRST. They
// belong to the zone, and are gone once the player leaves it. EfuGround's operations: put an item on the ground (on a
// tile, or with EFU_GROUND_BESIDE_PLAYER as its x on a free one of the eight around the player), or read the bag's
// holdable item (efu_bag.h)
#define EFU_GROUND_DROP 0
#define EFU_GROUND_BAG_ITEM 1
#define EFU_GROUND_BESIDE_PLAYER 0xffff
#define EFU_GROUND_ID_FIRST 0xc0
#define EFU_GROUND_MAX 16

// Fleeing (btl_server_flow.c): the original's cap on the escape attempts it counts, and the count that means the
// player failed to get away this turn and gets away at its end
#define EFU_ESCAPE_ATTEMPTS_MAX 30
#define EFU_ESCAPE_PENDING (EFU_ESCAPE_ATTEMPTS_MAX + 1)

#endif // POKEBW2_EFU_H
