#ifndef POKEBW2_EFU_H
#define POKEBW2_EFU_H

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
#define EFU_SCRIPT_LAST (EFU_SCRIPT_FIRST + 99)

// Saved event work values the original game never uses, so a save keeps them across builds (docs/efu.md). Only ever
// add new ones from the free list there; never move or reuse one
// Whether the player is out on a raid: set and saved on leaving through the east gate, cleared and saved on coming
// back. A save that is continued with it set was left mid-raid, and the raid counts as lost
#define EFU_WORK_RAID 0x41ac
// The save format's version, set on a new game. A later build that changes what the hack keeps in the save checks it
// on continuing and upgrades the old save
#define EFU_WORK_SAVE_VERSION 0x41ad
#define EFU_SAVE_VERSION 1

#endif // POKEBW2_EFU_H
