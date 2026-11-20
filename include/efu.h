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
// The Route 3 childcare centre's init script: a scav there always while the Day Care Lady's quest is open, then on
// EFU_SIDE_SCAV_CHANCE percent of entries
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
// A boulder in front of a zone door that is shut on this exploration (EFU_FLAG_DOOR_FIRST)
#define EFU_SCRIPT_BLOCKED_DOOR (EFU_SCRIPT_FIRST + 23)
// The east gate's init script: its guide is there once the player has met them (EFU_FLAG_GUIDE_MET)
#define EFU_SCRIPT_GATE_INIT (EFU_SCRIPT_FIRST + 24)
// The guide out in the zone, the first time
#define EFU_SCRIPT_GUIDE_MEET (EFU_SCRIPT_FIRST + 25)
// The target's init script: each of its scavs is out on EFU_SIDE_SCAV_CHANCE percent of entries
#define EFU_SCRIPT_TARGET_ENTER (EFU_SCRIPT_FIRST + 26)
// The locker, in the player's warehouse and by the Pokémon Center's Poké Mart counter: 20 slots, each in an event work
// value of its own (gen_efu.py's LOCKER_WORKS, docs/efu.md)
#define EFU_SCRIPT_LOCKER (EFU_SCRIPT_FIRST + 27)
// The signs on the Day Care Lady's warehouse doors, which say they are locked until she has joined
#define EFU_SCRIPT_DAYCARE_DOOR (EFU_SCRIPT_FIRST + 28)
// Route 3's init script, on each entry to the route: a scav may come out on coming back from a side area
// (EFU_ROUTE_SCAV_CHANCE)
#define EFU_SCRIPT_ROUTE_ENTER (EFU_SCRIPT_FIRST + 29)
// The trigger inside the Pokémon Center's door: the clerk (NPC EFU_CLERK_INTRO_ID, standing at x EFU_CLERK_INTRO_X)
// notices the player, walks over and talks the first time; EFU_WORK_CLERK_CALLED stops it running again
#define EFU_SCRIPT_CLERK_CALL (EFU_SCRIPT_FIRST + 30)
#define EFU_CLERK_INTRO_ID 8
#define EFU_CLERK_INTRO_X 1
// Route 2's old gate to Accumula Town, an exit from the zone: a ride home for EFU_PAID_EXIT_PRICE (a trigger in front of
// its door)
#define EFU_SCRIPT_PAID_EXIT (EFU_SCRIPT_FIRST + 31)
#define EFU_PAID_EXIT_PRICE 100
// Floccesy Ranch's init script: its scavengers come out by chance (EFU_FLAG_RANCH_SCAV_FIRST)
#define EFU_SCRIPT_RANCH_ENTER (EFU_SCRIPT_FIRST + 32)
// Burgh, Rumination Field's boss: his battle, the Blank HM and the end of the zone's story (EFU_FLAG_BURGH_BEATEN)
#define EFU_SCRIPT_BURGH (EFU_SCRIPT_FIRST + 33)
// The world editor's locked doors (tools/efu/world_editor, apply_world_edits.py): a warp whose grid's unk0a is n leads
// nowhere until EFU_FLAG_LOCK_FIRST + n - 1 is set (GetWarpForWalkIn in fieldmap_event.c), and a sign on its tile
// runs EFU_SCRIPT_LOCK_FIRST + n - 1, which opens it with its key, if it has one (gen_efu.py writes them from
// tools/efu/world_locks.json)
#define EFU_SCRIPT_LOCK_FIRST (EFU_SCRIPT_FIRST + 34)
#define EFU_LOCK_COUNT 32
#define EFU_SCRIPT_LAST (EFU_SCRIPT_FIRST + 99)

// Saved event work values the original game never uses, so a save keeps them across builds (docs/efu.md). Only ever
// add new ones from the free list there; never move or reuse one
// Whether the player is out on a raid: set and saved on leaving through the east gate, cleared and saved on coming
// back. A save that is continued with it set was left mid-raid, and the raid counts as lost
#define EFU_WORK_RAID 0x41ac
// The save format's version, set on a new game. A later build that changes what the hack keeps in the save checks it
// on continuing and upgrades the old save
#define EFU_WORK_SAVE_VERSION 0x41ad
#define EFU_SAVE_VERSION 4
// How many raids the player has set out on (from save version 2). The season moves on one with each raid, from winter
#define EFU_WORK_RAID_COUNT 0x41ab
// 1 when a scav is to come out on the route at the player's next step (Script_RouteEnter, EfuScav_Spawn); 0 after
#define EFU_WORK_SCAV_PENDING 0x4169
// How many scavs have come out on this exploration
#define EFU_WORK_SCAVS_OUT 0x41a9
// The item the bag tossed last, for EFU_SCRIPT_TOSS to put on the ground; 0 once it has
#define EFU_WORK_TOSSED_ITEM 0x41a8
// 1 once the clerk has met the player, which turns off EFU_SCRIPT_CLERK_CALL's trigger
#define EFU_WORK_CLERK_CALLED 0x4163
// A raid's hour of the day plus 1, rolled on heading out, or 0 at home for the real clock's (Efu_GetDaySeconds in
// fieldmap.c: the field's light, its day period and the battles' backgrounds)
#define EFU_WORK_RAID_HOUR 0x415f
// 1 on a game started from the title menu's Dev Test (GameStart_DevTest): its first Pokémon is a level 100 Volcarona
#define EFU_WORK_DEV_TEST 0x415e
// The level of the Pokémon that joins a player with none
#define EFU_LOST_SOUL_LEVEL 5
#define EFU_SEASON(raids) ((SEASON_WINTER + (raids)) % SEASON_COUNT)

// The scavs' pursuit (event_trainer_eye.c): how far they see, which starts a chase (the soft detection), the distance
// at which they notice the player whichever way they face and a chase becomes a battle (straight beside them, the hard
// detection, which is also their Trainer sight range, so the original's sight check never starts a battle further off),
// and the steps out of sight before they give up. Distances are in steps without diagonal ones
#define EFU_SCAV_SIGHT 12
#define EFU_SCAV_CATCH 1
#define EFU_SCAV_LOSE_STEPS 6
// How often the scavengers look and move while the player stands still, in frames: about a walking step
#define EFU_SCAV_IDLE_FRAMES 16
// The frames counted toward it (EventTrainerEye_EfuIdle)
#define EFU_WORK_IDLE_FRAMES 0x415d
// The Trainer actor's user parameters that keep its chase (they are 0 in the event data)
#define EFU_SCAV_PARAM_CHASE 1
#define EFU_SCAV_PARAM_MOVE_CODE 2
// The routes' scavs: each entry to a route (Script_RouteEnter) brings one out on EFU_ROUTE_SCAV_CHANCE percent of them,
// at a random spot of the route's where one of its own people stood (EfuScav_Spawn), while fewer than
// EFU_ROUTE_SCAV_MAX are out there and none nearer the player than EFU_SCAV_SPAWN_DIST steps. Each spot has its own
// scav, hidden by its own flag from EFU_FLAG_SPOT_FIRST (build_raid.py), all set on heading out, so a scav stays until
// it is beaten. The garden's (EFU_FLAG_GARDEN_SCAV) is out from the start of every raid. The side areas' own scavs are
// out on EFU_SIDE_SCAV_CHANCE percent of entries, whenever the player comes in
#define EFU_ROUTE_SCAV_CHANCE 25
#define EFU_SIDE_SCAV_CHANCE 75
#define EFU_ROUTE_SCAV_MAX 3
#define EFU_SCAV_SPAWN_DIST 6
// The same for the target and the childcare centre: the first entry rolls EFU_SIDE_SCAV_CHANCE, later ones
// EFU_ROUTE_SCAV_CHANCE
#define EFU_FLAG_TARGET_ENTERED 0xa46
#define EFU_FLAG_CHILDCARE_ENTERED 0xa47
// Set for a raid that drew downfall (EFU_DOWNFALL_CHANCE percent of them): rain, or snow in winter, wherever the sky is
// open and the zone's own weather is clear (GetDefaultWeatherValue, src/ov012/field_encount_st.c)
#define EFU_FLAG_DOWNFALL 0xa48
#define EFU_DOWNFALL_CHANCE 30
#define EFU_FLAG_SPOT_FIRST 0xa01
#define EFU_SPOT_MAX 63
#define EFU_FLAG_GARDEN_SCAV 0xa4f
// The hide flags of the item balls placed where the original had none (build_raid.py's NEW_BALLS), from this one.
// Heading out rolls every loot spot's flag again, these and the original balls' (tools/efu/loot.json)
#define EFU_FLAG_LOOT_FIRST 0xa90
// The hide flag of the scav in Route 3's childcare centre, rolled on each entry (Script_ChildcareEnter)
#define EFU_FLAG_CHILDCARE_SCAV 0xa93
// The generic scavenger who takes over the childcare centre once Billy is beaten, out by chance like the target's
#define EFU_FLAG_CHILDCARE_GENERIC 0x91e
// The inner forest's bridges: the hide flags of the Cut tree before the left one and the Strength boulder before the
// right one (build_raid.py's BRIDGE_CUT, BRIDGE_BOULDER), each put there on EFU_BRIDGE_BLOCK_CHANCE percent of
// explorations (L_DoorRoll)
#define EFU_FLAG_BRIDGE_CUT 0x91f
#define EFU_FLAG_BRIDGE_BOULDER 0x920
#define EFU_BRIDGE_BLOCK_CHANCE 70
// The hide flag of the scavenger always in the inner forest's grass patch right of the road: cleared on heading out,
// set when they are beaten
#define EFU_FLAG_FOREST_SCAV 0x921
// Floccesy Ranch's scavengers' hide flags (build_raid.py's RANCH_SPOTS), set on heading out, then each one still
// hidden comes out on an entry by chance like the target's (Script_RanchEnter); and the ranch's entered flag
#define EFU_FLAG_RANCH_SCAV_FIRST 0x922
#define EFU_RANCH_SCAV_COUNT 6
#define EFU_FLAG_RANCH_ENTERED 0x928
// Set once Burgh has been beaten: he stays gone, the guide is free, and a generic scavenger may take his place in
// Rumination Field (EFU_FLAG_RUMINATION_SCAV, out on EFU_SIDE_SCAV_CHANCE percent of explorations after)
#define EFU_FLAG_BURGH_BEATEN 0x929
#define EFU_FLAG_RUMINATION_SCAV 0x92a
// Burgh's reward, the Blank HM, which took Gram 1's place (build_bag.py)
#define EFU_ITEM_BLANK_HM ITEM_GRAM_1
// Billy's Trainer: the childcare centre's named scavenger, whose team is his own on every exploration
#define EFU_TRAINER_BILLY 401
// How many Pokémon a scavenger's team has on an exploration (Efu_ScavParty in field_encount.c)
#define EFU_SCAV_TEAM_MIN 2
#define EFU_SCAV_TEAM_MAX 5
// The slots of a zone's wild Pokémon: 12 in each of the three grass tables, 5 in each of the four water and fishing ones
#define EFU_WILD_SLOTS (12 * 3 + 5 * 4)

// EfuSpecial (script command 0x15f, Scrcmd_Efu_Special in scrcmd_field_actor.c), the hack's odd jobs by operation:
// put an item on the ground (on a tile, or with EFU_GROUND_BESIDE_PLAYER as its x on a free one of the eight around the
// player), read the bag's holdable item (efu_bag.h), add up the party's levels (eggs aside), or give each Pokémon in
// the Day Care a level, up to EFU_LEVEL_CAP (Efu_DayCareGrow in day_care.c), and the locker's jobs below
#define EFU_SPECIAL_DROP 0
#define EFU_SPECIAL_BAG_ITEM 1
#define EFU_SPECIAL_PARTY_LEVELS 2
#define EFU_SPECIAL_DAYCARE_GROW 3
// The locker (EFU_WORK_LOCKER_*): the held item of the party's Pokémon in item's place (eggs' and mail aside), or
// ITEM_NONE; taking it away; and an item's sell price, half its price
#define EFU_SPECIAL_HELD_ITEM 4
#define EFU_SPECIAL_TAKE_HELD 5
#define EFU_SPECIAL_SELL_PRICE 6
// Marks every species seen in the Pokédex, as a new game starts: the Pokédex starts complete
#define EFU_SPECIAL_FILL_POKEDEX 7
// After a win against a scavenger (Script_ScavDrop), with the Trainer in item's place and the item they drop in x's:
// they leave the area, their NPC hidden by its flag until they come out again, and the item lands where they stood
// (beside the player when they can't be found), as EFU_SPECIAL_DROP's result says
#define EFU_SPECIAL_SCAV_GONE 8
// Items on the ground: item ball actors made where an item was tossed or swapped, each holding its item in its user
// parameter 0, with actor IDs from EFU_GROUND_ID_FIRST. They belong to the zone, and are gone once the player leaves it
#define EFU_GROUND_BESIDE_PLAYER 0xffff
#define EFU_GROUND_ID_FIRST 0xc0
#define EFU_GROUND_MAX 16

// The first zone's level cap, its highest wild level (build_raid.py checks it): the Day Care raises its Pokémon to it
#define EFU_LEVEL_CAP 22
// The base's people (docs/efu.md). Nurse Joy, in Pinwheel Forest's northwest, heals for the party's total level in
// money and joins the base's Pokémon Center for EFU_JOY_HIRE; the clerk, in its waiting area, tells the player what
// happened the first time and runs its Poké Mart after, at the normal prices (EFU_MART_SHOP_ID's
// list, Nacrene's mail counter in the original, shops.json); the Day Care lady, in Route 3's Day Care, moves into the
// player's warehouse once the scav in the childcare centre next door is beaten (EFU_FLAG_DAYCARE_QUEST_DONE), and from
// there each Pokémon left with her gains a level each raid
#define EFU_JOY_HIRE 1000
#define EFU_MART_SHOP_ID 2
// Set once each has joined the base (the original NPC's hide flag), and the hide flags of their base NPCs, which the
// base's init scripts set from those (Script_PokecenInit, Script_HomeInit)
#define EFU_FLAG_JOY_JOINED 0xa94
#define EFU_FLAG_BASE_JOY_HIDDEN 0xa95
#define EFU_FLAG_CLERK_MET 0xa96
#define EFU_FLAG_BASE_CLERK_HIDDEN 0xa97
#define EFU_FLAG_DAYCARE_JOINED 0xa98
#define EFU_FLAG_BASE_DAYCARE_HIDDEN 0xa99
// Set while the Day Care Lady's original script (global 2201) runs for her Route 3 NPC (Script_DayCareJoin), where it
// leaves Withdraw out of its menu: she only takes Pokémon in there (build_raid.py patches global_2200.s)
#define EFU_FLAG_DAYCARE_DEPOSIT_ONLY 0xa43
// Set once the scav in Route 3's childcare centre (trainer 401) has been beaten: the Day Care Lady's quest
#define EFU_FLAG_DAYCARE_QUEST_DONE 0xa44
// The shut door in the Day Care Lady's warehouse's doorway (build_coast.py): its field prop (door_normal01 of
// FIELD_PROPS_EXTERIOR_SHARED_PC_01_3) and its place in its chunk (overworld_2_map20_18), which
// FieldPropSystem_InstantiateFromInfo leaves out once EFU_FLAG_DAYCARE_JOINED is set. Each closed warehouse has one
#define EFU_DAYCARE_DOOR_PROP 259
#define EFU_DAYCARE_DOOR_PROP_X (-112)
#define EFU_DAYCARE_DOOR_PROP_Z 84
// Her warehouse's two doors, Nacrene's warps (build_base.py), which lead nowhere until she has joined (GetWarpForWalkIn
// in fieldmap_event.c): a sign on each says the door is locked (Script_DayCareDoor)
#define EFU_DAYCARE_WARP 2
#define EFU_DAYCARE_UPPER_WARP 8
// Each world editor lock's flag, set once it is opened (EFU_SCRIPT_LOCK_FIRST), EFU_LOCK_COUNT of them
#define EFU_FLAG_LOCK_FIRST 0x92b
// The guide, met out in the zone (their NPC's hide flag there), and their NPC's hide flag at the east gate, which its
// init script sets from that (Script_GateInit)
#define EFU_FLAG_GUIDE_MET 0xa9e
#define EFU_FLAG_BASE_GUIDE_HIDDEN 0xa9f

// Doors that are shut on some explorations: each has a boulder in front of it, hidden by its flag from this one
// (build_raid.py's DOORS, in their order), which heading out rolls (L_DoorRoll): shut on EFU_DOOR_SHUT_CHANCE percent
#define EFU_FLAG_DOOR_FIRST 0xa9a
#define EFU_DOOR_COUNT 3
#define EFU_DOOR_SHUT_CHANCE 30
// The target's scavs, each hidden by its flag from this one and out on EFU_SIDE_SCAV_CHANCE percent of entries
#define EFU_FLAG_TARGET_SCAV_FIRST 0xa40
#define EFU_TARGET_SCAV_COUNT 3

// Fleeing (btl_server_flow.c): the original's cap on the escape attempts it counts, and the count that means the
// player failed to get away this turn and gets away at its end
#define EFU_ESCAPE_ATTEMPTS_MAX 30
#define EFU_ESCAPE_PENDING (EFU_ESCAPE_ATTEMPTS_MAX + 1)

#endif // POKEBW2_EFU_H
