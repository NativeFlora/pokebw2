#include "asm/field_script.inc"
#include "text/script/efu.h"
#include "efu.h"

// Escape from Unova's own script commands (EVCMD_TABLE in src/ov012/scrcmd_vm.c, from 0x2f3; each also needs
// a row of EVCMD_PERM_TABLE in src/ov012/script_sys.c)
    .macro EfuPokePartyRecoverHalf
    FieldCommand 0x2f3
    .endm
// Empties the party (0x2db, which was UnityTowerSetFloor; Scrcmd_Efu_PokePartyClear in src/ov036/scrcmd_leaves.c)
    .macro EfuPokePartyClear
    FieldCommand 0x2db
    .endm
// Escape from Unova's own scripts, global IDs from 11000 (EFU_SCRIPT_* in include/efu.h)
    ScriptEntry Script_NewGameSetup
    ScriptEntry Script_NewGameStart
    ScriptEntry Script_BoardedDoor
    ScriptEntry Script_Bed
    ScriptEntry Script_RaidDepart
    ScriptEntry Script_RaidReturn
    ScriptEntry Script_RaidLost
    ScriptEntry Script_Blackout
    ScriptEntry Script_LootRoute
    ScriptEntry Script_LootCave
    ScriptEntry Script_LootTarget
    ScriptEntry Script_ScavDrop
    ScriptEntriesEnd

// Runs before the first fade-in of a new game
Script_NewGameSetup:
    ActorsPauseAll
    WorkSetConst EFU_WORK_SAVE_VERSION, EFU_SAVE_VERSION
    GiveRunningShoes
    FinishAllEvents
    ActorsUnpauseAll
    VMHalt

// Runs after the first fade-in of a new game: a lost Pokémon finds the player
Script_NewGameStart:
    ActorsPauseAll
    SystemMsg Efu_Text_Wake, 2
    LastKeyWait
    VMCall L_LostSoul
    SystemMsgClose
    FinishAllEvents
    ActorsUnpauseAll
    VMHalt

// A boarded-up door of a closed building
Script_BoardedDoor:
    ActorsPauseAll
    SystemMsg Efu_Text_BoardedDoor, 2
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// The player's bed: a poor Pokémon Center that brings the party up to half HP and PP
Script_Bed:
    ActorsPauseAll
    SystemMsg Efu_Text_BedRest, 2
    YesNoWin 0x8010
    WorkCmpConst 0x8010, 1
    VMJumpIf CMP_EQ, L_BedNo
    SystemMsgClose
    FadeEx 3, 0, 16, 2
    FadeExWait
    EfuPokePartyRecoverHalf
    MEPlay SEQ_ME_ASA
    MEWait
    FadeEx 3, 16, 0, 2
    FadeExWait
    SystemMsg Efu_Text_BedRested, 2
    LastKeyWait
L_BedNo:
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// Stepping up to Route 3's door in the east gate, while not out on a raid. Leaving saves first, with the raid marked, so
// switching the game off before coming back loses the raid (Script_RaidLost)
Script_RaidDepart:
    ActorsPauseAll
    PokePartyGetCount 0x8010, 2
    WorkCmpConst 0x8010, 0
    VMJumpIf CMP_EQ, L_RaidNoTeam
    SystemMsg Efu_Text_RaidDepart, 2
    YesNoWin 0x8011
    WorkCmpConst 0x8011, 1
    VMJumpIf CMP_EQ, L_RaidStay
    WorkSetConst EFU_WORK_RAID, 1
    // The season moves on with each raid (EFU_SEASON), when the player steps out onto the route
    WorkAdd EFU_WORK_RAID_COUNT, 1
    // Saves from before version 2 started without them
    GiveRunningShoes
    // The scavs hide until the exploration has gone on a while (EventTrainerEye_EfuPursue brings them out), and the
    // clock for that starts at the first step out
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    FlagSet EFU_FLAG_SCAV_FIRST + \i
    .endr
    WorkSetConst EFU_WORK_EXPLORE_START, 0
    WorkSetConst EFU_WORK_SCAVS_OUT, 0
    // New loot: each spot's item ball is out or not by its tier's chance (L_LootRoll, from loot.json)
    VMCall L_LootRoll
    WorkSetConst EFU_WORK_SAVE_VERSION, EFU_SAVE_VERSION
    SystemMsg Efu_Text_Saving, 2
    SaveDataWrite 0x8010
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

L_RaidNoTeam:
    SystemMsg Efu_Text_RaidNoTeam, 2
    LastKeyWait
L_RaidStay:
    SystemMsgClose
    ActorCmdExec 255, Movement_StepBackWest
    ActorCmdWait
    ActorsUnpauseAll
    VMHalt

    // Movement data is read as aligned halfwords
    .balign 4, 0
Movement_StepBackWest:
    Move 14, 1
    MoveEnd

// Stepping up to Nacrene's door in the east gate while out on a raid: home, and saved
Script_RaidReturn:
    ActorsPauseAll
    WorkSetConst EFU_WORK_RAID, 0
    SystemMsg Efu_Text_RaidReturn, 2
    SystemMsg Efu_Text_Saving, 2
    SaveDataWrite 0x8010
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// Continuing a save left mid-raid: the raid is lost, and the party with it (emptied by EventFieldContinue_Callback
// before this runs), once the field has faded in
Script_RaidLost:
    ActorsPauseAll
    WorkSetConst EFU_WORK_RAID, 0
    EfuPokePartyClear
    SystemMsg Efu_Text_RaidLost, 2
    LastKeyWait
    VMCall L_LostSoul
    SystemMsg Efu_Text_Saving, 2
    SaveDataWrite 0x8010
    SystemMsgClose
    ActorsUnpauseAll
    MapChangeWarp ZONE_NACRENE_CITY_8, 3, 3, 1
    VMHalt

// Blacking out, once FieldMapControl_LoadBlackoutZone has brought the player home: the team is gone, the raid is
// over, a new Pokémon turns up, and the game saves
Script_Blackout:
    ActorsPauseAll
    WorkSetConst EFU_WORK_RAID, 0
    EfuPokePartyClear
    // The battle lost left the screen black (event_battle_lose.c), and the field shows nothing until it fades in
    FadeInBlackQ
    FadeWait
    SystemMsg Efu_Text_Blackout, 2
    LastKeyWait
    VMCall L_LostSoul
    SystemMsg Efu_Text_Saving, 2
    SaveDataWrite 0x8010
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// With the party empty: a random Pokémon from the starter pool (tools/efu/starters.py), as lost as the player, joins
L_LostSoul:
    Random 0x8020, 210
L_LostSoulPick:
    WorkCmpConst 0x8020, 105
    VMJumpIf CMP_GE, L_LostSoulPick_H
L_LostSoulPick_L:
    WorkCmpConst 0x8020, 52
    VMJumpIf CMP_GE, L_LostSoulPick_L_H
L_LostSoulPick_L_L:
    WorkCmpConst 0x8020, 26
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H
L_LostSoulPick_L_L_L:
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H
L_LostSoulPick_L_L_L_L:
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H
L_LostSoulPick_L_L_L_L_L:
    WorkCmpConst 0x8020, 3
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_L_H
L_LostSoulPick_L_L_L_L_L_L:
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_L_L_H
L_LostSoulPick_L_L_L_L_L_L_L:
    WorkSetConst 0x8025, 1
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_L_L_H:
    WorkCmpConst 0x8020, 2
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_L_L_H_H
L_LostSoulPick_L_L_L_L_L_L_H_L:
    WorkSetConst 0x8025, 4
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_L_L_H_H:
    WorkSetConst 0x8025, 7
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_L_H:
    WorkCmpConst 0x8020, 4
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_L_H_H
L_LostSoulPick_L_L_L_L_L_H_L:
    WorkSetConst 0x8025, 10
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_L_H_H:
    WorkCmpConst 0x8020, 5
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_L_H_H_H
L_LostSoulPick_L_L_L_L_L_H_H_L:
    WorkSetConst 0x8025, 13
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_L_H_H_H:
    WorkSetConst 0x8025, 16
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H:
    WorkCmpConst 0x8020, 9
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H_H
L_LostSoulPick_L_L_L_L_H_L:
    WorkCmpConst 0x8020, 7
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H_L_H
L_LostSoulPick_L_L_L_L_H_L_L:
    WorkSetConst 0x8025, 19
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H_L_H:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H_L_H_H
L_LostSoulPick_L_L_L_L_H_L_H_L:
    WorkSetConst 0x8025, 21
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H_L_H_H:
    WorkSetConst 0x8025, 23
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H_H:
    WorkCmpConst 0x8020, 11
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H_H_H
L_LostSoulPick_L_L_L_L_H_H_L:
    WorkCmpConst 0x8020, 10
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H_H_L_H
L_LostSoulPick_L_L_L_L_H_H_L_L:
    WorkSetConst 0x8025, 25
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H_H_L_H:
    WorkSetConst 0x8025, 27
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H_H_H:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_L_H_H_H_H
L_LostSoulPick_L_L_L_L_H_H_H_L:
    WorkSetConst 0x8025, 29
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_L_H_H_H_H:
    WorkSetConst 0x8025, 32
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H:
    WorkCmpConst 0x8020, 19
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H
L_LostSoulPick_L_L_L_H_L:
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_L_H
L_LostSoulPick_L_L_L_H_L_L:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_L_L_H
L_LostSoulPick_L_L_L_H_L_L_L:
    WorkSetConst 0x8025, 35
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_L_L_H:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_L_L_H_H
L_LostSoulPick_L_L_L_H_L_L_H_L:
    WorkSetConst 0x8025, 37
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_L_L_H_H:
    WorkSetConst 0x8025, 39
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_L_H:
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_L_H_H
L_LostSoulPick_L_L_L_H_L_H_L:
    WorkSetConst 0x8025, 41
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_L_H_H:
    WorkCmpConst 0x8020, 18
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_L_H_H_H
L_LostSoulPick_L_L_L_H_L_H_H_L:
    WorkSetConst 0x8025, 43
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_L_H_H_H:
    WorkSetConst 0x8025, 46
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H:
    WorkCmpConst 0x8020, 22
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H_H
L_LostSoulPick_L_L_L_H_H_L:
    WorkCmpConst 0x8020, 20
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H_L_H
L_LostSoulPick_L_L_L_H_H_L_L:
    WorkSetConst 0x8025, 48
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H_L_H:
    WorkCmpConst 0x8020, 21
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H_L_H_H
L_LostSoulPick_L_L_L_H_H_L_H_L:
    WorkSetConst 0x8025, 50
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H_L_H_H:
    WorkSetConst 0x8025, 52
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H_H:
    WorkCmpConst 0x8020, 24
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H_H_H
L_LostSoulPick_L_L_L_H_H_H_L:
    WorkCmpConst 0x8020, 23
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H_H_L_H
L_LostSoulPick_L_L_L_H_H_H_L_L:
    WorkSetConst 0x8025, 54
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H_H_L_H:
    WorkSetConst 0x8025, 56
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H_H_H:
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_L_H_H_H_H_H
L_LostSoulPick_L_L_L_H_H_H_H_L:
    WorkSetConst 0x8025, 58
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_L_H_H_H_H_H:
    WorkSetConst 0x8025, 60
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H:
    WorkCmpConst 0x8020, 39
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H
L_LostSoulPick_L_L_H_L:
    WorkCmpConst 0x8020, 32
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H
L_LostSoulPick_L_L_H_L_L:
    WorkCmpConst 0x8020, 29
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_L_H
L_LostSoulPick_L_L_H_L_L_L:
    WorkCmpConst 0x8020, 27
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_L_L_H
L_LostSoulPick_L_L_H_L_L_L_L:
    WorkSetConst 0x8025, 63
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_L_L_H:
    WorkCmpConst 0x8020, 28
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_L_L_H_H
L_LostSoulPick_L_L_H_L_L_L_H_L:
    WorkSetConst 0x8025, 66
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_L_L_H_H:
    WorkSetConst 0x8025, 69
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_L_H:
    WorkCmpConst 0x8020, 30
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_L_H_H
L_LostSoulPick_L_L_H_L_L_H_L:
    WorkSetConst 0x8025, 72
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_L_H_H:
    WorkCmpConst 0x8020, 31
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_L_H_H_H
L_LostSoulPick_L_L_H_L_L_H_H_L:
    WorkSetConst 0x8025, 74
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_L_H_H_H:
    WorkSetConst 0x8025, 77
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H:
    WorkCmpConst 0x8020, 35
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H_H
L_LostSoulPick_L_L_H_L_H_L:
    WorkCmpConst 0x8020, 33
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H_L_H
L_LostSoulPick_L_L_H_L_H_L_L:
    WorkSetConst 0x8025, 79
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H_L_H:
    WorkCmpConst 0x8020, 34
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H_L_H_H
L_LostSoulPick_L_L_H_L_H_L_H_L:
    WorkSetConst 0x8025, 81
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H_L_H_H:
    WorkSetConst 0x8025, 84
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H_H:
    WorkCmpConst 0x8020, 37
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H_H_H
L_LostSoulPick_L_L_H_L_H_H_L:
    WorkCmpConst 0x8020, 36
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H_H_L_H
L_LostSoulPick_L_L_H_L_H_H_L_L:
    WorkSetConst 0x8025, 86
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H_H_L_H:
    WorkSetConst 0x8025, 88
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H_H_H:
    WorkCmpConst 0x8020, 38
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_L_H_H_H_H
L_LostSoulPick_L_L_H_L_H_H_H_L:
    WorkSetConst 0x8025, 90
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_L_H_H_H_H:
    WorkSetConst 0x8025, 92
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H:
    WorkCmpConst 0x8020, 45
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H
L_LostSoulPick_L_L_H_H_L:
    WorkCmpConst 0x8020, 42
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_L_H
L_LostSoulPick_L_L_H_H_L_L:
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_L_L_H
L_LostSoulPick_L_L_H_H_L_L_L:
    WorkSetConst 0x8025, 95
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_L_L_H:
    WorkCmpConst 0x8020, 41
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_L_L_H_H
L_LostSoulPick_L_L_H_H_L_L_H_L:
    WorkSetConst 0x8025, 96
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_L_L_H_H:
    WorkSetConst 0x8025, 98
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_L_H:
    WorkCmpConst 0x8020, 43
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_L_H_H
L_LostSoulPick_L_L_H_H_L_H_L:
    WorkSetConst 0x8025, 100
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_L_H_H:
    WorkCmpConst 0x8020, 44
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_L_H_H_H
L_LostSoulPick_L_L_H_H_L_H_H_L:
    WorkSetConst 0x8025, 102
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_L_H_H_H:
    WorkSetConst 0x8025, 104
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H:
    WorkCmpConst 0x8020, 48
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H_H
L_LostSoulPick_L_L_H_H_H_L:
    WorkCmpConst 0x8020, 46
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H_L_H
L_LostSoulPick_L_L_H_H_H_L_L:
    WorkSetConst 0x8025, 108
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H_L_H:
    WorkCmpConst 0x8020, 47
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H_L_H_H
L_LostSoulPick_L_L_H_H_H_L_H_L:
    WorkSetConst 0x8025, 109
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H_L_H_H:
    WorkSetConst 0x8025, 111
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H_H:
    WorkCmpConst 0x8020, 50
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H_H_H
L_LostSoulPick_L_L_H_H_H_H_L:
    WorkCmpConst 0x8020, 49
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H_H_L_H
L_LostSoulPick_L_L_H_H_H_H_L_L:
    WorkSetConst 0x8025, 113
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H_H_L_H:
    WorkSetConst 0x8025, 114
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H_H_H:
    WorkCmpConst 0x8020, 51
    VMJumpIf CMP_GE, L_LostSoulPick_L_L_H_H_H_H_H_H
L_LostSoulPick_L_L_H_H_H_H_H_L:
    WorkSetConst 0x8025, 116
    VMJump L_LostSoulFound
L_LostSoulPick_L_L_H_H_H_H_H_H:
    WorkSetConst 0x8025, 118
    VMJump L_LostSoulFound
L_LostSoulPick_L_H:
    WorkCmpConst 0x8020, 78
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H
L_LostSoulPick_L_H_L:
    WorkCmpConst 0x8020, 65
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H
L_LostSoulPick_L_H_L_L:
    WorkCmpConst 0x8020, 58
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H
L_LostSoulPick_L_H_L_L_L:
    WorkCmpConst 0x8020, 55
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_L_H
L_LostSoulPick_L_H_L_L_L_L:
    WorkCmpConst 0x8020, 53
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_L_L_H
L_LostSoulPick_L_H_L_L_L_L_L:
    WorkSetConst 0x8025, 120
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_L_L_H:
    WorkCmpConst 0x8020, 54
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_L_L_H_H
L_LostSoulPick_L_H_L_L_L_L_H_L:
    WorkSetConst 0x8025, 123
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_L_L_H_H:
    WorkSetConst 0x8025, 125
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_L_H:
    WorkCmpConst 0x8020, 56
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_L_H_H
L_LostSoulPick_L_H_L_L_L_H_L:
    WorkSetConst 0x8025, 126
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_L_H_H:
    WorkCmpConst 0x8020, 57
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_L_H_H_H
L_LostSoulPick_L_H_L_L_L_H_H_L:
    WorkSetConst 0x8025, 129
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_L_H_H_H:
    WorkSetConst 0x8025, 133
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H:
    WorkCmpConst 0x8020, 61
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H_H
L_LostSoulPick_L_H_L_L_H_L:
    WorkCmpConst 0x8020, 59
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H_L_H
L_LostSoulPick_L_H_L_L_H_L_L:
    WorkSetConst 0x8025, 137
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H_L_H:
    WorkCmpConst 0x8020, 60
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H_L_H_H
L_LostSoulPick_L_H_L_L_H_L_H_L:
    WorkSetConst 0x8025, 138
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H_L_H_H:
    WorkSetConst 0x8025, 140
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H_H:
    WorkCmpConst 0x8020, 63
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H_H_H
L_LostSoulPick_L_H_L_L_H_H_L:
    WorkCmpConst 0x8020, 62
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H_H_L_H
L_LostSoulPick_L_H_L_L_H_H_L_L:
    WorkSetConst 0x8025, 152
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H_H_L_H:
    WorkSetConst 0x8025, 155
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H_H_H:
    WorkCmpConst 0x8020, 64
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_L_H_H_H_H
L_LostSoulPick_L_H_L_L_H_H_H_L:
    WorkSetConst 0x8025, 158
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_L_H_H_H_H:
    WorkSetConst 0x8025, 161
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H:
    WorkCmpConst 0x8020, 71
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H
L_LostSoulPick_L_H_L_H_L:
    WorkCmpConst 0x8020, 68
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_L_H
L_LostSoulPick_L_H_L_H_L_L:
    WorkCmpConst 0x8020, 66
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_L_L_H
L_LostSoulPick_L_H_L_H_L_L_L:
    WorkSetConst 0x8025, 163
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_L_L_H:
    WorkCmpConst 0x8020, 67
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_L_L_H_H
L_LostSoulPick_L_H_L_H_L_L_H_L:
    WorkSetConst 0x8025, 165
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_L_L_H_H:
    WorkSetConst 0x8025, 167
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_L_H:
    WorkCmpConst 0x8020, 69
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_L_H_H
L_LostSoulPick_L_H_L_H_L_H_L:
    WorkSetConst 0x8025, 170
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_L_H_H:
    WorkCmpConst 0x8020, 70
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_L_H_H_H
L_LostSoulPick_L_H_L_H_L_H_H_L:
    WorkSetConst 0x8025, 176
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_L_H_H_H:
    WorkSetConst 0x8025, 177
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H:
    WorkCmpConst 0x8020, 74
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H_H
L_LostSoulPick_L_H_L_H_H_L:
    WorkCmpConst 0x8020, 72
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H_L_H
L_LostSoulPick_L_H_L_H_H_L_L:
    WorkSetConst 0x8025, 179
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H_L_H:
    WorkCmpConst 0x8020, 73
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H_L_H_H
L_LostSoulPick_L_H_L_H_H_L_H_L:
    WorkSetConst 0x8025, 183
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H_L_H_H:
    WorkSetConst 0x8025, 187
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H_H:
    WorkCmpConst 0x8020, 76
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H_H_H
L_LostSoulPick_L_H_L_H_H_H_L:
    WorkCmpConst 0x8020, 75
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H_H_L_H
L_LostSoulPick_L_H_L_H_H_H_L_L:
    WorkSetConst 0x8025, 190
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H_H_L_H:
    WorkSetConst 0x8025, 191
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H_H_H:
    WorkCmpConst 0x8020, 77
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_L_H_H_H_H_H
L_LostSoulPick_L_H_L_H_H_H_H_L:
    WorkSetConst 0x8025, 193
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_L_H_H_H_H_H:
    WorkSetConst 0x8025, 194
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H:
    WorkCmpConst 0x8020, 91
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H
L_LostSoulPick_L_H_H_L:
    WorkCmpConst 0x8020, 84
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H
L_LostSoulPick_L_H_H_L_L:
    WorkCmpConst 0x8020, 81
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_L_H
L_LostSoulPick_L_H_H_L_L_L:
    WorkCmpConst 0x8020, 79
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_L_L_H
L_LostSoulPick_L_H_H_L_L_L_L:
    WorkSetConst 0x8025, 198
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_L_L_H:
    WorkCmpConst 0x8020, 80
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_L_L_H_H
L_LostSoulPick_L_H_H_L_L_L_H_L:
    WorkSetConst 0x8025, 200
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_L_L_H_H:
    WorkSetConst 0x8025, 204
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_L_H:
    WorkCmpConst 0x8020, 82
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_L_H_H
L_LostSoulPick_L_H_H_L_L_H_L:
    WorkSetConst 0x8025, 207
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_L_H_H:
    WorkCmpConst 0x8020, 83
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_L_H_H_H
L_LostSoulPick_L_H_H_L_L_H_H_L:
    WorkSetConst 0x8025, 209
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_L_H_H_H:
    WorkSetConst 0x8025, 215
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H:
    WorkCmpConst 0x8020, 87
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H_H
L_LostSoulPick_L_H_H_L_H_L:
    WorkCmpConst 0x8020, 85
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H_L_H
L_LostSoulPick_L_H_H_L_H_L_L:
    WorkSetConst 0x8025, 216
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H_L_H:
    WorkCmpConst 0x8020, 86
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H_L_H_H
L_LostSoulPick_L_H_H_L_H_L_H_L:
    WorkSetConst 0x8025, 218
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H_L_H_H:
    WorkSetConst 0x8025, 220
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H_H:
    WorkCmpConst 0x8020, 89
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H_H_H
L_LostSoulPick_L_H_H_L_H_H_L:
    WorkCmpConst 0x8020, 88
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H_H_L_H
L_LostSoulPick_L_H_H_L_H_H_L_L:
    WorkSetConst 0x8025, 223
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H_H_L_H:
    WorkSetConst 0x8025, 228
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H_H_H:
    WorkCmpConst 0x8020, 90
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_L_H_H_H_H
L_LostSoulPick_L_H_H_L_H_H_H_L:
    WorkSetConst 0x8025, 231
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_L_H_H_H_H:
    WorkSetConst 0x8025, 252
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H:
    WorkCmpConst 0x8020, 98
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H
L_LostSoulPick_L_H_H_H_L:
    WorkCmpConst 0x8020, 94
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_L_H
L_LostSoulPick_L_H_H_H_L_L:
    WorkCmpConst 0x8020, 92
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_L_L_H
L_LostSoulPick_L_H_H_H_L_L_L:
    WorkSetConst 0x8025, 255
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_L_L_H:
    WorkCmpConst 0x8020, 93
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_L_L_H_H
L_LostSoulPick_L_H_H_H_L_L_H_L:
    WorkSetConst 0x8025, 258
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_L_L_H_H:
    WorkSetConst 0x8025, 261
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_L_H:
    WorkCmpConst 0x8020, 96
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_L_H_H
L_LostSoulPick_L_H_H_H_L_H_L:
    WorkCmpConst 0x8020, 95
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_L_H_L_H
L_LostSoulPick_L_H_H_H_L_H_L_L:
    WorkSetConst 0x8025, 263
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_L_H_L_H:
    WorkSetConst 0x8025, 265
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_L_H_H:
    WorkCmpConst 0x8020, 97
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_L_H_H_H
L_LostSoulPick_L_H_H_H_L_H_H_L:
    WorkSetConst 0x8025, 270
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_L_H_H_H:
    WorkSetConst 0x8025, 273
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H:
    WorkCmpConst 0x8020, 101
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H_H
L_LostSoulPick_L_H_H_H_H_L:
    WorkCmpConst 0x8020, 99
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H_L_H
L_LostSoulPick_L_H_H_H_H_L_L:
    WorkSetConst 0x8025, 276
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H_L_H:
    WorkCmpConst 0x8020, 100
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H_L_H_H
L_LostSoulPick_L_H_H_H_H_L_H_L:
    WorkSetConst 0x8025, 278
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H_L_H_H:
    WorkSetConst 0x8025, 280
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H_H:
    WorkCmpConst 0x8020, 103
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H_H_H
L_LostSoulPick_L_H_H_H_H_H_L:
    WorkCmpConst 0x8020, 102
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H_H_L_H
L_LostSoulPick_L_H_H_H_H_H_L_L:
    WorkSetConst 0x8025, 283
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H_H_L_H:
    WorkSetConst 0x8025, 285
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H_H_H:
    WorkCmpConst 0x8020, 104
    VMJumpIf CMP_GE, L_LostSoulPick_L_H_H_H_H_H_H_H
L_LostSoulPick_L_H_H_H_H_H_H_L:
    WorkSetConst 0x8025, 287
    VMJump L_LostSoulFound
L_LostSoulPick_L_H_H_H_H_H_H_H:
    WorkSetConst 0x8025, 290
    VMJump L_LostSoulFound
L_LostSoulPick_H:
    WorkCmpConst 0x8020, 157
    VMJumpIf CMP_GE, L_LostSoulPick_H_H
L_LostSoulPick_H_L:
    WorkCmpConst 0x8020, 131
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H
L_LostSoulPick_H_L_L:
    WorkCmpConst 0x8020, 118
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H
L_LostSoulPick_H_L_L_L:
    WorkCmpConst 0x8020, 111
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H
L_LostSoulPick_H_L_L_L_L:
    WorkCmpConst 0x8020, 108
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_L_H
L_LostSoulPick_H_L_L_L_L_L:
    WorkCmpConst 0x8020, 106
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_L_L_H
L_LostSoulPick_H_L_L_L_L_L_L:
    WorkSetConst 0x8025, 293
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_L_L_H:
    WorkCmpConst 0x8020, 107
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_L_L_H_H
L_LostSoulPick_H_L_L_L_L_L_H_L:
    WorkSetConst 0x8025, 296
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_L_L_H_H:
    WorkSetConst 0x8025, 299
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_L_H:
    WorkCmpConst 0x8020, 109
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_L_H_H
L_LostSoulPick_H_L_L_L_L_H_L:
    WorkSetConst 0x8025, 300
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_L_H_H:
    WorkCmpConst 0x8020, 110
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_L_H_H_H
L_LostSoulPick_H_L_L_L_L_H_H_L:
    WorkSetConst 0x8025, 304
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_L_H_H_H:
    WorkSetConst 0x8025, 307
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H:
    WorkCmpConst 0x8020, 114
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H_H
L_LostSoulPick_H_L_L_L_H_L:
    WorkCmpConst 0x8020, 112
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H_L_H
L_LostSoulPick_H_L_L_L_H_L_L:
    WorkSetConst 0x8025, 309
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H_L_H:
    WorkCmpConst 0x8020, 113
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H_L_H_H
L_LostSoulPick_H_L_L_L_H_L_H_L:
    WorkSetConst 0x8025, 315
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H_L_H_H:
    WorkSetConst 0x8025, 316
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H_H:
    WorkCmpConst 0x8020, 116
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H_H_H
L_LostSoulPick_H_L_L_L_H_H_L:
    WorkCmpConst 0x8020, 115
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H_H_L_H
L_LostSoulPick_H_L_L_L_H_H_L_L:
    WorkSetConst 0x8025, 318
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H_H_L_H:
    WorkSetConst 0x8025, 320
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H_H_H:
    WorkCmpConst 0x8020, 117
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_L_H_H_H_H
L_LostSoulPick_H_L_L_L_H_H_H_L:
    WorkSetConst 0x8025, 322
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_L_H_H_H_H:
    WorkSetConst 0x8025, 325
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H:
    WorkCmpConst 0x8020, 124
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H
L_LostSoulPick_H_L_L_H_L:
    WorkCmpConst 0x8020, 121
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_L_H
L_LostSoulPick_H_L_L_H_L_L:
    WorkCmpConst 0x8020, 119
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_L_L_H
L_LostSoulPick_H_L_L_H_L_L_L:
    WorkSetConst 0x8025, 328
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_L_L_H:
    WorkCmpConst 0x8020, 120
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_L_L_H_H
L_LostSoulPick_H_L_L_H_L_L_H_L:
    WorkSetConst 0x8025, 331
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_L_L_H_H:
    WorkSetConst 0x8025, 333
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_L_H:
    WorkCmpConst 0x8020, 122
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_L_H_H
L_LostSoulPick_H_L_L_H_L_H_L:
    WorkSetConst 0x8025, 339
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_L_H_H:
    WorkCmpConst 0x8020, 123
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_L_H_H_H
L_LostSoulPick_H_L_L_H_L_H_H_L:
    WorkSetConst 0x8025, 341
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_L_H_H_H:
    WorkSetConst 0x8025, 343
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H:
    WorkCmpConst 0x8020, 127
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H_H
L_LostSoulPick_H_L_L_H_H_L:
    WorkCmpConst 0x8020, 125
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H_L_H
L_LostSoulPick_H_L_L_H_H_L_L:
    WorkSetConst 0x8025, 345
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H_L_H:
    WorkCmpConst 0x8020, 126
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H_L_H_H
L_LostSoulPick_H_L_L_H_H_L_H_L:
    WorkSetConst 0x8025, 347
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H_L_H_H:
    WorkSetConst 0x8025, 349
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H_H:
    WorkCmpConst 0x8020, 129
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H_H_H
L_LostSoulPick_H_L_L_H_H_H_L:
    WorkCmpConst 0x8020, 128
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H_H_L_H
L_LostSoulPick_H_L_L_H_H_H_L_L:
    WorkSetConst 0x8025, 353
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H_H_L_H:
    WorkSetConst 0x8025, 355
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H_H_H:
    WorkCmpConst 0x8020, 130
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_L_H_H_H_H_H
L_LostSoulPick_H_L_L_H_H_H_H_L:
    WorkSetConst 0x8025, 361
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_L_H_H_H_H_H:
    WorkSetConst 0x8025, 363
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H:
    WorkCmpConst 0x8020, 144
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H
L_LostSoulPick_H_L_H_L:
    WorkCmpConst 0x8020, 137
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H
L_LostSoulPick_H_L_H_L_L:
    WorkCmpConst 0x8020, 134
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_L_H
L_LostSoulPick_H_L_H_L_L_L:
    WorkCmpConst 0x8020, 132
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_L_L_H
L_LostSoulPick_H_L_H_L_L_L_L:
    WorkSetConst 0x8025, 366
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_L_L_H:
    WorkCmpConst 0x8020, 133
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_L_L_H_H
L_LostSoulPick_H_L_H_L_L_L_H_L:
    WorkSetConst 0x8025, 387
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_L_L_H_H:
    WorkSetConst 0x8025, 390
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_L_H:
    WorkCmpConst 0x8020, 135
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_L_H_H
L_LostSoulPick_H_L_H_L_L_H_L:
    WorkSetConst 0x8025, 393
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_L_H_H:
    WorkCmpConst 0x8020, 136
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_L_H_H_H
L_LostSoulPick_H_L_H_L_L_H_H_L:
    WorkSetConst 0x8025, 396
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_L_H_H_H:
    WorkSetConst 0x8025, 399
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H:
    WorkCmpConst 0x8020, 140
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H_H
L_LostSoulPick_H_L_H_L_H_L:
    WorkCmpConst 0x8020, 138
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H_L_H
L_LostSoulPick_H_L_H_L_H_L_L:
    WorkSetConst 0x8025, 401
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H_L_H:
    WorkCmpConst 0x8020, 139
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H_L_H_H
L_LostSoulPick_H_L_H_L_H_L_H_L:
    WorkSetConst 0x8025, 403
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H_L_H_H:
    WorkSetConst 0x8025, 408
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H_H:
    WorkCmpConst 0x8020, 142
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H_H_H
L_LostSoulPick_H_L_H_L_H_H_L:
    WorkCmpConst 0x8020, 141
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H_H_L_H
L_LostSoulPick_H_L_H_L_H_H_L_L:
    WorkSetConst 0x8025, 410
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H_H_L_H:
    WorkSetConst 0x8025, 412
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H_H_H:
    WorkCmpConst 0x8020, 143
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_L_H_H_H_H
L_LostSoulPick_H_L_H_L_H_H_H_L:
    WorkSetConst 0x8025, 415
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_L_H_H_H_H:
    WorkSetConst 0x8025, 418
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H:
    WorkCmpConst 0x8020, 150
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H
L_LostSoulPick_H_L_H_H_L:
    WorkCmpConst 0x8020, 147
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_L_H
L_LostSoulPick_H_L_H_H_L_L:
    WorkCmpConst 0x8020, 145
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_L_L_H
L_LostSoulPick_H_L_H_H_L_L_L:
    WorkSetConst 0x8025, 420
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_L_L_H:
    WorkCmpConst 0x8020, 146
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_L_L_H_H
L_LostSoulPick_H_L_H_H_L_L_H_L:
    WorkSetConst 0x8025, 422
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_L_L_H_H:
    WorkSetConst 0x8025, 425
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_L_H:
    WorkCmpConst 0x8020, 148
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_L_H_H
L_LostSoulPick_H_L_H_H_L_H_L:
    WorkSetConst 0x8025, 427
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_L_H_H:
    WorkCmpConst 0x8020, 149
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_L_H_H_H
L_LostSoulPick_H_L_H_H_L_H_H_L:
    WorkSetConst 0x8025, 431
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_L_H_H_H:
    WorkSetConst 0x8025, 434
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H:
    WorkCmpConst 0x8020, 153
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H_H
L_LostSoulPick_H_L_H_H_H_L:
    WorkCmpConst 0x8020, 151
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H_L_H
L_LostSoulPick_H_L_H_H_H_L_L:
    WorkSetConst 0x8025, 436
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H_L_H:
    WorkCmpConst 0x8020, 152
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H_L_H_H
L_LostSoulPick_H_L_H_H_H_L_H_L:
    WorkSetConst 0x8025, 449
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H_L_H_H:
    WorkSetConst 0x8025, 451
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H_H:
    WorkCmpConst 0x8020, 155
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H_H_H
L_LostSoulPick_H_L_H_H_H_H_L:
    WorkCmpConst 0x8020, 154
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H_H_L_H
L_LostSoulPick_H_L_H_H_H_H_L_L:
    WorkSetConst 0x8025, 453
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H_H_L_H:
    WorkSetConst 0x8025, 456
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H_H_H:
    WorkCmpConst 0x8020, 156
    VMJumpIf CMP_GE, L_LostSoulPick_H_L_H_H_H_H_H_H
L_LostSoulPick_H_L_H_H_H_H_H_L:
    WorkSetConst 0x8025, 459
    VMJump L_LostSoulFound
L_LostSoulPick_H_L_H_H_H_H_H_H:
    WorkSetConst 0x8025, 495
    VMJump L_LostSoulFound
L_LostSoulPick_H_H:
    WorkCmpConst 0x8020, 183
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H
L_LostSoulPick_H_H_L:
    WorkCmpConst 0x8020, 170
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H
L_LostSoulPick_H_H_L_L:
    WorkCmpConst 0x8020, 163
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H
L_LostSoulPick_H_H_L_L_L:
    WorkCmpConst 0x8020, 160
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_L_H
L_LostSoulPick_H_H_L_L_L_L:
    WorkCmpConst 0x8020, 158
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_L_L_H
L_LostSoulPick_H_H_L_L_L_L_L:
    WorkSetConst 0x8025, 498
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_L_L_H:
    WorkCmpConst 0x8020, 159
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_L_L_H_H
L_LostSoulPick_H_H_L_L_L_L_H_L:
    WorkSetConst 0x8025, 501
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_L_L_H_H:
    WorkSetConst 0x8025, 504
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_L_H:
    WorkCmpConst 0x8020, 161
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_L_H_H
L_LostSoulPick_H_H_L_L_L_H_L:
    WorkSetConst 0x8025, 506
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_L_H_H:
    WorkCmpConst 0x8020, 162
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_L_H_H_H
L_LostSoulPick_H_H_L_L_L_H_H_L:
    WorkSetConst 0x8025, 509
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_L_H_H_H:
    WorkSetConst 0x8025, 511
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H:
    WorkCmpConst 0x8020, 166
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H_H
L_LostSoulPick_H_H_L_L_H_L:
    WorkCmpConst 0x8020, 164
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H_L_H
L_LostSoulPick_H_H_L_L_H_L_L:
    WorkSetConst 0x8025, 513
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H_L_H:
    WorkCmpConst 0x8020, 165
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H_L_H_H
L_LostSoulPick_H_H_L_L_H_L_H_L:
    WorkSetConst 0x8025, 515
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H_L_H_H:
    WorkSetConst 0x8025, 517
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H_H:
    WorkCmpConst 0x8020, 168
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H_H_H
L_LostSoulPick_H_H_L_L_H_H_L:
    WorkCmpConst 0x8020, 167
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H_H_L_H
L_LostSoulPick_H_H_L_L_H_H_L_L:
    WorkSetConst 0x8025, 519
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H_H_L_H:
    WorkSetConst 0x8025, 522
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H_H_H:
    WorkCmpConst 0x8020, 169
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_L_H_H_H_H
L_LostSoulPick_H_H_L_L_H_H_H_L:
    WorkSetConst 0x8025, 524
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_L_H_H_H_H:
    WorkSetConst 0x8025, 527
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H:
    WorkCmpConst 0x8020, 176
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H
L_LostSoulPick_H_H_L_H_L:
    WorkCmpConst 0x8020, 173
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_L_H
L_LostSoulPick_H_H_L_H_L_L:
    WorkCmpConst 0x8020, 171
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_L_L_H
L_LostSoulPick_H_H_L_H_L_L_L:
    WorkSetConst 0x8025, 529
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_L_L_H:
    WorkCmpConst 0x8020, 172
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_L_L_H_H
L_LostSoulPick_H_H_L_H_L_L_H_L:
    WorkSetConst 0x8025, 532
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_L_L_H_H:
    WorkSetConst 0x8025, 535
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_L_H:
    WorkCmpConst 0x8020, 174
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_L_H_H
L_LostSoulPick_H_H_L_H_L_H_L:
    WorkSetConst 0x8025, 540
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_L_H_H:
    WorkCmpConst 0x8020, 175
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_L_H_H_H
L_LostSoulPick_H_H_L_H_L_H_H_L:
    WorkSetConst 0x8025, 543
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_L_H_H_H:
    WorkSetConst 0x8025, 546
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H:
    WorkCmpConst 0x8020, 179
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H_H
L_LostSoulPick_H_H_L_H_H_L:
    WorkCmpConst 0x8020, 177
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H_L_H
L_LostSoulPick_H_H_L_H_H_L_L:
    WorkSetConst 0x8025, 548
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H_L_H:
    WorkCmpConst 0x8020, 178
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H_L_H_H
L_LostSoulPick_H_H_L_H_H_L_H_L:
    WorkSetConst 0x8025, 551
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H_L_H_H:
    WorkSetConst 0x8025, 554
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H_H:
    WorkCmpConst 0x8020, 181
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H_H_H
L_LostSoulPick_H_H_L_H_H_H_L:
    WorkCmpConst 0x8020, 180
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H_H_L_H
L_LostSoulPick_H_H_L_H_H_H_L_L:
    WorkSetConst 0x8025, 557
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H_H_L_H:
    WorkSetConst 0x8025, 559
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H_H_H:
    WorkCmpConst 0x8020, 182
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_L_H_H_H_H_H
L_LostSoulPick_H_H_L_H_H_H_H_L:
    WorkSetConst 0x8025, 562
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_L_H_H_H_H_H:
    WorkSetConst 0x8025, 564
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H:
    WorkCmpConst 0x8020, 196
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H
L_LostSoulPick_H_H_H_L:
    WorkCmpConst 0x8020, 189
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H
L_LostSoulPick_H_H_H_L_L:
    WorkCmpConst 0x8020, 186
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_L_H
L_LostSoulPick_H_H_H_L_L_L:
    WorkCmpConst 0x8020, 184
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_L_L_H
L_LostSoulPick_H_H_H_L_L_L_L:
    WorkSetConst 0x8025, 566
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_L_L_H:
    WorkCmpConst 0x8020, 185
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_L_L_H_H
L_LostSoulPick_H_H_H_L_L_L_H_L:
    WorkSetConst 0x8025, 568
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_L_L_H_H:
    WorkSetConst 0x8025, 570
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_L_H:
    WorkCmpConst 0x8020, 187
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_L_H_H
L_LostSoulPick_H_H_H_L_L_H_L:
    WorkSetConst 0x8025, 572
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_L_H_H:
    WorkCmpConst 0x8020, 188
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_L_H_H_H
L_LostSoulPick_H_H_H_L_L_H_H_L:
    WorkSetConst 0x8025, 574
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_L_H_H_H:
    WorkSetConst 0x8025, 577
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H:
    WorkCmpConst 0x8020, 192
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H_H
L_LostSoulPick_H_H_H_L_H_L:
    WorkCmpConst 0x8020, 190
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H_L_H
L_LostSoulPick_H_H_H_L_H_L_L:
    WorkSetConst 0x8025, 580
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H_L_H:
    WorkCmpConst 0x8020, 191
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H_L_H_H
L_LostSoulPick_H_H_H_L_H_L_H_L:
    WorkSetConst 0x8025, 582
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H_L_H_H:
    WorkSetConst 0x8025, 585
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H_H:
    WorkCmpConst 0x8020, 194
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H_H_H
L_LostSoulPick_H_H_H_L_H_H_L:
    WorkCmpConst 0x8020, 193
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H_H_L_H
L_LostSoulPick_H_H_H_L_H_H_L_L:
    WorkSetConst 0x8025, 588
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H_H_L_H:
    WorkSetConst 0x8025, 590
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H_H_H:
    WorkCmpConst 0x8020, 195
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_L_H_H_H_H
L_LostSoulPick_H_H_H_L_H_H_H_L:
    WorkSetConst 0x8025, 592
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_L_H_H_H_H:
    WorkSetConst 0x8025, 595
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H:
    WorkCmpConst 0x8020, 203
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H
L_LostSoulPick_H_H_H_H_L:
    WorkCmpConst 0x8020, 199
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_L_H
L_LostSoulPick_H_H_H_H_L_L:
    WorkCmpConst 0x8020, 197
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_L_L_H
L_LostSoulPick_H_H_H_H_L_L_L:
    WorkSetConst 0x8025, 597
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_L_L_H:
    WorkCmpConst 0x8020, 198
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_L_L_H_H
L_LostSoulPick_H_H_H_H_L_L_H_L:
    WorkSetConst 0x8025, 599
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_L_L_H_H:
    WorkSetConst 0x8025, 602
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_L_H:
    WorkCmpConst 0x8020, 201
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_L_H_H
L_LostSoulPick_H_H_H_H_L_H_L:
    WorkCmpConst 0x8020, 200
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_L_H_L_H
L_LostSoulPick_H_H_H_H_L_H_L_L:
    WorkSetConst 0x8025, 605
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_L_H_L_H:
    WorkSetConst 0x8025, 607
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_L_H_H:
    WorkCmpConst 0x8020, 202
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_L_H_H_H
L_LostSoulPick_H_H_H_H_L_H_H_L:
    WorkSetConst 0x8025, 610
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_L_H_H_H:
    WorkSetConst 0x8025, 613
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H:
    WorkCmpConst 0x8020, 206
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H_H
L_LostSoulPick_H_H_H_H_H_L:
    WorkCmpConst 0x8020, 204
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H_L_H
L_LostSoulPick_H_H_H_H_H_L_L:
    WorkSetConst 0x8025, 616
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H_L_H:
    WorkCmpConst 0x8020, 205
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H_L_H_H
L_LostSoulPick_H_H_H_H_H_L_H_L:
    WorkSetConst 0x8025, 619
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H_L_H_H:
    WorkSetConst 0x8025, 622
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H_H:
    WorkCmpConst 0x8020, 208
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H_H_H
L_LostSoulPick_H_H_H_H_H_H_L:
    WorkCmpConst 0x8020, 207
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H_H_L_H
L_LostSoulPick_H_H_H_H_H_H_L_L:
    WorkSetConst 0x8025, 624
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H_H_L_H:
    WorkSetConst 0x8025, 627
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H_H_H:
    WorkCmpConst 0x8020, 209
    VMJumpIf CMP_GE, L_LostSoulPick_H_H_H_H_H_H_H_H
L_LostSoulPick_H_H_H_H_H_H_H_L:
    WorkSetConst 0x8025, 629
    VMJump L_LostSoulFound
L_LostSoulPick_H_H_H_H_H_H_H_H:
    WorkSetConst 0x8025, 636
    VMJump L_LostSoulFound
L_LostSoulFound:
    WordSetPokeSpecies 1, 0x8025
    PokePartyAdd 0x8010, 0x8025, 0, EFU_LOST_SOUL_LEVEL
    FlagSet EVENT_FLAG_0x0961
    MEPlay SEQ_ME_POKEGET
    SystemMsg Efu_Text_LostSoul, 2
    MEWait
    LastKeyWait
    VMReturn

L_ChooseStarter:
    SystemMsg Efu_Text_WhichType, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Type_Normal_I, 65535, 0
    ListMenuAdd Efu_Text_Type_Normal_II, 65535, 1
    ListMenuAdd Efu_Text_Type_Fire, 65535, 2
    ListMenuAdd Efu_Text_Type_Water_I, 65535, 3
    ListMenuAdd Efu_Text_Type_Water_II, 65535, 4
    ListMenuAdd Efu_Text_Type_Grass, 65535, 5
    ListMenuAdd Efu_Text_Type_Electric, 65535, 6
    ListMenuAdd Efu_Text_Type_Ice, 65535, 7
    ListMenuAdd Efu_Text_Type_Fighting, 65535, 8
    ListMenuAdd Efu_Text_Type_Poison, 65535, 9
    ListMenuAdd Efu_Text_Type_Ground, 65535, 10
    ListMenuAdd Efu_Text_Type_Psychic, 65535, 11
    ListMenuAdd Efu_Text_Type_Bug, 65535, 12
    ListMenuAdd Efu_Text_Type_Rock, 65535, 13
    ListMenuAdd Efu_Text_Type_Ghost, 65535, 14
    ListMenuAdd Efu_Text_Type_Dragon, 65535, 15
    ListMenuAdd Efu_Text_Type_Dark, 65535, 16
    ListMenuAdd Efu_Text_Type_Steel, 65535, 17
    ListMenuShow
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_Page_0
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_Page_1
    WorkCmpConst 0x8020, 2
    VMJumpIf CMP_EQ, L_Page_2
    WorkCmpConst 0x8020, 3
    VMJumpIf CMP_EQ, L_Page_3
    WorkCmpConst 0x8020, 4
    VMJumpIf CMP_EQ, L_Page_4
    WorkCmpConst 0x8020, 5
    VMJumpIf CMP_EQ, L_Page_5
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_EQ, L_Page_6
    WorkCmpConst 0x8020, 7
    VMJumpIf CMP_EQ, L_Page_7
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_EQ, L_Page_8
    WorkCmpConst 0x8020, 9
    VMJumpIf CMP_EQ, L_Page_9
    WorkCmpConst 0x8020, 10
    VMJumpIf CMP_EQ, L_Page_10
    WorkCmpConst 0x8020, 11
    VMJumpIf CMP_EQ, L_Page_11
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_EQ, L_Page_12
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_EQ, L_Page_13
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_EQ, L_Page_14
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_EQ, L_Page_15
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_EQ, L_Page_16
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_EQ, L_Page_17
    VMJump L_ChooseStarter

L_Page_0:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Pidgey, 65535, 16
    ListMenuAdd Efu_Text_Sp_Rattata, 65535, 19
    ListMenuAdd Efu_Text_Sp_Spearow, 65535, 21
    ListMenuAdd Efu_Text_Sp_Clefairy, 65535, 35
    ListMenuAdd Efu_Text_Sp_Jigglypuff, 65535, 39
    ListMenuAdd Efu_Text_Sp_Meowth, 65535, 52
    ListMenuAdd Efu_Text_Sp_Doduo, 65535, 84
    ListMenuAdd Efu_Text_Sp_Lickitung, 65535, 108
    ListMenuAdd Efu_Text_Sp_Chansey, 65535, 113
    ListMenuAdd Efu_Text_Sp_Eevee, 65535, 133
    ListMenuAdd Efu_Text_Sp_Porygon, 65535, 137
    ListMenuAdd Efu_Text_Sp_Sentret, 65535, 161
    ListMenuAdd Efu_Text_Sp_Hoothoot, 65535, 163
    ListMenuAdd Efu_Text_Sp_Togetic, 65535, 176
    ListMenuAdd Efu_Text_Sp_Aipom, 65535, 190
    ListMenuAdd Efu_Text_Sp_Snubbull, 65535, 209
    ListMenuAdd Efu_Text_Sp_Teddiursa, 65535, 216
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_1:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Zigzagoon, 65535, 263
    ListMenuAdd Efu_Text_Sp_Taillow, 65535, 276
    ListMenuAdd Efu_Text_Sp_Slakoth, 65535, 287
    ListMenuAdd Efu_Text_Sp_Whismur, 65535, 293
    ListMenuAdd Efu_Text_Sp_Skitty, 65535, 300
    ListMenuAdd Efu_Text_Sp_Swablu, 65535, 333
    ListMenuAdd Efu_Text_Sp_Starly, 65535, 396
    ListMenuAdd Efu_Text_Sp_Bidoof, 65535, 399
    ListMenuAdd Efu_Text_Sp_Buneary, 65535, 427
    ListMenuAdd Efu_Text_Sp_Glameow, 65535, 431
    ListMenuAdd Efu_Text_Sp_Patrat, 65535, 504
    ListMenuAdd Efu_Text_Sp_Lillipup, 65535, 506
    ListMenuAdd Efu_Text_Sp_Pidove, 65535, 519
    ListMenuAdd Efu_Text_Sp_Minccino, 65535, 572
    ListMenuAdd Efu_Text_Sp_Deerling, 65535, 585
    ListMenuAdd Efu_Text_Sp_Rufflet, 65535, 627
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_2:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Charmander, 65535, 4
    ListMenuAdd Efu_Text_Sp_Vulpix, 65535, 37
    ListMenuAdd Efu_Text_Sp_Growlithe, 65535, 58
    ListMenuAdd Efu_Text_Sp_Ponyta, 65535, 77
    ListMenuAdd Efu_Text_Sp_Magmar, 65535, 126
    ListMenuAdd Efu_Text_Sp_Cyndaquil, 65535, 155
    ListMenuAdd Efu_Text_Sp_Slugma, 65535, 218
    ListMenuAdd Efu_Text_Sp_Torchic, 65535, 255
    ListMenuAdd Efu_Text_Sp_Numel, 65535, 322
    ListMenuAdd Efu_Text_Sp_Chimchar, 65535, 390
    ListMenuAdd Efu_Text_Sp_Tepig, 65535, 498
    ListMenuAdd Efu_Text_Sp_Pansear, 65535, 513
    ListMenuAdd Efu_Text_Sp_Darumaka, 65535, 554
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_3:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Squirtle, 65535, 7
    ListMenuAdd Efu_Text_Sp_Psyduck, 65535, 54
    ListMenuAdd Efu_Text_Sp_Poliwag, 65535, 60
    ListMenuAdd Efu_Text_Sp_Tentacool, 65535, 72
    ListMenuAdd Efu_Text_Sp_Slowpoke, 65535, 79
    ListMenuAdd Efu_Text_Sp_Seel, 65535, 86
    ListMenuAdd Efu_Text_Sp_Shellder, 65535, 90
    ListMenuAdd Efu_Text_Sp_Krabby, 65535, 98
    ListMenuAdd Efu_Text_Sp_Horsea, 65535, 116
    ListMenuAdd Efu_Text_Sp_Goldeen, 65535, 118
    ListMenuAdd Efu_Text_Sp_Staryu, 65535, 120
    ListMenuAdd Efu_Text_Sp_Magikarp, 65535, 129
    ListMenuAdd Efu_Text_Sp_Totodile, 65535, 158
    ListMenuAdd Efu_Text_Sp_Chinchou, 65535, 170
    ListMenuAdd Efu_Text_Sp_Marill, 65535, 183
    ListMenuAdd Efu_Text_Sp_Wooper, 65535, 194
    ListMenuAdd Efu_Text_Sp_Remoraid, 65535, 223
    ListMenuAdd Efu_Text_Sp_Mudkip, 65535, 258
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_4:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Lotad, 65535, 270
    ListMenuAdd Efu_Text_Sp_Wingull, 65535, 278
    ListMenuAdd Efu_Text_Sp_Carvanha, 65535, 318
    ListMenuAdd Efu_Text_Sp_Wailmer, 65535, 320
    ListMenuAdd Efu_Text_Sp_Barboach, 65535, 339
    ListMenuAdd Efu_Text_Sp_Corphish, 65535, 341
    ListMenuAdd Efu_Text_Sp_Feebas, 65535, 349
    ListMenuAdd Efu_Text_Sp_Clamperl, 65535, 366
    ListMenuAdd Efu_Text_Sp_Piplup, 65535, 393
    ListMenuAdd Efu_Text_Sp_Buizel, 65535, 418
    ListMenuAdd Efu_Text_Sp_Shellos, 65535, 422
    ListMenuAdd Efu_Text_Sp_Finneon, 65535, 456
    ListMenuAdd Efu_Text_Sp_Oshawott, 65535, 501
    ListMenuAdd Efu_Text_Sp_Panpour, 65535, 515
    ListMenuAdd Efu_Text_Sp_Tympole, 65535, 535
    ListMenuAdd Efu_Text_Sp_Tirtouga, 65535, 564
    ListMenuAdd Efu_Text_Sp_Ducklett, 65535, 580
    ListMenuAdd Efu_Text_Sp_Frillish, 65535, 592
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_5:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Bulbasaur, 65535, 1
    ListMenuAdd Efu_Text_Sp_Oddish, 65535, 43
    ListMenuAdd Efu_Text_Sp_Bellsprout, 65535, 69
    ListMenuAdd Efu_Text_Sp_Exeggcute, 65535, 102
    ListMenuAdd Efu_Text_Sp_Tangela, 65535, 114
    ListMenuAdd Efu_Text_Sp_Chikorita, 65535, 152
    ListMenuAdd Efu_Text_Sp_Hoppip, 65535, 187
    ListMenuAdd Efu_Text_Sp_Sunkern, 65535, 191
    ListMenuAdd Efu_Text_Sp_Treecko, 65535, 252
    ListMenuAdd Efu_Text_Sp_Seedot, 65535, 273
    ListMenuAdd Efu_Text_Sp_Shroomish, 65535, 285
    ListMenuAdd Efu_Text_Sp_Roselia, 65535, 315
    ListMenuAdd Efu_Text_Sp_Cacnea, 65535, 331
    ListMenuAdd Efu_Text_Sp_Turtwig, 65535, 387
    ListMenuAdd Efu_Text_Sp_Cherubi, 65535, 420
    ListMenuAdd Efu_Text_Sp_Snover, 65535, 459
    ListMenuAdd Efu_Text_Sp_Snivy, 65535, 495
    ListMenuAdd Efu_Text_Sp_Pansage, 65535, 511
    ListMenuAdd Efu_Text_Sp_Cottonee, 65535, 546
    ListMenuAdd Efu_Text_Sp_Petilil, 65535, 548
    ListMenuAdd Efu_Text_Sp_Foongus, 65535, 590
    ListMenuAdd Efu_Text_Sp_Ferroseed, 65535, 597
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_6:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Pikachu, 65535, 25
    ListMenuAdd Efu_Text_Sp_Magnemite, 65535, 81
    ListMenuAdd Efu_Text_Sp_Voltorb, 65535, 100
    ListMenuAdd Efu_Text_Sp_Electabuzz, 65535, 125
    ListMenuAdd Efu_Text_Sp_Mareep, 65535, 179
    ListMenuAdd Efu_Text_Sp_Electrike, 65535, 309
    ListMenuAdd Efu_Text_Sp_Shinx, 65535, 403
    ListMenuAdd Efu_Text_Sp_Blitzle, 65535, 522
    ListMenuAdd Efu_Text_Sp_Tynamo, 65535, 602
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_7:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Swinub, 65535, 220
    ListMenuAdd Efu_Text_Sp_Snorunt, 65535, 361
    ListMenuAdd Efu_Text_Sp_Spheal, 65535, 363
    ListMenuAdd Efu_Text_Sp_Vanillite, 65535, 582
    ListMenuAdd Efu_Text_Sp_Cubchoo, 65535, 613
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_8:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Mankey, 65535, 56
    ListMenuAdd Efu_Text_Sp_Machop, 65535, 66
    ListMenuAdd Efu_Text_Sp_Makuhita, 65535, 296
    ListMenuAdd Efu_Text_Sp_Meditite, 65535, 307
    ListMenuAdd Efu_Text_Sp_Timburr, 65535, 532
    ListMenuAdd Efu_Text_Sp_Mienfoo, 65535, 619
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_9:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Ekans, 65535, 23
    ListMenuAdd Efu_Text_Sp_NidoranF, 65535, 29
    ListMenuAdd Efu_Text_Sp_NidoranM, 65535, 32
    ListMenuAdd Efu_Text_Sp_Zubat, 65535, 41
    ListMenuAdd Efu_Text_Sp_Grimer, 65535, 88
    ListMenuAdd Efu_Text_Sp_Koffing, 65535, 109
    ListMenuAdd Efu_Text_Sp_Gulpin, 65535, 316
    ListMenuAdd Efu_Text_Sp_Stunky, 65535, 434
    ListMenuAdd Efu_Text_Sp_Skorupi, 65535, 451
    ListMenuAdd Efu_Text_Sp_Croagunk, 65535, 453
    ListMenuAdd Efu_Text_Sp_Trubbish, 65535, 568
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_10:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Sandshrew, 65535, 27
    ListMenuAdd Efu_Text_Sp_Diglett, 65535, 50
    ListMenuAdd Efu_Text_Sp_Cubone, 65535, 104
    ListMenuAdd Efu_Text_Sp_Rhyhorn, 65535, 111
    ListMenuAdd Efu_Text_Sp_Gligar, 65535, 207
    ListMenuAdd Efu_Text_Sp_Phanpy, 65535, 231
    ListMenuAdd Efu_Text_Sp_Trapinch, 65535, 328
    ListMenuAdd Efu_Text_Sp_Baltoy, 65535, 343
    ListMenuAdd Efu_Text_Sp_Hippopotas, 65535, 449
    ListMenuAdd Efu_Text_Sp_Drilbur, 65535, 529
    ListMenuAdd Efu_Text_Sp_Sandile, 65535, 551
    ListMenuAdd Efu_Text_Sp_Golett, 65535, 622
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_11:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Abra, 65535, 63
    ListMenuAdd Efu_Text_Sp_Drowzee, 65535, 96
    ListMenuAdd Efu_Text_Sp_Natu, 65535, 177
    ListMenuAdd Efu_Text_Sp_Ralts, 65535, 280
    ListMenuAdd Efu_Text_Sp_Spoink, 65535, 325
    ListMenuAdd Efu_Text_Sp_Munna, 65535, 517
    ListMenuAdd Efu_Text_Sp_Woobat, 65535, 527
    ListMenuAdd Efu_Text_Sp_Gothita, 65535, 574
    ListMenuAdd Efu_Text_Sp_Solosis, 65535, 577
    ListMenuAdd Efu_Text_Sp_Elgyem, 65535, 605
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_12:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Caterpie, 65535, 10
    ListMenuAdd Efu_Text_Sp_Weedle, 65535, 13
    ListMenuAdd Efu_Text_Sp_Paras, 65535, 46
    ListMenuAdd Efu_Text_Sp_Venonat, 65535, 48
    ListMenuAdd Efu_Text_Sp_Scyther, 65535, 123
    ListMenuAdd Efu_Text_Sp_Ledyba, 65535, 165
    ListMenuAdd Efu_Text_Sp_Spinarak, 65535, 167
    ListMenuAdd Efu_Text_Sp_Yanma, 65535, 193
    ListMenuAdd Efu_Text_Sp_Pineco, 65535, 204
    ListMenuAdd Efu_Text_Sp_Wurmple, 65535, 265
    ListMenuAdd Efu_Text_Sp_Surskit, 65535, 283
    ListMenuAdd Efu_Text_Sp_Nincada, 65535, 290
    ListMenuAdd Efu_Text_Sp_Kricketot, 65535, 401
    ListMenuAdd Efu_Text_Sp_Burmy, 65535, 412
    ListMenuAdd Efu_Text_Sp_Combee, 65535, 415
    ListMenuAdd Efu_Text_Sp_Sewaddle, 65535, 540
    ListMenuAdd Efu_Text_Sp_Venipede, 65535, 543
    ListMenuAdd Efu_Text_Sp_Dwebble, 65535, 557
    ListMenuAdd Efu_Text_Sp_Karrablast, 65535, 588
    ListMenuAdd Efu_Text_Sp_Joltik, 65535, 595
    ListMenuAdd Efu_Text_Sp_Shelmet, 65535, 616
    ListMenuAdd Efu_Text_Sp_Larvesta, 65535, 636
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_13:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Geodude, 65535, 74
    ListMenuAdd Efu_Text_Sp_Onix, 65535, 95
    ListMenuAdd Efu_Text_Sp_Omanyte, 65535, 138
    ListMenuAdd Efu_Text_Sp_Kabuto, 65535, 140
    ListMenuAdd Efu_Text_Sp_Nosepass, 65535, 299
    ListMenuAdd Efu_Text_Sp_Lileep, 65535, 345
    ListMenuAdd Efu_Text_Sp_Anorith, 65535, 347
    ListMenuAdd Efu_Text_Sp_Cranidos, 65535, 408
    ListMenuAdd Efu_Text_Sp_Shieldon, 65535, 410
    ListMenuAdd Efu_Text_Sp_Roggenrola, 65535, 524
    ListMenuAdd Efu_Text_Sp_Archen, 65535, 566
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_14:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Gastly, 65535, 92
    ListMenuAdd Efu_Text_Sp_Misdreavus, 65535, 200
    ListMenuAdd Efu_Text_Sp_Shuppet, 65535, 353
    ListMenuAdd Efu_Text_Sp_Duskull, 65535, 355
    ListMenuAdd Efu_Text_Sp_Drifloon, 65535, 425
    ListMenuAdd Efu_Text_Sp_Yamask, 65535, 562
    ListMenuAdd Efu_Text_Sp_Litwick, 65535, 607
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_15:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Axew, 65535, 610
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_16:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Murkrow, 65535, 198
    ListMenuAdd Efu_Text_Sp_Sneasel, 65535, 215
    ListMenuAdd Efu_Text_Sp_Houndour, 65535, 228
    ListMenuAdd Efu_Text_Sp_Poochyena, 65535, 261
    ListMenuAdd Efu_Text_Sp_Purrloin, 65535, 509
    ListMenuAdd Efu_Text_Sp_Scraggy, 65535, 559
    ListMenuAdd Efu_Text_Sp_Zorua, 65535, 570
    ListMenuAdd Efu_Text_Sp_Pawniard, 65535, 624
    ListMenuAdd Efu_Text_Sp_Vullaby, 65535, 629
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter

L_Page_17:
    SystemMsg Efu_Text_WhichOne, 2
    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020
    ListMenuAdd Efu_Text_Sp_Aron, 65535, 304
    ListMenuAdd Efu_Text_Sp_Bronzor, 65535, 436
    ListMenuAdd Efu_Text_Sp_Klink, 65535, 599
    ListMenuAdd Efu_Text_Back, 65535, 0
    ListMenuShow
    VMJump L_ConfirmStarter
// 0x8020 is the species, or 0 (Back) or more than any species (B)
L_ConfirmStarter:
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_ChooseStarter
    WorkCmpConst 0x8020, 650
    VMJumpIf CMP_GE, L_ChooseStarter
    WorkSet 0x8025, 0x8020
    WordSetPokeSpecies 1, 0x8025
    SystemMsg Efu_Text_ThisOne, 2
    YesNoWin 0x8010
    WorkCmpConst 0x8010, 1
    VMJumpIf CMP_EQ, L_ChooseStarter
    PokePartyAdd 0x8010, 0x8025, 0, 5
    FlagSet EVENT_FLAG_0x0961
    MEPlay SEQ_ME_POKEGET
    SystemMsg Efu_Text_StayedWithYou, 2
    MEWait
    LastKeyWait
    VMReturn
    .balign 4, 0

// Picking up loot: what the ball holds is rolled from its tier's table (gen_efu.py's LOOT), and the item ball script
// of the original (global 7400, which the original balls call with their item) gives it and hides the ball by its flag
Script_LootRoute:
    ActorsPauseAll
    ItemCheckSpace 4, 1, 0x800c
    WorkCmpConst 0x800c, 0
    VMJumpIf CMP_EQ, L_LootNoRoom
    VMCall L_LootPickRoute
    VMJump L_LootGive

Script_LootCave:
    ActorsPauseAll
    ItemCheckSpace 4, 1, 0x800c
    WorkCmpConst 0x800c, 0
    VMJumpIf CMP_EQ, L_LootNoRoom
    VMCall L_LootPickCave
    VMJump L_LootGive

Script_LootTarget:
    ActorsPauseAll
    ItemCheckSpace 4, 1, 0x800c
    WorkCmpConst 0x800c, 0
    VMJumpIf CMP_EQ, L_LootNoRoom
    VMCall L_LootPickTarget
L_LootGive:
    WorkSetConst 0x800d, 1
    RTCallGlobal 7400
    FinishAllEvents
    ActorsUnpauseAll
    VMHalt

// The one-item bag (include/efu_bag.h): each loot script asks first, and with the bag's item already carried, the
// ball stays shut, so what it holds is rolled only when it can be taken (every loot item can be held, so a Poke Ball
// stands for them all)
L_LootNoRoom:
    SystemMsg Efu_Text_LootNoRoom, 2
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// After a win against a scav (global_3000.s calls it): it drops an item from the target's table, which the player takes
// if the bag has room
Script_ScavDrop:
    VMCall L_LootPickTarget
    WordSetItemNameEx 0, 0x800c, 1, 0
    ItemCheckSpace 0x800c, 1, 0x8010
    WorkCmpConst 0x8010, 0
    VMJumpIf CMP_EQ, L_ScavDropFull
    ItemAdd 0x800c, 1, 0x8010
    MEPlay SEQ_ME_ITEM
    SystemMsg Efu_Text_ScavDrop, 2
    MEWait
    LastKeyWait
    SystemMsgClose
    RTEndGlobal
    VMHalt

L_ScavDropFull:
    SystemMsg Efu_Text_ScavDropFull, 2
    LastKeyWait
    SystemMsgClose
    RTEndGlobal
    VMHalt

L_LootPickRoute:
    Random 0x8020, 22
L_LootPickRoute_:
    WorkCmpConst 0x8020, 11
    VMJumpIf CMP_GE, L_LootPickRoute__H
L_LootPickRoute__L:
    WorkCmpConst 0x8020, 5
    VMJumpIf CMP_GE, L_LootPickRoute__L_H
L_LootPickRoute__L_L:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootPickRoute__L_H:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootPickRoute__L_H_H
L_LootPickRoute__L_H_L:
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_GE, L_LootPickRoute__L_H_L_H
L_LootPickRoute__L_H_L_L:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootPickRoute__L_H_L_H:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickRoute__L_H_H:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickRoute__H:
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_GE, L_LootPickRoute__H_H
L_LootPickRoute__H_L:
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_GE, L_LootPickRoute__H_L_H
L_LootPickRoute__H_L_L:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootPickRoute__H_L_L_H
L_LootPickRoute__H_L_L_L:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickRoute__H_L_L_H:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootPickRoute__H_L_H:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LootPickRoute__H_L_H_H
L_LootPickRoute__H_L_H_L:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootPickRoute__H_L_H_H:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootPickRoute__H_L_H_H_H
L_LootPickRoute__H_L_H_H_L:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootPickRoute__H_L_H_H_H:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootPickRoute__H_H:
    WorkCmpConst 0x8020, 19
    VMJumpIf CMP_GE, L_LootPickRoute__H_H_H
L_LootPickRoute__H_H_L:
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_GE, L_LootPickRoute__H_H_L_H
L_LootPickRoute__H_H_L_L:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootPickRoute__H_H_L_H:
    WorkCmpConst 0x8020, 18
    VMJumpIf CMP_GE, L_LootPickRoute__H_H_L_H_H
L_LootPickRoute__H_H_L_H_L:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootPickRoute__H_H_L_H_H:
    WorkSetConst 0x800c, 149
    VMReturn
L_LootPickRoute__H_H_H:
    WorkCmpConst 0x8020, 20
    VMJumpIf CMP_GE, L_LootPickRoute__H_H_H_H
L_LootPickRoute__H_H_H_L:
    WorkSetConst 0x800c, 151
    VMReturn
L_LootPickRoute__H_H_H_H:
    WorkCmpConst 0x8020, 21
    VMJumpIf CMP_GE, L_LootPickRoute__H_H_H_H_H
L_LootPickRoute__H_H_H_H_L:
    WorkSetConst 0x800c, 152
    VMReturn
L_LootPickRoute__H_H_H_H_H:
    WorkSetConst 0x800c, 18
    VMReturn
L_LootPickCave:
    Random 0x8020, 19
L_LootPickCave_:
    WorkCmpConst 0x8020, 9
    VMJumpIf CMP_GE, L_LootPickCave__H
L_LootPickCave__L:
    WorkCmpConst 0x8020, 4
    VMJumpIf CMP_GE, L_LootPickCave__L_H
L_LootPickCave__L_L:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootPickCave__L_H:
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_GE, L_LootPickCave__L_H_H
L_LootPickCave__L_H_L:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickCave__L_H_H:
    WorkCmpConst 0x8020, 7
    VMJumpIf CMP_GE, L_LootPickCave__L_H_H_H
L_LootPickCave__L_H_H_L:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickCave__L_H_H_H:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootPickCave__L_H_H_H_H
L_LootPickCave__L_H_H_H_L:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickCave__L_H_H_H_H:
    WorkSetConst 0x800c, 88
    VMReturn
L_LootPickCave__H:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LootPickCave__H_H
L_LootPickCave__H_L:
    WorkCmpConst 0x8020, 11
    VMJumpIf CMP_GE, L_LootPickCave__H_L_H
L_LootPickCave__H_L_L:
    WorkSetConst 0x800c, 88
    VMReturn
L_LootPickCave__H_L_H:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootPickCave__H_L_H_H
L_LootPickCave__H_L_H_L:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootPickCave__H_L_H_H:
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_GE, L_LootPickCave__H_L_H_H_H
L_LootPickCave__H_L_H_H_L:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootPickCave__H_L_H_H_H:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootPickCave__H_H:
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_GE, L_LootPickCave__H_H_H
L_LootPickCave__H_H_L:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootPickCave__H_H_L_H
L_LootPickCave__H_H_L_L:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootPickCave__H_H_L_H:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootPickCave__H_H_H:
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_GE, L_LootPickCave__H_H_H_H
L_LootPickCave__H_H_H_L:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootPickCave__H_H_H_H:
    WorkCmpConst 0x8020, 18
    VMJumpIf CMP_GE, L_LootPickCave__H_H_H_H_H
L_LootPickCave__H_H_H_H_L:
    WorkSetConst 0x800c, 3
    VMReturn
L_LootPickCave__H_H_H_H_H:
    WorkSetConst 0x800c, 92
    VMReturn
L_LootPickTarget:
    Random 0x8020, 17
L_LootPickTarget_:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootPickTarget__H
L_LootPickTarget__L:
    WorkCmpConst 0x8020, 4
    VMJumpIf CMP_GE, L_LootPickTarget__L_H
L_LootPickTarget__L_L:
    WorkCmpConst 0x8020, 2
    VMJumpIf CMP_GE, L_LootPickTarget__L_L_H
L_LootPickTarget__L_L_L:
    WorkSetConst 0x800c, 88
    VMReturn
L_LootPickTarget__L_L_H:
    WorkCmpConst 0x8020, 3
    VMJumpIf CMP_GE, L_LootPickTarget__L_L_H_H
L_LootPickTarget__L_L_H_L:
    WorkSetConst 0x800c, 88
    VMReturn
L_LootPickTarget__L_L_H_H:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootPickTarget__L_H:
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_GE, L_LootPickTarget__L_H_H
L_LootPickTarget__L_H_L:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootPickTarget__L_H_H:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickTarget__H:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootPickTarget__H_H
L_LootPickTarget__H_L:
    WorkCmpConst 0x8020, 10
    VMJumpIf CMP_GE, L_LootPickTarget__H_L_H
L_LootPickTarget__H_L_L:
    WorkCmpConst 0x8020, 9
    VMJumpIf CMP_GE, L_LootPickTarget__H_L_L_H
L_LootPickTarget__H_L_L_L:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootPickTarget__H_L_L_H:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootPickTarget__H_L_H:
    WorkCmpConst 0x8020, 11
    VMJumpIf CMP_GE, L_LootPickTarget__H_L_H_H
L_LootPickTarget__H_L_H_L:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootPickTarget__H_L_H_H:
    WorkSetConst 0x800c, 26
    VMReturn
L_LootPickTarget__H_H:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LootPickTarget__H_H_H
L_LootPickTarget__H_H_L:
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_GE, L_LootPickTarget__H_H_L_H
L_LootPickTarget__H_H_L_L:
    WorkSetConst 0x800c, 26
    VMReturn
L_LootPickTarget__H_H_L_H:
    WorkSetConst 0x800c, 3
    VMReturn
L_LootPickTarget__H_H_H:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootPickTarget__H_H_H_H
L_LootPickTarget__H_H_H_L:
    WorkSetConst 0x800c, 3
    VMReturn
L_LootPickTarget__H_H_H_H:
    WorkSetConst 0x800c, 92
    VMReturn
L_LootRoll:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_0
    FlagSet 0x55e
    VMJump L_LootNext_0
L_LootOut_0:
    FlagReset 0x55e
L_LootNext_0:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_1
    FlagSet 0x55f
    VMJump L_LootNext_1
L_LootOut_1:
    FlagReset 0x55f
L_LootNext_1:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_2
    FlagSet 0x560
    VMJump L_LootNext_2
L_LootOut_2:
    FlagReset 0x560
L_LootNext_2:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_3
    FlagSet 0x561
    VMJump L_LootNext_3
L_LootOut_3:
    FlagReset 0x561
L_LootNext_3:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_4
    FlagSet 0x562
    VMJump L_LootNext_4
L_LootOut_4:
    FlagReset 0x562
L_LootNext_4:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_5
    FlagSet 0x563
    VMJump L_LootNext_5
L_LootOut_5:
    FlagReset 0x563
L_LootNext_5:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_6
    FlagSet 0x44f
    VMJump L_LootNext_6
L_LootOut_6:
    FlagReset 0x44f
L_LootNext_6:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_7
    FlagSet 0x450
    VMJump L_LootNext_7
L_LootOut_7:
    FlagReset 0x450
L_LootNext_7:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_8
    FlagSet 0x451
    VMJump L_LootNext_8
L_LootOut_8:
    FlagReset 0x451
L_LootNext_8:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_9
    FlagSet 0x452
    VMJump L_LootNext_9
L_LootOut_9:
    FlagReset 0x452
L_LootNext_9:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_10
    FlagSet 0x453
    VMJump L_LootNext_10
L_LootOut_10:
    FlagReset 0x453
L_LootNext_10:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_11
    FlagSet 0x454
    VMJump L_LootNext_11
L_LootOut_11:
    FlagReset 0x454
L_LootNext_11:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_12
    FlagSet 0x455
    VMJump L_LootNext_12
L_LootOut_12:
    FlagReset 0x455
L_LootNext_12:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_13
    FlagSet 0x456
    VMJump L_LootNext_13
L_LootOut_13:
    FlagReset 0x456
L_LootNext_13:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_14
    FlagSet 0x565
    VMJump L_LootNext_14
L_LootOut_14:
    FlagReset 0x565
L_LootNext_14:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_15
    FlagSet 0x569
    VMJump L_LootNext_15
L_LootOut_15:
    FlagReset 0x569
L_LootNext_15:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_16
    FlagSet 0x566
    VMJump L_LootNext_16
L_LootOut_16:
    FlagReset 0x566
L_LootNext_16:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_17
    FlagSet 0x567
    VMJump L_LootNext_17
L_LootOut_17:
    FlagReset 0x567
L_LootNext_17:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_18
    FlagSet 0x568
    VMJump L_LootNext_18
L_LootOut_18:
    FlagReset 0x568
L_LootNext_18:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_19
    FlagSet 0x56b
    VMJump L_LootNext_19
L_LootOut_19:
    FlagReset 0x56b
L_LootNext_19:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_20
    FlagSet 0xa90
    VMJump L_LootNext_20
L_LootOut_20:
    FlagReset 0xa90
L_LootNext_20:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_21
    FlagSet 0xa91
    VMJump L_LootNext_21
L_LootOut_21:
    FlagReset 0xa91
L_LootNext_21:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_22
    FlagSet 0xa92
    VMJump L_LootNext_22
L_LootOut_22:
    FlagReset 0xa92
L_LootNext_22:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_23
    FlagSet 0x54f
    VMJump L_LootNext_23
L_LootOut_23:
    FlagReset 0x54f
L_LootNext_23:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_24
    FlagSet 0x556
    VMJump L_LootNext_24
L_LootOut_24:
    FlagReset 0x556
L_LootNext_24:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_25
    FlagSet 0x555
    VMJump L_LootNext_25
L_LootOut_25:
    FlagReset 0x555
L_LootNext_25:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_26
    FlagSet 0x554
    VMJump L_LootNext_26
L_LootOut_26:
    FlagReset 0x554
L_LootNext_26:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_27
    FlagSet 0x553
    VMJump L_LootNext_27
L_LootOut_27:
    FlagReset 0x553
L_LootNext_27:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_28
    FlagSet 0x552
    VMJump L_LootNext_28
L_LootOut_28:
    FlagReset 0x552
L_LootNext_28:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_29
    FlagSet 0x550
    VMJump L_LootNext_29
L_LootOut_29:
    FlagReset 0x550
L_LootNext_29:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_30
    FlagSet 0x54e
    VMJump L_LootNext_30
L_LootOut_30:
    FlagReset 0x54e
L_LootNext_30:
    VMReturn
