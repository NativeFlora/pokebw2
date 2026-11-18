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
// The script of an item on the ground (EfuSpecial): picking it up, or swapping the bag's item for it
#define EFU_SCRIPT_GROUND_ITEM (EFU_SCRIPT_FIRST + 13)
// Reserved by the bag (itemmenu.c) when it tosses an item, to put it on the ground back in the field
#define EFU_SCRIPT_TOSS (EFU_SCRIPT_FIRST + 14)
// The base's people (EFU_JOY_HIRE and below)
#define EFU_SCRIPT_NURSE (EFU_SCRIPT_FIRST + 15)
#define EFU_SCRIPT_JOY_FOREST (EFU_SCRIPT_FIRST + 16)
#define EFU_SCRIPT_CLERK_INTRO (EFU_SCRIPT_FIRST + 17)
#define EFU_SCRIPT_CLERK (EFU_SCRIPT_FIRST + 18)
#define EFU_SCRIPT_DAYCARE_JOIN (EFU_SCRIPT_FIRST + 19)
#define EFU_SCRIPT_POKECEN_INIT (EFU_SCRIPT_FIRST + 20)
#define EFU_SCRIPT_DAYCARE_INIT (EFU_SCRIPT_FIRST + 21)
// The east gate's guide, who will take the player to the farther zones
#define EFU_SCRIPT_GATE_GUIDE (EFU_SCRIPT_FIRST + 22)
// A boulder in front of a door that is shut (EFU_FLAG_DOOR_FIRST, the Day Care's warehouse)
#define EFU_SCRIPT_BLOCKED_DOOR (EFU_SCRIPT_FIRST + 23)
// The east gate's init script: its guide is there once the player has met them (EFU_FLAG_GUIDE_MET)
#define EFU_SCRIPT_GATE_INIT (EFU_SCRIPT_FIRST + 24)
// The guide out in the zone, the first time
#define EFU_SCRIPT_GUIDE_MEET (EFU_SCRIPT_FIRST + 25)
// The target's init script: each of its scavs is out on EFU_TARGET_SCAV_CHANCE percent of entries
#define EFU_SCRIPT_TARGET_ENTER (EFU_SCRIPT_FIRST + 26)
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

// EfuSpecial (script command 0x15f, Scrcmd_Efu_Special in scrcmd_field_actor.c), the hack's odd jobs by operation:
// put an item on the ground (on a tile, or with EFU_GROUND_BESIDE_PLAYER as its x on a free one of the eight around the
// player), read the bag's holdable item (efu_bag.h), add up the party's levels (eggs aside), or give each Pokémon in
// the Day Care a level, up to EFU_LEVEL_CAP (Efu_DayCareGrow in day_care.c)
#define EFU_SPECIAL_DROP 0
#define EFU_SPECIAL_BAG_ITEM 1
#define EFU_SPECIAL_PARTY_LEVELS 2
#define EFU_SPECIAL_DAYCARE_GROW 3
// Items on the ground: item ball actors made where an item was tossed or swapped, each holding its item in its user
// parameter 0, with actor IDs from EFU_GROUND_ID_FIRST. They belong to the zone, and are gone once the player leaves it
#define EFU_GROUND_BESIDE_PLAYER 0xffff
#define EFU_GROUND_ID_FIRST 0xc0
#define EFU_GROUND_MAX 16

// The first zone's level cap, its highest wild level (build_raid.py checks it): the Day Care raises its Pokémon to it
#define EFU_LEVEL_CAP 22
// The base's people (docs/efu.md). Nurse Joy, in Pinwheel Forest's northwest, heals for the party's total level in
// money and joins the base's Pokémon Center for EFU_JOY_HIRE; the clerk, in its waiting area, tells the player what
// happened the first time and runs its Poké Mart after, at EFU_MART_PRICE_FACTOR times the prices (EFU_MART_SHOP_ID's
// list, Nacrene's mail counter in the original, shops.json); the Day Care lady, in Route 3's Day Care, moves into the
// player's warehouse for EFU_DAYCARE_HIRE, and from there each Pokémon left with her gains a level each raid
#define EFU_JOY_HIRE 1000
#define EFU_DAYCARE_HIRE 1000
#define EFU_MART_SHOP_ID 2
#define EFU_MART_PRICE_FACTOR 5
// Set once each has joined the base (the original NPC's hide flag), and the hide flags of their base NPCs, which the
// base's init scripts set from those (Script_PokecenInit, Script_HomeInit)
#define EFU_FLAG_JOY_JOINED 0xa94
#define EFU_FLAG_BASE_JOY_HIDDEN 0xa95
#define EFU_FLAG_CLERK_MET 0xa96
#define EFU_FLAG_BASE_CLERK_HIDDEN 0xa97
#define EFU_FLAG_DAYCARE_JOINED 0xa98
#define EFU_FLAG_BASE_DAYCARE_HIDDEN 0xa99
// The guide, met out in the zone (their NPC's hide flag there), and their NPC's hide flag at the east gate, which its
// init script sets from that (Script_GateInit)
#define EFU_FLAG_GUIDE_MET 0xa9e
#define EFU_FLAG_BASE_GUIDE_HIDDEN 0xa9f

// Doors that are shut on some explorations: each has a boulder in front of it, hidden by its flag from this one
// (build_raid.py's DOORS, in their order), which heading out rolls (L_DoorRoll): shut on EFU_DOOR_SHUT_CHANCE percent
#define EFU_FLAG_DOOR_FIRST 0xa9a
#define EFU_DOOR_COUNT 4
#define EFU_DOOR_SHUT_CHANCE 30
// The target's scavs, each hidden by its flag from this one and out on EFU_TARGET_SCAV_CHANCE percent of entries
#define EFU_FLAG_TARGET_SCAV_FIRST 0xa40
#define EFU_TARGET_SCAV_COUNT 3
#define EFU_TARGET_SCAV_CHANCE 40

// Fleeing (btl_server_flow.c): the original's cap on the escape attempts it counts, and the count that means the
// player failed to get away this turn and gets away at its end
#define EFU_ESCAPE_ATTEMPTS_MAX 30
#define EFU_ESCAPE_PENDING (EFU_ESCAPE_ATTEMPTS_MAX + 1)

#endif // POKEBW2_EFU_H
