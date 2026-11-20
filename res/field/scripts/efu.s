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
// Items on the ground (0x15f, which was Nop; Scrcmd_Efu_Special in src/ov036/scrcmd_field_actor.c): op is
// EFU_SPECIAL_DROP or EFU_SPECIAL_BAG_ITEM (include/efu.h)
    .macro EfuSpecial op, item, x, z, result
    FieldCommand 0x15f
    .2byte \op
    .2byte \item
    .2byte \x
    .2byte \z
    .2byte \result
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
    ScriptEntry Script_ChildcareEnter
    ScriptEntry Script_GroundItem
    ScriptEntry Script_Toss
    ScriptEntry Script_Nurse
    ScriptEntry Script_JoyForest
    ScriptEntry Script_ClerkIntro
    ScriptEntry Script_Clerk
    ScriptEntry Script_DayCareJoin
    ScriptEntry Script_PokecenInit
    ScriptEntry Script_DayCareInit
    ScriptEntry Script_GateGuide
    ScriptEntry Script_BlockedDoor
    ScriptEntry Script_GateInit
    ScriptEntry Script_GuideMeet
    ScriptEntry Script_TargetEnter
    ScriptEntry Script_Locker
    ScriptEntry Script_DayCareDoor
    ScriptEntry Script_RouteEnter
    ScriptEntry Script_ClerkCall
    ScriptEntry Script_PaidExit
    ScriptEntry Script_RanchEnter
    ScriptEntry Script_Burgh
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntry Script_LockNone
    ScriptEntriesEnd

// Runs before the first fade-in of a new game
Script_NewGameSetup:
    ActorsPauseAll
    WorkSetConst EFU_WORK_SAVE_VERSION, EFU_SAVE_VERSION
    GiveRunningShoes
    // No money to start with: the zones are where it comes from (the subtraction stops at 0)
    MoneySub 0x3fff
    VMCall L_PokedexFill
    FinishAllEvents
    ActorsUnpauseAll
    VMHalt

// The Pokédex, national and complete: every species seen, which its screens show as a whole entry (pokedex_info.c),
// while only the species the player has caught get the ball, in its list and in battle
L_PokedexFill:
    // The flag that puts the Pokédex in the field menu (FieldMenu_GetMenuType)
    FlagSet EVENT_FLAG_0x0962
    PokeDexEnable
    PokeDexGiveNational
    EfuSpecial EFU_SPECIAL_FILL_POKEDEX, 0, 0, 0, 0x8020
    VMReturn

// Runs after the first fade-in of a new game: a lost Pokémon finds the player
Script_NewGameStart:
    ActorsPauseAll
    SystemMsg Efu_Text_Wake, 2
    LastKeyWait
    // A game from the title menu's Dev Test starts with a play tester's Pokémon instead (GameStart_DevTest)
    WorkCmpConst EFU_WORK_DEV_TEST, 0
    VMCallIf CMP_NE, L_DevTestPokemon
    WorkCmpConst EFU_WORK_DEV_TEST, 0
    VMCallIf CMP_EQ, L_LostSoul
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
    // Saves from before version 2 started without them, and from before version 4 without the Pokédex
    GiveRunningShoes
    WorkCmpConst EFU_WORK_SAVE_VERSION, 4
    VMCallIf CMP_LT, L_PokedexFill
    // Every spot's scav hides until a roll brings it out (Script_RouteEnter); the garden's is out from the start
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62
    FlagSet EFU_FLAG_SPOT_FIRST + \i
    .endr
    FlagReset EFU_FLAG_GARDEN_SCAV
    TrainerFlagReset 395
    FlagReset EFU_FLAG_FOREST_SCAV
    TrainerFlagReset 646
    // Once Burgh is beaten, a generic scavenger may hold Rumination Field in his place
    FlagSet EFU_FLAG_RUMINATION_SCAV
    TrainerFlagReset 640
    FlagGet EFU_FLAG_BURGH_BEATEN, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_RuminationScavEnd
    Random 0x8020, 100
    WorkCmpConst 0x8020, EFU_SIDE_SCAV_CHANCE
    VMJumpIf CMP_GE, L_RuminationScavEnd
    FlagReset EFU_FLAG_RUMINATION_SCAV
L_RuminationScavEnd:
    WorkSetConst EFU_WORK_SCAV_PENDING, 0
    // The world editor's locks that lock again on each raid (gen_efu.py)
    // The side areas' scavs hide too, until the player comes in (Script_TargetEnter, Script_ChildcareEnter)
    .irp i, 0,1,2
    FlagSet EFU_FLAG_TARGET_SCAV_FIRST + \i
    .endr
    FlagSet EFU_FLAG_CHILDCARE_SCAV
    FlagSet EFU_FLAG_CHILDCARE_GENERIC
    .irp i, 0,1,2,3,4,5
    FlagSet EFU_FLAG_RANCH_SCAV_FIRST + \i
    .endr
    FlagReset EFU_FLAG_RANCH_ENTERED
    FlagReset EFU_FLAG_TARGET_ENTERED
    FlagReset EFU_FLAG_CHILDCARE_ENTERED
    WorkSetConst EFU_WORK_SCAVS_OUT, 0
    // Any time of day, and downfall on EFU_DOWNFALL_CHANCE percent of raids (L_RaidOver puts both back)
    Random EFU_WORK_RAID_HOUR, 24
    WorkAdd EFU_WORK_RAID_HOUR, 1
    FlagReset EFU_FLAG_DOWNFALL
    Random 0x8020, 100
    WorkCmpConst 0x8020, EFU_DOWNFALL_CHANCE
    VMCallIf CMP_LT, L_Downfall
    // New loot: each spot's item ball is out or not by its tier's chance (L_LootRoll, from loot.json)
    VMCall L_LootRoll
    VMCall L_DoorRoll
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

L_Downfall:
    FlagSet EFU_FLAG_DOWNFALL
    VMReturn

// The end of a raid, however it went: the real clock and no downfall
L_RaidOver:
    WorkSetConst EFU_WORK_RAID, 0
    WorkSetConst EFU_WORK_RAID_HOUR, 0
    FlagReset EFU_FLAG_DOWNFALL
    VMReturn

// Stepping up to Route 2's old gate: a ride home for EFU_PAID_EXIT_PRICE, which ends the exploration as walking home
// would, from the east gate's Route 3 door; or a step back
Script_PaidExit:
    ActorsPauseAll
    MoneyWinDisp 31, 1
    WorkSetConst 0x8020, EFU_PAID_EXIT_PRICE
    WordSetNumber 0, 0x8020, 3
    SystemMsg Efu_Text_PaidExitAsk, 2
    YesNoWin 0x8021
    WorkCmpConst 0x8021, 1
    VMJumpIf CMP_EQ, L_PaidExitStay
    MoneyCheck 0x8022, 0x8020
    WorkCmpConst 0x8022, 0
    VMJumpIf CMP_EQ, L_PaidExitPoor
    MoneySub 0x8020
    MoneyWinUpdate
    SEPlay SEQ_SE_SYS_08
    SystemMsg Efu_Text_PaidExitGo, 2
    LastKeyWait
    SystemMsgClose
    MoneyWinClose
    MapChangeWarp ZONE_NACRENE_GATE, 14, 5, 2
    ActorsUnpauseAll
    VMHalt

L_PaidExitPoor:
    SystemMsg Efu_Text_NotEnoughMoney, 2
    LastKeyWait
L_PaidExitStay:
    SystemMsgClose
    MoneyWinClose
    ActorCmdExec 255, Movement_StepBackWest
    ActorCmdWait
    ActorsUnpauseAll
    VMHalt

// Stepping up to Nacrene's door in the east gate while out on a raid: home, and saved
Script_RaidReturn:
    ActorsPauseAll
    VMCall L_RaidOver
    // The Day Care's Pokémon grow a level with each raid
    EfuSpecial EFU_SPECIAL_DAYCARE_GROW, 0, 0, 0, 0x8010
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
    VMCall L_RaidOver
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
    VMCall L_RaidOver
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
// Dev Test's Pokémon: a level 100 Volcarona
L_DevTestPokemon:
    WorkSetConst 0x8025, 637
    WordSetPokeSpecies 1, 0x8025
    PokePartyAdd 0x8010, 0x8025, 0, 100
    VMJump L_LostSoulGot

L_LostSoulFound:
    WordSetPokeSpecies 1, 0x8025
    PokePartyAdd 0x8010, 0x8025, 0, EFU_LOST_SOUL_LEVEL
L_LostSoulGot:
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

// Picking up loot: what the ball holds is rolled from its place's tiers (gen_efu.py's LOOT_PLACES and LOOT_TIERS),
// then given at once with one message, and the ball is hidden by its flag (the original's item ball script, global
// 7400, took two messages and the player's pickup pose)
Script_LootRoute:
    ActorsPauseAll
    VMCall L_LootSwapOut
    VMCall L_LootPickRoute
    VMJump L_LootGive

Script_LootCave:
    ActorsPauseAll
    VMCall L_LootSwapOut
    VMCall L_LootPickCave
    VMJump L_LootGive

Script_LootTarget:
    ActorsPauseAll
    VMCall L_LootSwapOut
    VMCall L_LootPickTarget
L_LootGive:
    ActorGetSpawnFlag 0x8011, 0x8010
    FlagSet 0x8010
    ActorDelete 0x8011
    ItemAdd 0x800c, 1, 0x8010
    WordSetItemNameEx 0, 0x800c, 1, 0
    WorkCmpConst 0x8012, 0
    VMJumpIf CMP_NE, L_ItemSwapped
    VMJump L_ItemTaken

// The one-item bag (include/efu_bag.h): with the bag's item already carried, a loot ball swaps it for what's in the
// ball, unseen, without asking: the bag's item is left on the ball's tile, where it can be picked up again. What a ball
// holds is rolled only when it is taken, so it can't be peeked at and rolled again (every loot item can be held, so a
// Poke Ball stands for them all). 0x8012 is the item left, or 0
L_LootSwapOut:
    WorkSetConst 0x8012, 0
    ItemCheckSpace 4, 1, 0x800c
    WorkCmpConst 0x800c, 0
    VMJumpIf CMP_NE, L_LootSwapOutDone
    EfuSpecial EFU_SPECIAL_BAG_ITEM, 0, 0, 0, 0x8012
    ActorGetGPos 0x8011, 0x8014, 0x8015
    ItemSub 0x8012, 1, 0x8016
    EfuSpecial EFU_SPECIAL_DROP, 0x8012, 0x8014, 0x8015, 0x8016
L_LootSwapOutDone:
    VMReturn

// The messages of an item picked up, its name in word 0 and what was left for it in word 1, played over the item
// fanfare, which the player can't cut short
L_ItemTaken:
    MEPlay SEQ_ME_ITEM
    SystemMsg Efu_Text_GroundTake, 2
    VMJump L_ItemDone

L_ItemSwapped:
    WordSetItemNameEx 1, 0x8012, 1, 0
    MEPlay SEQ_ME_ITEM
    SystemMsg Efu_Text_GroundSwapped, 2
L_ItemDone:
    MEWait
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// After a win against a scavenger (global_3000.s calls it, with the Trainer in 0x803f): they run off, leaving an item
// from the target's table on the ground where they stood, for the player to pick up
Script_ScavDrop:
    VMCall L_LootPickScav
    EfuSpecial EFU_SPECIAL_SCAV_GONE, 0x803f, 0x800c, 0, 0x8010
    WorkCmpConst 0x8010, 0
    VMJumpIf CMP_EQ, L_ScavDropLost
    SystemMsg Efu_Text_ScavDrop, 2
    LastKeyWait
    SystemMsgClose
    RTEndGlobal
    VMHalt

L_ScavDropLost:
    SystemMsg Efu_Text_ScavDropLost, 2
    LastKeyWait
    SystemMsgClose
    RTEndGlobal
    VMHalt

// Entering Route 3's childcare centre (its init script): Billy (EFU_TRAINER_BILLY) waits there always while the Day
// Care Lady's quest is open. Once he's beaten, he's gone for good (L_DayCareQuestCheck), and a generic scavenger takes
// over: like the target's (Script_TargetEnter), they come out on EFU_SIDE_SCAV_CHANCE percent of the exploration's
// first entries and EFU_ROUTE_SCAV_CHANCE percent of the later ones, and stay until they are beaten
Script_ChildcareEnter:
    VMCall L_DayCareQuestCheck
    FlagGet EFU_FLAG_DAYCARE_QUEST_DONE, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_ChildcareBilly
    FlagSet EFU_FLAG_CHILDCARE_SCAV
    TrainerFlagReset 398
    WorkSetConst 0x8021, EFU_ROUTE_SCAV_CHANCE
    FlagGet EFU_FLAG_CHILDCARE_ENTERED, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_ChildcareRoll
    FlagSet EFU_FLAG_CHILDCARE_ENTERED
    WorkSetConst 0x8021, EFU_SIDE_SCAV_CHANCE
L_ChildcareRoll:
    Random 0x8020, 100
    WorkCmpWork 0x8020, 0x8021
    VMJumpIf CMP_GE, L_ChildcareEnd
    FlagReset EFU_FLAG_CHILDCARE_GENERIC
L_ChildcareEnd:
    VMHalt

L_ChildcareBilly:
    TrainerFlagReset EFU_TRAINER_BILLY
    FlagReset EFU_FLAG_CHILDCARE_SCAV
    VMHalt

// The Day Care Lady's quest is done once Billy has been beaten, which his trainer flag holds until the centre is entered
// again
L_DayCareQuestCheck:
    TrainerFlagGet EFU_TRAINER_BILLY, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_DayCareQuestOpen
    FlagSet EFU_FLAG_DAYCARE_QUEST_DONE
L_DayCareQuestOpen:
    VMReturn

// An item on the ground (EfuSpecial), its item in the actor's user parameter 0: taken, and when the bag's item is
// already carried, swapped for it without asking, leaving the bag's item in its place
Script_GroundItem:
    ActorsPauseAll
    ActorGetUserParam 0x8011, 0, 0x800c
    WordSetItemNameEx 0, 0x800c, 1, 0
    WorkSetConst 0x8012, 0
    ItemCheckSpace 0x800c, 1, 0x8010
    WorkCmpConst 0x8010, 0
    VMJumpIf CMP_EQ, L_GroundSwap
    ActorDelete 0x8011
    ItemAdd 0x800c, 1, 0x8010
    VMJump L_ItemTaken

L_GroundSwap:
    EfuSpecial EFU_SPECIAL_BAG_ITEM, 0, 0, 0, 0x8012
    ActorGetGPos 0x8011, 0x8014, 0x8015
    ActorDelete 0x8011
    ItemSub 0x8012, 1, 0x8016
    ItemAdd 0x800c, 1, 0x8016
    EfuSpecial EFU_SPECIAL_DROP, 0x8012, 0x8014, 0x8015, 0x8016
    VMJump L_ItemSwapped

// Reserved by the bag after a toss (itemmenu.c): the item lands beside the player, or is lost with nowhere to put it
Script_Toss:
    WorkGet 0x800c, EFU_WORK_TOSSED_ITEM
    WorkSetConst EFU_WORK_TOSSED_ITEM, 0
    WorkCmpConst 0x800c, 0
    VMJumpIf CMP_EQ, L_TossDone
    EfuSpecial EFU_SPECIAL_DROP, 0x800c, EFU_GROUND_BESIDE_PLAYER, 0, 0x8010
    WorkCmpConst 0x8010, 0
    VMJumpIf CMP_NE, L_TossDone
    ActorsPauseAll
    WordSetItemNameEx 0, 0x800c, 1, 0
    SystemMsg Efu_Text_TossLost, 2
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
L_TossDone:
    VMHalt

// Nurse Joy at the base's counter: a full heal for the party's total level in money
Script_Nurse:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    MoneyWinDisp 31, 1
    EfuSpecial EFU_SPECIAL_PARTY_LEVELS, 0, 0, 0, 0x8020
    WordSetNumber 0, 0x8020, 5
    ActorMsg MSGFILE_SCRIPT, Efu_Text_NurseOffer, 0x8011, 2, 0
    VMCall L_PaidHeal
    WorkCmpConst 0x8021, 0
    VMJumpIf CMP_NE, L_NurseEnd
    ActorCmdExec 0x8011, Movement_NurseTurn
    ActorCmdWait
    PokePartyGetCount 0x8023, 1
    PokecenPlayHealingSequence 0x8023
    PokePartyRecoverAll
    ActorCmdExec 0x8011, Movement_NurseBack
    ActorCmdWait
    ActorMsg MSGFILE_SCRIPT, Efu_Text_NurseDone, 0x8011, 2, 0
    LastKeyWait
L_NurseEnd:
    ActorMsgClose
    MoneyWinClose
    ActorsUnpauseAll
    VMHalt

// After the offer of a heal for 0x8020: on yes and with the money, takes it and sets 0x8021 to 0; otherwise says why
// not, and sets it to 1
L_PaidHeal:
    YesNoWin 0x8021
    WorkCmpConst 0x8021, 1
    VMJumpIf CMP_EQ, L_PaidHealNo
    MoneyCheck 0x8022, 0x8020
    WorkCmpConst 0x8022, 0
    VMJumpIf CMP_EQ, L_PaidHealPoor
    MoneySub 0x8020
    MoneyWinUpdate
    SEPlay SEQ_SE_SYS_08
    VMReturn

L_PaidHealPoor:
    WorkSetConst 0x8021, 1
    ActorMsg MSGFILE_SCRIPT, Efu_Text_NotEnoughMoney, 0x8011, 2, 0
    LastKeyWait
    VMReturn

L_PaidHealNo:
    ActorMsg MSGFILE_SCRIPT, Efu_Text_NurseBye, 0x8011, 2, 0
    LastKeyWait
    VMReturn

Movement_NurseTurn:
    Move 0, 1
    MoveEnd

Movement_NurseBack:
    Move 1, 1
    MoveEnd

// Nurse Joy in Pinwheel Forest: a heal on the spot for the same price, then the offer to join the base for
// EFU_JOY_HIRE, after which she is gone from the forest (her hide flag is EFU_FLAG_JOY_JOINED)
Script_JoyForest:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    MoneyWinDisp 31, 1
    EfuSpecial EFU_SPECIAL_PARTY_LEVELS, 0, 0, 0, 0x8020
    WordSetNumber 0, 0x8020, 5
    ActorMsg MSGFILE_SCRIPT, Efu_Text_JoyOffer, 0x8011, 2, 0
    VMCall L_PaidHeal
    WorkCmpConst 0x8021, 0
    VMJumpIf CMP_NE, L_JoyAsk
    FadeEx 3, 0, 16, 2
    FadeExWait
    PokePartyRecoverAll
    MEPlay SEQ_ME_ASA
    MEWait
    FadeEx 3, 16, 0, 2
    FadeExWait
L_JoyAsk:
    WorkSetConst 0x8020, EFU_JOY_HIRE
    WordSetNumber 0, 0x8020, 5
    ActorMsg MSGFILE_SCRIPT, Efu_Text_JoyJoin, 0x8011, 2, 0
    YesNoWin 0x8021
    WorkCmpConst 0x8021, 1
    VMJumpIf CMP_EQ, L_JoyStay
    MoneyCheck 0x8022, 0x8020
    WorkCmpConst 0x8022, 0
    VMJumpIf CMP_EQ, L_JoyPoor
    MoneySub 0x8020
    MoneyWinUpdate
    SEPlay SEQ_SE_SYS_08
    ActorMsg MSGFILE_SCRIPT, Efu_Text_JoyJoined, 0x8011, 2, 0
    LastKeyWait
    ActorMsgClose
    MoneyWinClose
    FlagSet EFU_FLAG_JOY_JOINED
    FadeEx 3, 0, 16, 2
    FadeExWait
    ActorDelete 0x8011
    FadeEx 3, 16, 0, 2
    FadeExWait
    ActorsUnpauseAll
    VMHalt

L_JoyPoor:
    ActorMsg MSGFILE_SCRIPT, Efu_Text_NotEnoughMoney, 0x8011, 2, 0
    LastKeyWait
L_JoyStay:
    ActorMsg MSGFILE_SCRIPT, Efu_Text_JoyStay, 0x8011, 2, 0
    LastKeyWait
    ActorMsgClose
    MoneyWinClose
    ActorsUnpauseAll
    VMHalt

// The clerk, in the Pokémon Center's waiting area the first time: what happened, and then to the Poké Mart counter
// (Script_PokecenInit shows the counter's clerk once EFU_FLAG_CLERK_MET is set, which hides this one)
Script_ClerkIntro:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
L_ClerkIntroTalk:
    ActorMsg MSGFILE_SCRIPT, Efu_Text_ClerkIntro, 0x8011, 2, 0
    LastKeyWait
    ActorMsgClose
    FlagSet EFU_FLAG_CLERK_MET
    WorkSetConst EFU_WORK_CLERK_CALLED, 1
    FlagReset EFU_FLAG_BASE_CLERK_HIDDEN
    FadeEx 3, 0, 16, 2
    FadeExWait
    ActorDelete 0x8011
    ActorAdd 0
    FadeEx 3, 16, 0, 2
    FadeExWait
    ActorsUnpauseAll
    VMHalt

// Stepping into the Pokémon Center while the clerk is in its waiting area (a trigger by the door, while
// EFU_WORK_CLERK_CALLED is 0): the clerk sees the player, comes over along the row above and down to them, and talks
// (Script_ClerkIntro). A save where they have met already only has the work set
Script_ClerkCall:
    FlagGet EFU_FLAG_CLERK_MET, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_ClerkCallMet
    ActorsPauseAll
    ActorCmdExec EFU_CLERK_INTRO_ID, Movement_ClerkNotice
    ActorCmdWait
    PlayerGetGPos 0x8020, 0x8021
    WorkSetConst 0x8022, EFU_CLERK_INTRO_X
L_ClerkCallWalk:
    WorkCmpWork 0x8022, 0x8020
    VMJumpIf CMP_GE, L_ClerkCallDown
    ActorCmdExec EFU_CLERK_INTRO_ID, Movement_ClerkRight
    ActorCmdWait
    WorkAdd 0x8022, 1
    VMJump L_ClerkCallWalk

L_ClerkCallDown:
    ActorCmdExec EFU_CLERK_INTRO_ID, Movement_ClerkDown
    ActorCmdWait
    SEPlay SEQ_SE_MESSAGE
    WorkSetConst 0x8011, EFU_CLERK_INTRO_ID
    VMJump L_ClerkIntroTalk

L_ClerkCallMet:
    WorkSetConst EFU_WORK_CLERK_CALLED, 1
    VMHalt

    .balign 4, 0
Movement_ClerkNotice:
    Move 3, 1
    Move 75, 1
    MoveEnd

Movement_ClerkRight:
    Move 15, 1
    MoveEnd

// From the waiting area's row (13) to the one above the trigger's (16), facing the player
Movement_ClerkDown:
    Move 13, 4
    MoveEnd

// The clerk at the counter: the Poké Mart of EFU_MART_SHOP_ID's list, at the normal prices
// (scrcmd_shop.c), through the original clerk's script (global 10110), as Nacrene's Pokémon Center ran it
Script_Clerk:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    VMStackPush 0x8000
    VMStackPush 0x8001
    WorkSet 0x8000, EFU_MART_SHOP_ID
    WorkSet 0x8001, 1
    RTCallGlobal 10110
    VMStackPop 0x8001
    VMStackPop 0x8000
    FinishAllEvents
    ActorsUnpauseAll
    VMHalt

// The Day Care Lady in Route 3's Day Care: until she has joined, she asks the player to drive the scav out of the
// childcare centre next door (Script_ChildcareEnter), and once it is beaten moves into a warehouse of the base, where
// the original Day Care Lady's script (global 2201) runs her (Script_DayCareInit shows her there, and her warehouse's
// doors open). After that she takes Pokémon in here, but gives none back: her original script runs with
// EFU_FLAG_DAYCARE_DEPOSIT_ONLY set, which leaves Withdraw out of its menu
Script_DayCareJoin:
    FlagGet EFU_FLAG_DAYCARE_JOINED, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_DayCareDeposit
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    VMCall L_DayCareQuestCheck
    FlagGet EFU_FLAG_DAYCARE_QUEST_DONE, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_DayCareJoins
    ActorMsg MSGFILE_SCRIPT, Efu_Text_DayCareQuest, 0x8011, 2, 0
    LastKeyWait
    ActorMsgClose
    ActorsUnpauseAll
    VMHalt

L_DayCareJoins:
    SEPlay SEQ_SE_SYS_08
    ActorMsg MSGFILE_SCRIPT, Efu_Text_DayCareJoined, 0x8011, 2, 0
    LastKeyWait
    FlagSet EFU_FLAG_DAYCARE_JOINED
    ActorMsgClose
    ActorsUnpauseAll
L_DayCareDeposit:
    FlagSet EFU_FLAG_DAYCARE_DEPOSIT_ONLY
    RTCallGlobal 2201
    FlagReset EFU_FLAG_DAYCARE_DEPOSIT_ONLY
    VMHalt

// Entering a route (its init script), from anywhere: a scav comes out at the player's next step on
// EFU_ROUTE_SCAV_CHANCE percent of entries (EfuScav_Spawn, in EventTrainerEye_EfuPursue)
Script_RouteEnter:
    Random 0x8020, 100
    WorkCmpConst 0x8020, EFU_ROUTE_SCAV_CHANCE
    VMJumpIf CMP_GE, L_RouteEnterEnd
    WorkSetConst EFU_WORK_SCAV_PENDING, 1
L_RouteEnterEnd:
    VMHalt

// The signs on the Day Care Lady's warehouse doors, which are shut until she has joined (GetWarpForWalkIn)
Script_DayCareDoor:
    FlagGet EFU_FLAG_DAYCARE_JOINED, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_NE, L_DayCareDoorEnd
    ActorsPauseAll
    SystemMsg Efu_Text_BoardedDoor, 2
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
L_DayCareDoorEnd:
    VMHalt

// The base's init scripts (on loading the zone): the people who have joined show, the rest stay hidden
Script_PokecenInit:
    FlagSet EFU_FLAG_BASE_JOY_HIDDEN
    FlagGet EFU_FLAG_JOY_JOINED, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_PokecenClerk
    FlagReset EFU_FLAG_BASE_JOY_HIDDEN
L_PokecenClerk:
    FlagSet EFU_FLAG_BASE_CLERK_HIDDEN
    FlagGet EFU_FLAG_CLERK_MET, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_PokecenInitEnd
    FlagReset EFU_FLAG_BASE_CLERK_HIDDEN
L_PokecenInitEnd:
    VMHalt

Script_DayCareInit:
    FlagSet EFU_FLAG_BASE_DAYCARE_HIDDEN
    FlagGet EFU_FLAG_DAYCARE_JOINED, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_DayCareInitEnd
    FlagReset EFU_FLAG_BASE_DAYCARE_HIDDEN
L_DayCareInitEnd:
    VMHalt

Script_GateInit:
    FlagSet EFU_FLAG_BASE_GUIDE_HIDDEN
    FlagGet EFU_FLAG_GUIDE_MET, 0x8020
    WorkCmpConst 0x8020, 0
    VMJumpIf CMP_EQ, L_GateInitEnd
    FlagReset EFU_FLAG_BASE_GUIDE_HIDDEN
L_GateInitEnd:
    VMHalt

// The guide out on Route 3, the first time: they make for the east gate, where Script_GateGuide runs them
Script_GuideMeet:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    ActorMsg MSGFILE_SCRIPT, Efu_Text_GuideMeet, 0x8011, 2, 0
    LastKeyWait
    ActorMsgClose
    FlagSet EFU_FLAG_GUIDE_MET
    FadeEx 3, 0, 16, 2
    FadeExWait
    ActorDelete 0x8011
    FadeEx 3, 16, 0, 2
    FadeExWait
    ActorsUnpauseAll
    VMHalt

// A boulder in front of a shut door
Script_BlockedDoor:
    ActorsPauseAll
    SystemMsg Efu_Text_BlockedDoor, 2
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

// Entering the target (its init script): the first time on an exploration, each of its scavs comes out on
// EFU_SIDE_SCAV_CHANCE percent; after that, each that isn't out comes out on EFU_ROUTE_SCAV_CHANCE percent. One that is
// out stays until it is beaten (EFU_SPECIAL_SCAV_GONE), so coming back only ever adds scavs. All are ready to fight
Script_TargetEnter:
    WorkSetConst 0x8021, EFU_ROUTE_SCAV_CHANCE
    FlagGet EFU_FLAG_TARGET_ENTERED, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_TargetRoll
    FlagSet EFU_FLAG_TARGET_ENTERED
    WorkSetConst 0x8021, EFU_SIDE_SCAV_CHANCE
L_TargetRoll:
    .irp i, 0,1,2
    Random 0x8020, 100
    WorkCmpWork 0x8020, 0x8021
    VMJumpIf CMP_GE, L_TargetScavNext\i
    FlagReset EFU_FLAG_TARGET_SCAV_FIRST + \i
L_TargetScavNext\i:
    .endr
    TrainerFlagReset 643
    TrainerFlagReset 642
    TrainerFlagReset 645
    VMHalt

// Entering Floccesy Ranch, overrun (its init script): its scavengers come out like the target's
Script_RanchEnter:
    WorkSetConst 0x8021, EFU_ROUTE_SCAV_CHANCE
    FlagGet EFU_FLAG_RANCH_ENTERED, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_RanchRoll
    FlagSet EFU_FLAG_RANCH_ENTERED
    WorkSetConst 0x8021, EFU_SIDE_SCAV_CHANCE
L_RanchRoll:
    .irp i, 0,1,2,3,4,5
    Random 0x8020, 100
    WorkCmpWork 0x8020, 0x8021
    VMJumpIf CMP_GE, L_RanchScavNext\i
    FlagReset EFU_FLAG_RANCH_SCAV_FIRST + \i
L_RanchScavNext\i:
    .endr
    TrainerFlagReset 164
    TrainerFlagReset 165
    TrainerFlagReset 176
    TrainerFlagReset 387
    TrainerFlagReset 388
    TrainerFlagReset 392
    VMHalt

// Burgh, holding Rumination Field at the forest's heart: beating him gives the Blank HM, frees the guide and ends the
// zone's story. He doesn't come back (EFU_FLAG_BURGH_BEATEN hides him)
Script_Burgh:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    ActorMsg MSGFILE_SCRIPT, Efu_Text_BurghIntro, 0x8011, 2, 0
    ActorMsgClose
    CallTrainerBattle TRAINER_LEADER_BURGH, 0, 0
    // 1 for a win, 0 for a loss
    TrainerBattleIsVictory 0x8010
    WorkCmpConst 0x8010, 0
    VMJumpIf CMP_EQ, L_BurghLost
    CallTrainerBattleEnd
    ActorMsg MSGFILE_SCRIPT, Efu_Text_BurghBeaten, 0x8011, 2, 0
    ActorMsgClose
    WorkSetConst 0x800c, EFU_ITEM_BLANK_HM
    ItemAdd 0x800c, 1, 0x8010
    WordSetItemNameEx 0, 0x800c, 1, 0
    MEPlay SEQ_ME_ITEM
    SystemMsg Efu_Text_BurghReward, 2
    MEWait
    LastKeyWait
    SystemMsgClose
    ActorMsg MSGFILE_SCRIPT, Efu_Text_BurghLeave, 0x8011, 2, 0
    ActorMsgClose
    FlagSet EFU_FLAG_BURGH_BEATEN
    ActorDelete 0x8011
    MEPlay SEQ_ME_ASA
    SystemMsg Efu_Text_ZoneCleared, 2
    MEWait
    LastKeyWait
    SystemMsgClose
    ActorsUnpauseAll
    VMHalt

L_BurghLost:
    CallTrainerLose
    VMHalt

// Heading out: each door that can be shut is, on EFU_DOOR_SHUT_CHANCE percent of explorations (its boulder out)
L_DoorRoll:
    .irp i, 0,1,2
    FlagSet EFU_FLAG_DOOR_FIRST + \i
    Random 0x8020, 100
    WorkCmpConst 0x8020, EFU_DOOR_SHUT_CHANCE
    VMJumpIf CMP_GE, L_DoorNext\i
    FlagReset EFU_FLAG_DOOR_FIRST + \i
L_DoorNext\i:
    .endr
    // The childcare centre's (the first) stays open while the Day Care Lady's quest, to beat its scav, is
    FlagGet EFU_FLAG_DAYCARE_QUEST_DONE, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_DoorRollEnd
    FlagSet EFU_FLAG_DOOR_FIRST
L_DoorRollEnd:
    // The inner forest's bridges: a Cut tree before the left one, a Strength boulder before the right one, each on
    // EFU_BRIDGE_BLOCK_CHANCE percent
    FlagSet EFU_FLAG_BRIDGE_CUT
    Random 0x8020, 100
    WorkCmpConst 0x8020, EFU_BRIDGE_BLOCK_CHANCE
    VMJumpIf CMP_GE, L_BridgeBoulder
    FlagReset EFU_FLAG_BRIDGE_CUT
L_BridgeBoulder:
    FlagSet EFU_FLAG_BRIDGE_BOULDER
    Random 0x8020, 100
    WorkCmpConst 0x8020, EFU_BRIDGE_BLOCK_CHANCE
    VMJumpIf CMP_GE, L_BridgeEnd
    FlagReset EFU_FLAG_BRIDGE_BOULDER
L_BridgeEnd:
    VMReturn

// The east gate's guide: one day, the way to the farther zones
Script_GateGuide:
    ActorsPauseAll
    SEPlay SEQ_SE_MESSAGE
    ActorSetEyeToEye
    FlagGet EFU_FLAG_BURGH_BEATEN, 0x8020
    WorkCmpConst 0x8020, 1
    VMJumpIf CMP_EQ, L_GateGuideFree
    ActorMsg MSGFILE_SCRIPT, Efu_Text_GateGuide, 0x8011, 2, 0
    VMJump L_GateGuideEnd
L_GateGuideFree:
    ActorMsg MSGFILE_SCRIPT, Efu_Text_GateGuideFree, 0x8011, 2, 0
L_GateGuideEnd:
    LastKeyWait
    ActorMsgClose
    ActorsUnpauseAll
    VMHalt

L_LootTierCommon:
    Random 0x8020, 34
L_LootTierCommon_:
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_GE, L_LootTierCommon__H
L_LootTierCommon__L:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootTierCommon__L_H
L_LootTierCommon__L_L:
    WorkCmpConst 0x8020, 4
    VMJumpIf CMP_GE, L_LootTierCommon__L_L_H
L_LootTierCommon__L_L_L:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootTierCommon__L_L_H:
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_GE, L_LootTierCommon__L_L_H_H
L_LootTierCommon__L_L_H_L:
    WorkSetConst 0x800c, 86
    VMReturn
L_LootTierCommon__L_L_H_H:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootTierCommon__L_H:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootTierCommon__L_H_H
L_LootTierCommon__L_H_L:
    WorkSetConst 0x800c, 4
    VMReturn
L_LootTierCommon__L_H_H:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LootTierCommon__L_H_H_H
L_LootTierCommon__L_H_H_L:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootTierCommon__L_H_H_H:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootTierCommon__L_H_H_H_H
L_LootTierCommon__L_H_H_H_L:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootTierCommon__L_H_H_H_H:
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_GE, L_LootTierCommon__L_H_H_H_H_H
L_LootTierCommon__L_H_H_H_H_L:
    WorkSetConst 0x800c, 155
    VMReturn
L_LootTierCommon__L_H_H_H_H_H:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootTierCommon__H:
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootTierCommon__H_H
L_LootTierCommon__H_L:
    WorkCmpConst 0x8020, 21
    VMJumpIf CMP_GE, L_LootTierCommon__H_L_H
L_LootTierCommon__H_L_L:
    WorkCmpConst 0x8020, 19
    VMJumpIf CMP_GE, L_LootTierCommon__H_L_L_H
L_LootTierCommon__H_L_L_L:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootTierCommon__H_L_L_H:
    WorkCmpConst 0x8020, 20
    VMJumpIf CMP_GE, L_LootTierCommon__H_L_L_H_H
L_LootTierCommon__H_L_L_H_L:
    WorkSetConst 0x800c, 17
    VMReturn
L_LootTierCommon__H_L_L_H_H:
    WorkSetConst 0x800c, 18
    VMReturn
L_LootTierCommon__H_L_H:
    WorkCmpConst 0x8020, 23
    VMJumpIf CMP_GE, L_LootTierCommon__H_L_H_H
L_LootTierCommon__H_L_H_L:
    WorkCmpConst 0x8020, 22
    VMJumpIf CMP_GE, L_LootTierCommon__H_L_H_L_H
L_LootTierCommon__H_L_H_L_L:
    WorkSetConst 0x800c, 18
    VMReturn
L_LootTierCommon__H_L_H_L_H:
    WorkSetConst 0x800c, 22
    VMReturn
L_LootTierCommon__H_L_H_H:
    WorkCmpConst 0x8020, 24
    VMJumpIf CMP_GE, L_LootTierCommon__H_L_H_H_H
L_LootTierCommon__H_L_H_H_L:
    WorkSetConst 0x800c, 22
    VMReturn
L_LootTierCommon__H_L_H_H_H:
    WorkSetConst 0x800c, 79
    VMReturn
L_LootTierCommon__H_H:
    WorkCmpConst 0x8020, 29
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_H
L_LootTierCommon__H_H_L:
    WorkCmpConst 0x8020, 27
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_L_H
L_LootTierCommon__H_H_L_L:
    WorkCmpConst 0x8020, 26
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_L_L_H
L_LootTierCommon__H_H_L_L_L:
    WorkSetConst 0x800c, 79
    VMReturn
L_LootTierCommon__H_H_L_L_H:
    WorkSetConst 0x800c, 21
    VMReturn
L_LootTierCommon__H_H_L_H:
    WorkCmpConst 0x8020, 28
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_L_H_H
L_LootTierCommon__H_H_L_H_L:
    WorkSetConst 0x800c, 19
    VMReturn
L_LootTierCommon__H_H_L_H_H:
    WorkSetConst 0x800c, 20
    VMReturn
L_LootTierCommon__H_H_H:
    WorkCmpConst 0x8020, 31
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_H_H
L_LootTierCommon__H_H_H_L:
    WorkCmpConst 0x8020, 30
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_H_L_H
L_LootTierCommon__H_H_H_L_L:
    WorkSetConst 0x800c, 149
    VMReturn
L_LootTierCommon__H_H_H_L_H:
    WorkSetConst 0x800c, 151
    VMReturn
L_LootTierCommon__H_H_H_H:
    WorkCmpConst 0x8020, 32
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_H_H_H
L_LootTierCommon__H_H_H_H_L:
    WorkSetConst 0x800c, 152
    VMReturn
L_LootTierCommon__H_H_H_H_H:
    WorkCmpConst 0x8020, 33
    VMJumpIf CMP_GE, L_LootTierCommon__H_H_H_H_H_H
L_LootTierCommon__H_H_H_H_H_L:
    WorkSetConst 0x800c, 153
    VMReturn
L_LootTierCommon__H_H_H_H_H_H:
    WorkSetConst 0x800c, 150
    VMReturn
L_LootTierUncommon:
    Random 0x8020, 28
L_LootTierUncommon_:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LootTierUncommon__H
L_LootTierUncommon__L:
    WorkCmpConst 0x8020, 7
    VMJumpIf CMP_GE, L_LootTierUncommon__L_H
L_LootTierUncommon__L_L:
    WorkCmpConst 0x8020, 3
    VMJumpIf CMP_GE, L_LootTierUncommon__L_L_H
L_LootTierUncommon__L_L_L:
    WorkSetConst 0x800c, 3
    VMReturn
L_LootTierUncommon__L_L_H:
    WorkCmpConst 0x8020, 5
    VMJumpIf CMP_GE, L_LootTierUncommon__L_L_H_H
L_LootTierUncommon__L_L_H_L:
    WorkCmpConst 0x8020, 4
    VMJumpIf CMP_GE, L_LootTierUncommon__L_L_H_L_H
L_LootTierUncommon__L_L_H_L_L:
    WorkSetConst 0x800c, 3
    VMReturn
L_LootTierUncommon__L_L_H_L_H:
    WorkSetConst 0x800c, 26
    VMReturn
L_LootTierUncommon__L_L_H_H:
    WorkSetConst 0x800c, 26
    VMReturn
L_LootTierUncommon__L_H:
    WorkCmpConst 0x8020, 10
    VMJumpIf CMP_GE, L_LootTierUncommon__L_H_H
L_LootTierUncommon__L_H_L:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootTierUncommon__L_H_L_H
L_LootTierUncommon__L_H_L_L:
    WorkSetConst 0x800c, 26
    VMReturn
L_LootTierUncommon__L_H_L_H:
    WorkSetConst 0x800c, 88
    VMReturn
L_LootTierUncommon__L_H_H:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootTierUncommon__L_H_H_H
L_LootTierUncommon__L_H_H_L:
    WorkSetConst 0x800c, 88
    VMReturn
L_LootTierUncommon__L_H_H_H:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootTierUncommon__H:
    WorkCmpConst 0x8020, 21
    VMJumpIf CMP_GE, L_LootTierUncommon__H_H
L_LootTierUncommon__H_L:
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_GE, L_LootTierUncommon__H_L_H
L_LootTierUncommon__H_L_L:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootTierUncommon__H_L_L_H
L_LootTierUncommon__H_L_L_L:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootTierUncommon__H_L_L_H:
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_GE, L_LootTierUncommon__H_L_L_H_H
L_LootTierUncommon__H_L_L_H_L:
    WorkSetConst 0x800c, 90
    VMReturn
L_LootTierUncommon__H_L_L_H_H:
    WorkSetConst 0x800c, 27
    VMReturn
L_LootTierUncommon__H_L_H:
    WorkCmpConst 0x8020, 19
    VMJumpIf CMP_GE, L_LootTierUncommon__H_L_H_H
L_LootTierUncommon__H_L_H_L:
    WorkCmpConst 0x8020, 18
    VMJumpIf CMP_GE, L_LootTierUncommon__H_L_H_L_H
L_LootTierUncommon__H_L_H_L_L:
    WorkSetConst 0x800c, 27
    VMReturn
L_LootTierUncommon__H_L_H_L_H:
    WorkSetConst 0x800c, 158
    VMReturn
L_LootTierUncommon__H_L_H_H:
    WorkCmpConst 0x8020, 20
    VMJumpIf CMP_GE, L_LootTierUncommon__H_L_H_H_H
L_LootTierUncommon__H_L_H_H_L:
    WorkSetConst 0x800c, 158
    VMReturn
L_LootTierUncommon__H_L_H_H_H:
    WorkSetConst 0x800c, 87
    VMReturn
L_LootTierUncommon__H_H:
    WorkCmpConst 0x8020, 24
    VMJumpIf CMP_GE, L_LootTierUncommon__H_H_H
L_LootTierUncommon__H_H_L:
    WorkCmpConst 0x8020, 22
    VMJumpIf CMP_GE, L_LootTierUncommon__H_H_L_H
L_LootTierUncommon__H_H_L_L:
    WorkSetConst 0x800c, 87
    VMReturn
L_LootTierUncommon__H_H_L_H:
    WorkSetConst 0x800c, 76
    VMReturn
L_LootTierUncommon__H_H_H:
    WorkCmpConst 0x8020, 26
    VMJumpIf CMP_GE, L_LootTierUncommon__H_H_H_H
L_LootTierUncommon__H_H_H_L:
    WorkSetConst 0x800c, 38
    VMReturn
L_LootTierUncommon__H_H_H_H:
    WorkSetConst 0x800c, 30
    VMReturn
L_LootTierRare:
    Random 0x8020, 20
L_LootTierRare_:
    WorkCmpConst 0x8020, 10
    VMJumpIf CMP_GE, L_LootTierRare__H
L_LootTierRare__L:
    WorkCmpConst 0x8020, 5
    VMJumpIf CMP_GE, L_LootTierRare__L_H
L_LootTierRare__L_L:
    WorkCmpConst 0x8020, 2
    VMJumpIf CMP_GE, L_LootTierRare__L_L_H
L_LootTierRare__L_L_L:
    WorkSetConst 0x800c, 2
    VMReturn
L_LootTierRare__L_L_H:
    WorkCmpConst 0x8020, 3
    VMJumpIf CMP_GE, L_LootTierRare__L_L_H_H
L_LootTierRare__L_L_H_L:
    WorkSetConst 0x800c, 2
    VMReturn
L_LootTierRare__L_L_H_H:
    WorkSetConst 0x800c, 25
    VMReturn
L_LootTierRare__L_H:
    WorkCmpConst 0x8020, 7
    VMJumpIf CMP_GE, L_LootTierRare__L_H_H
L_LootTierRare__L_H_L:
    WorkCmpConst 0x8020, 6
    VMJumpIf CMP_GE, L_LootTierRare__L_H_L_H
L_LootTierRare__L_H_L_L:
    WorkSetConst 0x800c, 25
    VMReturn
L_LootTierRare__L_H_L_H:
    WorkSetConst 0x800c, 28
    VMReturn
L_LootTierRare__L_H_H:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootTierRare__L_H_H_H
L_LootTierRare__L_H_H_L:
    WorkSetConst 0x800c, 28
    VMReturn
L_LootTierRare__L_H_H_H:
    WorkCmpConst 0x8020, 9
    VMJumpIf CMP_GE, L_LootTierRare__L_H_H_H_H
L_LootTierRare__L_H_H_H_L:
    WorkSetConst 0x800c, 28
    VMReturn
L_LootTierRare__L_H_H_H_H:
    WorkSetConst 0x800c, 92
    VMReturn
L_LootTierRare__H:
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootTierRare__H_H
L_LootTierRare__H_L:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootTierRare__H_L_H
L_LootTierRare__H_L_L:
    WorkSetConst 0x800c, 92
    VMReturn
L_LootTierRare__H_L_H:
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_GE, L_LootTierRare__H_L_H_H
L_LootTierRare__H_L_H_L:
    WorkSetConst 0x800c, 89
    VMReturn
L_LootTierRare__H_L_H_H:
    WorkCmpConst 0x8020, 14
    VMJumpIf CMP_GE, L_LootTierRare__H_L_H_H_H
L_LootTierRare__H_L_H_H_L:
    WorkSetConst 0x800c, 89
    VMReturn
L_LootTierRare__H_L_H_H_H:
    WorkSetConst 0x800c, 157
    VMReturn
L_LootTierRare__H_H:
    WorkCmpConst 0x8020, 17
    VMJumpIf CMP_GE, L_LootTierRare__H_H_H
L_LootTierRare__H_H_L:
    WorkCmpConst 0x8020, 16
    VMJumpIf CMP_GE, L_LootTierRare__H_H_L_H
L_LootTierRare__H_H_L_L:
    WorkSetConst 0x800c, 157
    VMReturn
L_LootTierRare__H_H_L_H:
    WorkSetConst 0x800c, 40
    VMReturn
L_LootTierRare__H_H_H:
    WorkCmpConst 0x8020, 18
    VMJumpIf CMP_GE, L_LootTierRare__H_H_H_H
L_LootTierRare__H_H_H_L:
    WorkSetConst 0x800c, 40
    VMReturn
L_LootTierRare__H_H_H_H:
    WorkCmpConst 0x8020, 19
    VMJumpIf CMP_GE, L_LootTierRare__H_H_H_H_H
L_LootTierRare__H_H_H_H_L:
    WorkSetConst 0x800c, 50
    VMReturn
L_LootTierRare__H_H_H_H_H:
    WorkSetConst 0x800c, 93
    VMReturn
L_LootTierValuable:
    Random 0x8020, 14
L_LootTierValuable_:
    WorkCmpConst 0x8020, 7
    VMJumpIf CMP_GE, L_LootTierValuable__H
L_LootTierValuable__L:
    WorkCmpConst 0x8020, 3
    VMJumpIf CMP_GE, L_LootTierValuable__L_H
L_LootTierValuable__L_L:
    WorkSetConst 0x800c, 91
    VMReturn
L_LootTierValuable__L_H:
    WorkCmpConst 0x8020, 5
    VMJumpIf CMP_GE, L_LootTierValuable__L_H_H
L_LootTierValuable__L_H_L:
    WorkSetConst 0x800c, 29
    VMReturn
L_LootTierValuable__L_H_H:
    WorkSetConst 0x800c, 23
    VMReturn
L_LootTierValuable__H:
    WorkCmpConst 0x8020, 10
    VMJumpIf CMP_GE, L_LootTierValuable__H_H
L_LootTierValuable__H_L:
    WorkCmpConst 0x8020, 8
    VMJumpIf CMP_GE, L_LootTierValuable__H_L_H
L_LootTierValuable__H_L_L:
    WorkSetConst 0x800c, 51
    VMReturn
L_LootTierValuable__H_L_H:
    WorkCmpConst 0x8020, 9
    VMJumpIf CMP_GE, L_LootTierValuable__H_L_H_H
L_LootTierValuable__H_L_H_L:
    WorkSetConst 0x800c, 51
    VMReturn
L_LootTierValuable__H_L_H_H:
    WorkSetConst 0x800c, 581
    VMReturn
L_LootTierValuable__H_H:
    WorkCmpConst 0x8020, 12
    VMJumpIf CMP_GE, L_LootTierValuable__H_H_H
L_LootTierValuable__H_H_L:
    WorkCmpConst 0x8020, 11
    VMJumpIf CMP_GE, L_LootTierValuable__H_H_L_H
L_LootTierValuable__H_H_L_L:
    WorkSetConst 0x800c, 583
    VMReturn
L_LootTierValuable__H_H_L_H:
    WorkSetConst 0x800c, 234
    VMReturn
L_LootTierValuable__H_H_H:
    WorkCmpConst 0x8020, 13
    VMJumpIf CMP_GE, L_LootTierValuable__H_H_H_H
L_LootTierValuable__H_H_H_L:
    WorkSetConst 0x800c, 217
    VMReturn
L_LootTierValuable__H_H_H_H:
    WorkSetConst 0x800c, 221
    VMReturn
L_LootTierCandy:
    Random 0x8020, 1
L_LootTierCandy_:
    WorkSetConst 0x800c, 50
    VMReturn
L_LootPickRoute:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 85
    VMJumpIf CMP_LT, L_LootTierCommon
    VMJump L_LootTierUncommon
L_LootPickCave:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 50
    VMJumpIf CMP_LT, L_LootTierCommon
    WorkCmpConst 0x8020, 90
    VMJumpIf CMP_LT, L_LootTierUncommon
    VMJump L_LootTierRare
L_LootPickTarget:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_LT, L_LootTierCommon
    WorkCmpConst 0x8020, 65
    VMJumpIf CMP_LT, L_LootTierUncommon
    WorkCmpConst 0x8020, 97
    VMJumpIf CMP_LT, L_LootTierRare
    VMJump L_LootTierValuable
L_LootPickScav:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 45
    VMJumpIf CMP_LT, L_LootTierUncommon
    WorkCmpConst 0x8020, 90
    VMJumpIf CMP_LT, L_LootTierRare
    VMJump L_LootTierValuable
L_LootPickCandy:
    Random 0x8020, 100
    VMJump L_LootTierCandy
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
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_14
    FlagSet 0x578
    VMJump L_LootNext_14
L_LootOut_14:
    FlagReset 0x578
L_LootNext_14:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_15
    FlagSet 0x579
    VMJump L_LootNext_15
L_LootOut_15:
    FlagReset 0x579
L_LootNext_15:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_16
    FlagSet 0x57a
    VMJump L_LootNext_16
L_LootOut_16:
    FlagReset 0x57a
L_LootNext_16:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_17
    FlagSet 0x57b
    VMJump L_LootNext_17
L_LootOut_17:
    FlagReset 0x57b
L_LootNext_17:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_18
    FlagSet 0x57d
    VMJump L_LootNext_18
L_LootOut_18:
    FlagReset 0x57d
L_LootNext_18:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_19
    FlagSet 0x57e
    VMJump L_LootNext_19
L_LootOut_19:
    FlagReset 0x57e
L_LootNext_19:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_20
    FlagSet 0x44d
    VMJump L_LootNext_20
L_LootOut_20:
    FlagReset 0x44d
L_LootNext_20:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_21
    FlagSet 0x44e
    VMJump L_LootNext_21
L_LootOut_21:
    FlagReset 0x44e
L_LootNext_21:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 40
    VMJumpIf CMP_GE, L_LootOut_22
    FlagSet 0x58f
    VMJump L_LootNext_22
L_LootOut_22:
    FlagReset 0x58f
L_LootNext_22:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_23
    FlagSet 0x565
    VMJump L_LootNext_23
L_LootOut_23:
    FlagReset 0x565
L_LootNext_23:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_24
    FlagSet 0x569
    VMJump L_LootNext_24
L_LootOut_24:
    FlagReset 0x569
L_LootNext_24:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_25
    FlagSet 0x566
    VMJump L_LootNext_25
L_LootOut_25:
    FlagReset 0x566
L_LootNext_25:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_26
    FlagSet 0x567
    VMJump L_LootNext_26
L_LootOut_26:
    FlagReset 0x567
L_LootNext_26:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_27
    FlagSet 0x568
    VMJump L_LootNext_27
L_LootOut_27:
    FlagReset 0x568
L_LootNext_27:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_28
    FlagSet 0x56b
    VMJump L_LootNext_28
L_LootOut_28:
    FlagReset 0x56b
L_LootNext_28:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_29
    FlagSet 0xa90
    VMJump L_LootNext_29
L_LootOut_29:
    FlagReset 0xa90
L_LootNext_29:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_30
    FlagSet 0xa91
    VMJump L_LootNext_30
L_LootOut_30:
    FlagReset 0xa91
L_LootNext_30:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 25
    VMJumpIf CMP_GE, L_LootOut_31
    FlagSet 0xa92
    VMJump L_LootNext_31
L_LootOut_31:
    FlagReset 0xa92
L_LootNext_31:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_32
    FlagSet 0x54f
    VMJump L_LootNext_32
L_LootOut_32:
    FlagReset 0x54f
L_LootNext_32:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_33
    FlagSet 0x556
    VMJump L_LootNext_33
L_LootOut_33:
    FlagReset 0x556
L_LootNext_33:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_34
    FlagSet 0x555
    VMJump L_LootNext_34
L_LootOut_34:
    FlagReset 0x555
L_LootNext_34:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_35
    FlagSet 0x554
    VMJump L_LootNext_35
L_LootOut_35:
    FlagReset 0x554
L_LootNext_35:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_36
    FlagSet 0x553
    VMJump L_LootNext_36
L_LootOut_36:
    FlagReset 0x553
L_LootNext_36:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_37
    FlagSet 0x552
    VMJump L_LootNext_37
L_LootOut_37:
    FlagReset 0x552
L_LootNext_37:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_38
    FlagSet 0x550
    VMJump L_LootNext_38
L_LootOut_38:
    FlagReset 0x550
L_LootNext_38:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 15
    VMJumpIf CMP_GE, L_LootOut_39
    FlagSet 0x54e
    VMJump L_LootNext_39
L_LootOut_39:
    FlagReset 0x54e
L_LootNext_39:
    Random 0x8020, 100
    WorkCmpConst 0x8020, 90
    VMJumpIf CMP_GE, L_LootOut_40
    FlagSet 0x564
    VMJump L_LootNext_40
L_LootOut_40:
    FlagReset 0x564
L_LootNext_40:
    VMReturn

// The locker, in the player's warehouse and by the Pokémon Center's Poké Mart counter (build_base.py), one store
// shared by both: 20 slots of an item and its count, in event work values of their own (gen_efu.py's
// LOCKER_WORKS). Its list shows each slot, then Store everything (the bag's holdable item, and every item the party
// holds but mail) and Close. A slot offers Take, one at a time into the bag if it has room (include/efu_bag.h), or
// Sell, one at a time for half its price. Neither asks first, and the cursor stays on the slot, so a stack goes quickly
Script_Locker:
    ActorsPauseAll
    MoneyWinDisp 31, 1
    WorkSetConst 0x8028, 0
L_LockerMenu:
    ListMenuAnchorTopLeft 1, 1, 0x8028, 1, 0x8020
    VMCall L_LockerList
    ListMenuAdd Efu_Text_LockerStore, 65535, 100
    ListMenuAdd Efu_Text_LockerClose, 65535, 101
    WordSetNumber 0, 0x8029, 2
    SystemMsg Efu_Text_LockerHolds, 2
    ListMenuShow
    WorkCmpConst 0x8020, 100
    VMJumpIf CMP_EQ, L_LockerStore
    WorkCmpConst 0x8020, 20
    VMJumpIf CMP_GE, L_LockerClose
    WorkGet 0x8027, 0x8020
    WorkGet 0x8028, 0x8020
    VMCall L_LockerGet
    WorkGet 0x8022, 0x8026
    WorkAnd 0x8022, 1023
    WordSetItemNameEx 0, 0x8022, 1, 0
    EfuSpecial EFU_SPECIAL_SELL_PRICE, 0x8022, 0, 0, 0x8023
    WordSetNumber 1, 0x8023, 5
    SystemMsg Efu_Text_LockerWhat, 2
    ListMenuAnchorTopRight 31, 7, 0, 1, 0x8024
    ListMenuAdd Efu_Text_LockerTake, 65535, 0
    ListMenuAdd Efu_Text_LockerSell, 65535, 1
    ListMenuAdd Efu_Text_LockerCancel, 65535, 2
    ListMenuShow
    WorkCmpConst 0x8024, 0
    VMJumpIf CMP_EQ, L_LockerTake
    WorkCmpConst 0x8024, 1
    VMJumpIf CMP_EQ, L_LockerSell
    VMJump L_LockerMenu

L_LockerTake:
    ItemCheckSpace 0x8022, 1, 0x8025
    WorkCmpConst 0x8025, 0
    VMJumpIf CMP_EQ, L_LockerBagFull
    ItemAdd 0x8022, 1, 0x8025
    SEPlay SEQ_SE_DECIDE1
    VMJump L_LockerTakeOne

L_LockerSell:
    WorkCmpConst 0x8023, 0
    VMJumpIf CMP_EQ, L_LockerNoSale
    MoneyAdd 0x8023
    MoneyWinUpdate
    SEPlay SEQ_SE_SYS_22
// One of the slot's item is gone: the slot loses one, and empties under a count of one
L_LockerTakeOne:
    WorkSub 0x8026, 1024
    WorkCmpConst 0x8026, 1024
    VMJumpIf CMP_GE, L_LockerTakeSet
    WorkSetConst 0x8026, 0
L_LockerTakeSet:
    VMCall L_LockerSet
    VMCall L_LockerCompact
    VMJump L_LockerMenu

L_LockerBagFull:
    SystemMsg Efu_Text_LockerBagFull, 2
    LastKeyWait
    VMJump L_LockerMenu

L_LockerNoSale:
    SystemMsg Efu_Text_LockerNoSale, 2
    LastKeyWait
    VMJump L_LockerMenu

// Store everything: the bag's holdable item, then each Pokémon's held item, while there is room. 0x802a counts what
// went in and 0x802b what didn't fit
L_LockerStore:
    WorkSetConst 0x802a, 0
    WorkSetConst 0x802b, 0
    EfuSpecial EFU_SPECIAL_BAG_ITEM, 0, 0, 0, 0x8030
    WorkCmpConst 0x8030, 0
    VMJumpIf CMP_EQ, L_LockerStoreParty
    VMCall L_LockerPut
    WorkCmpConst 0x8031, 0
    VMJumpIf CMP_EQ, L_LockerStoreBagFull
    ItemSub 0x8030, 1, 0x8025
    WorkAdd 0x802a, 1
    VMJump L_LockerStoreParty
L_LockerStoreBagFull:
    WorkAdd 0x802b, 1
L_LockerStoreParty:
    WorkSetConst 0x802c, 0
L_LockerStorePkm:
    EfuSpecial EFU_SPECIAL_HELD_ITEM, 0x802c, 0, 0, 0x8030
    WorkCmpConst 0x8030, 0
    VMJumpIf CMP_EQ, L_LockerStoreNext
    VMCall L_LockerPut
    WorkCmpConst 0x8031, 0
    VMJumpIf CMP_EQ, L_LockerStorePkmFull
    EfuSpecial EFU_SPECIAL_TAKE_HELD, 0x802c, 0, 0, 0x8031
    WorkAdd 0x802a, 1
    VMJump L_LockerStoreNext
L_LockerStorePkmFull:
    WorkAdd 0x802b, 1
L_LockerStoreNext:
    WorkAdd 0x802c, 1
    WorkCmpConst 0x802c, 6
    VMJumpIf CMP_LT, L_LockerStorePkm
    WordSetNumber 0, 0x802a, 2
    WordSetNumber 1, 0x802b, 2
    WorkCmpConst 0x802b, 0
    VMJumpIf CMP_NE, L_LockerStoredFull
    WorkCmpConst 0x802a, 0
    VMJumpIf CMP_EQ, L_LockerNothing
    SEPlay SEQ_SE_DECIDE1
    VMJump L_LockerMenu

L_LockerStoredFull:
    SystemMsg Efu_Text_LockerStoredFull, 2
    LastKeyWait
    VMJump L_LockerMenu

L_LockerNothing:
    SystemMsg Efu_Text_LockerNothing, 2
    LastKeyWait
    VMJump L_LockerMenu

L_LockerClose:
    SystemMsgClose
    MoneyWinClose
    ActorsUnpauseAll
    VMHalt

L_LockerList:
    WorkSetConst 0x8029, 0
    WorkCmpConst 0x41a7, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a7
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a7
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 0
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a6, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a6
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a6
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 1
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a5, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a5
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a5
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 2
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a4, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a4
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a4
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 3
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a3, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a3
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a3
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 4
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a2, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a2
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a2
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 5
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a1, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a1
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a1
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 6
    WorkAdd 0x8029, 1
    WorkCmpConst 0x41a0, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x41a0
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x41a0
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 7
    WorkAdd 0x8029, 1
    WorkCmpConst 0x419e, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x419e
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x419e
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 8
    WorkAdd 0x8029, 1
    WorkCmpConst 0x419d, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x419d
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x419d
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 9
    WorkAdd 0x8029, 1
    WorkCmpConst 0x419c, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x419c
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x419c
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 10
    WorkAdd 0x8029, 1
    WorkCmpConst 0x419b, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x419b
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x419b
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 11
    WorkAdd 0x8029, 1
    WorkCmpConst 0x419a, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x419a
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x419a
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 12
    WorkAdd 0x8029, 1
    WorkCmpConst 0x4199, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x4199
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x4199
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 13
    WorkAdd 0x8029, 1
    WorkCmpConst 0x4198, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x4198
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x4198
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 14
    WorkAdd 0x8029, 1
    WorkCmpConst 0x4197, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x4197
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x4197
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 15
    WorkAdd 0x8029, 1
    WorkCmpConst 0x4193, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x4193
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x4193
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 16
    WorkAdd 0x8029, 1
    WorkCmpConst 0x418b, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x418b
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x418b
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 17
    WorkAdd 0x8029, 1
    WorkCmpConst 0x4180, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x4180
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x4180
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 18
    WorkAdd 0x8029, 1
    WorkCmpConst 0x4177, 0
    VMJumpIf CMP_EQ, L_LockerListDone
    WorkGet 0x8022, 0x4177
    WorkAnd 0x8022, 1023
    WorkGet 0x8021, 0x4177
    WorkDiv 0x8021, 1024
    WordSetItemNameEx 0, 0x8022, 1, 0
    WordSetNumber 1, 0x8021, 2
    ListMenuAdd Efu_Text_LockerSlot, 65535, 19
    WorkAdd 0x8029, 1
L_LockerListDone:
    VMReturn
L_LockerGet:
    WorkCmpConst 0x8027, 0
    VMJumpIf CMP_EQ, L_LockerGet_0
    WorkCmpConst 0x8027, 1
    VMJumpIf CMP_EQ, L_LockerGet_1
    WorkCmpConst 0x8027, 2
    VMJumpIf CMP_EQ, L_LockerGet_2
    WorkCmpConst 0x8027, 3
    VMJumpIf CMP_EQ, L_LockerGet_3
    WorkCmpConst 0x8027, 4
    VMJumpIf CMP_EQ, L_LockerGet_4
    WorkCmpConst 0x8027, 5
    VMJumpIf CMP_EQ, L_LockerGet_5
    WorkCmpConst 0x8027, 6
    VMJumpIf CMP_EQ, L_LockerGet_6
    WorkCmpConst 0x8027, 7
    VMJumpIf CMP_EQ, L_LockerGet_7
    WorkCmpConst 0x8027, 8
    VMJumpIf CMP_EQ, L_LockerGet_8
    WorkCmpConst 0x8027, 9
    VMJumpIf CMP_EQ, L_LockerGet_9
    WorkCmpConst 0x8027, 10
    VMJumpIf CMP_EQ, L_LockerGet_10
    WorkCmpConst 0x8027, 11
    VMJumpIf CMP_EQ, L_LockerGet_11
    WorkCmpConst 0x8027, 12
    VMJumpIf CMP_EQ, L_LockerGet_12
    WorkCmpConst 0x8027, 13
    VMJumpIf CMP_EQ, L_LockerGet_13
    WorkCmpConst 0x8027, 14
    VMJumpIf CMP_EQ, L_LockerGet_14
    WorkCmpConst 0x8027, 15
    VMJumpIf CMP_EQ, L_LockerGet_15
    WorkCmpConst 0x8027, 16
    VMJumpIf CMP_EQ, L_LockerGet_16
    WorkCmpConst 0x8027, 17
    VMJumpIf CMP_EQ, L_LockerGet_17
    WorkCmpConst 0x8027, 18
    VMJumpIf CMP_EQ, L_LockerGet_18
    WorkCmpConst 0x8027, 19
    VMJumpIf CMP_EQ, L_LockerGet_19
    VMReturn
L_LockerGet_0:
    WorkGet 0x8026, 0x41a7
    VMReturn
L_LockerGet_1:
    WorkGet 0x8026, 0x41a6
    VMReturn
L_LockerGet_2:
    WorkGet 0x8026, 0x41a5
    VMReturn
L_LockerGet_3:
    WorkGet 0x8026, 0x41a4
    VMReturn
L_LockerGet_4:
    WorkGet 0x8026, 0x41a3
    VMReturn
L_LockerGet_5:
    WorkGet 0x8026, 0x41a2
    VMReturn
L_LockerGet_6:
    WorkGet 0x8026, 0x41a1
    VMReturn
L_LockerGet_7:
    WorkGet 0x8026, 0x41a0
    VMReturn
L_LockerGet_8:
    WorkGet 0x8026, 0x419e
    VMReturn
L_LockerGet_9:
    WorkGet 0x8026, 0x419d
    VMReturn
L_LockerGet_10:
    WorkGet 0x8026, 0x419c
    VMReturn
L_LockerGet_11:
    WorkGet 0x8026, 0x419b
    VMReturn
L_LockerGet_12:
    WorkGet 0x8026, 0x419a
    VMReturn
L_LockerGet_13:
    WorkGet 0x8026, 0x4199
    VMReturn
L_LockerGet_14:
    WorkGet 0x8026, 0x4198
    VMReturn
L_LockerGet_15:
    WorkGet 0x8026, 0x4197
    VMReturn
L_LockerGet_16:
    WorkGet 0x8026, 0x4193
    VMReturn
L_LockerGet_17:
    WorkGet 0x8026, 0x418b
    VMReturn
L_LockerGet_18:
    WorkGet 0x8026, 0x4180
    VMReturn
L_LockerGet_19:
    WorkGet 0x8026, 0x4177
    VMReturn
L_LockerSet:
    WorkCmpConst 0x8027, 0
    VMJumpIf CMP_EQ, L_LockerSet_0
    WorkCmpConst 0x8027, 1
    VMJumpIf CMP_EQ, L_LockerSet_1
    WorkCmpConst 0x8027, 2
    VMJumpIf CMP_EQ, L_LockerSet_2
    WorkCmpConst 0x8027, 3
    VMJumpIf CMP_EQ, L_LockerSet_3
    WorkCmpConst 0x8027, 4
    VMJumpIf CMP_EQ, L_LockerSet_4
    WorkCmpConst 0x8027, 5
    VMJumpIf CMP_EQ, L_LockerSet_5
    WorkCmpConst 0x8027, 6
    VMJumpIf CMP_EQ, L_LockerSet_6
    WorkCmpConst 0x8027, 7
    VMJumpIf CMP_EQ, L_LockerSet_7
    WorkCmpConst 0x8027, 8
    VMJumpIf CMP_EQ, L_LockerSet_8
    WorkCmpConst 0x8027, 9
    VMJumpIf CMP_EQ, L_LockerSet_9
    WorkCmpConst 0x8027, 10
    VMJumpIf CMP_EQ, L_LockerSet_10
    WorkCmpConst 0x8027, 11
    VMJumpIf CMP_EQ, L_LockerSet_11
    WorkCmpConst 0x8027, 12
    VMJumpIf CMP_EQ, L_LockerSet_12
    WorkCmpConst 0x8027, 13
    VMJumpIf CMP_EQ, L_LockerSet_13
    WorkCmpConst 0x8027, 14
    VMJumpIf CMP_EQ, L_LockerSet_14
    WorkCmpConst 0x8027, 15
    VMJumpIf CMP_EQ, L_LockerSet_15
    WorkCmpConst 0x8027, 16
    VMJumpIf CMP_EQ, L_LockerSet_16
    WorkCmpConst 0x8027, 17
    VMJumpIf CMP_EQ, L_LockerSet_17
    WorkCmpConst 0x8027, 18
    VMJumpIf CMP_EQ, L_LockerSet_18
    WorkCmpConst 0x8027, 19
    VMJumpIf CMP_EQ, L_LockerSet_19
    VMReturn
L_LockerSet_0:
    WorkSet 0x41a7, 0x8026
    VMReturn
L_LockerSet_1:
    WorkSet 0x41a6, 0x8026
    VMReturn
L_LockerSet_2:
    WorkSet 0x41a5, 0x8026
    VMReturn
L_LockerSet_3:
    WorkSet 0x41a4, 0x8026
    VMReturn
L_LockerSet_4:
    WorkSet 0x41a3, 0x8026
    VMReturn
L_LockerSet_5:
    WorkSet 0x41a2, 0x8026
    VMReturn
L_LockerSet_6:
    WorkSet 0x41a1, 0x8026
    VMReturn
L_LockerSet_7:
    WorkSet 0x41a0, 0x8026
    VMReturn
L_LockerSet_8:
    WorkSet 0x419e, 0x8026
    VMReturn
L_LockerSet_9:
    WorkSet 0x419d, 0x8026
    VMReturn
L_LockerSet_10:
    WorkSet 0x419c, 0x8026
    VMReturn
L_LockerSet_11:
    WorkSet 0x419b, 0x8026
    VMReturn
L_LockerSet_12:
    WorkSet 0x419a, 0x8026
    VMReturn
L_LockerSet_13:
    WorkSet 0x4199, 0x8026
    VMReturn
L_LockerSet_14:
    WorkSet 0x4198, 0x8026
    VMReturn
L_LockerSet_15:
    WorkSet 0x4197, 0x8026
    VMReturn
L_LockerSet_16:
    WorkSet 0x4193, 0x8026
    VMReturn
L_LockerSet_17:
    WorkSet 0x418b, 0x8026
    VMReturn
L_LockerSet_18:
    WorkSet 0x4180, 0x8026
    VMReturn
L_LockerSet_19:
    WorkSet 0x4177, 0x8026
    VMReturn
L_LockerPut:
    WorkSetConst 0x8031, 1
    WorkGet 0x8032, 0x41a7
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_0
    WorkCmpConst 0x41a7, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_0
    WorkAdd 0x41a7, 1024
    VMReturn
L_LockerPutNext_0:
    WorkGet 0x8032, 0x41a6
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_1
    WorkCmpConst 0x41a6, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_1
    WorkAdd 0x41a6, 1024
    VMReturn
L_LockerPutNext_1:
    WorkGet 0x8032, 0x41a5
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_2
    WorkCmpConst 0x41a5, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_2
    WorkAdd 0x41a5, 1024
    VMReturn
L_LockerPutNext_2:
    WorkGet 0x8032, 0x41a4
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_3
    WorkCmpConst 0x41a4, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_3
    WorkAdd 0x41a4, 1024
    VMReturn
L_LockerPutNext_3:
    WorkGet 0x8032, 0x41a3
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_4
    WorkCmpConst 0x41a3, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_4
    WorkAdd 0x41a3, 1024
    VMReturn
L_LockerPutNext_4:
    WorkGet 0x8032, 0x41a2
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_5
    WorkCmpConst 0x41a2, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_5
    WorkAdd 0x41a2, 1024
    VMReturn
L_LockerPutNext_5:
    WorkGet 0x8032, 0x41a1
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_6
    WorkCmpConst 0x41a1, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_6
    WorkAdd 0x41a1, 1024
    VMReturn
L_LockerPutNext_6:
    WorkGet 0x8032, 0x41a0
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_7
    WorkCmpConst 0x41a0, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_7
    WorkAdd 0x41a0, 1024
    VMReturn
L_LockerPutNext_7:
    WorkGet 0x8032, 0x419e
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_8
    WorkCmpConst 0x419e, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_8
    WorkAdd 0x419e, 1024
    VMReturn
L_LockerPutNext_8:
    WorkGet 0x8032, 0x419d
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_9
    WorkCmpConst 0x419d, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_9
    WorkAdd 0x419d, 1024
    VMReturn
L_LockerPutNext_9:
    WorkGet 0x8032, 0x419c
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_10
    WorkCmpConst 0x419c, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_10
    WorkAdd 0x419c, 1024
    VMReturn
L_LockerPutNext_10:
    WorkGet 0x8032, 0x419b
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_11
    WorkCmpConst 0x419b, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_11
    WorkAdd 0x419b, 1024
    VMReturn
L_LockerPutNext_11:
    WorkGet 0x8032, 0x419a
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_12
    WorkCmpConst 0x419a, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_12
    WorkAdd 0x419a, 1024
    VMReturn
L_LockerPutNext_12:
    WorkGet 0x8032, 0x4199
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_13
    WorkCmpConst 0x4199, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_13
    WorkAdd 0x4199, 1024
    VMReturn
L_LockerPutNext_13:
    WorkGet 0x8032, 0x4198
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_14
    WorkCmpConst 0x4198, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_14
    WorkAdd 0x4198, 1024
    VMReturn
L_LockerPutNext_14:
    WorkGet 0x8032, 0x4197
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_15
    WorkCmpConst 0x4197, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_15
    WorkAdd 0x4197, 1024
    VMReturn
L_LockerPutNext_15:
    WorkGet 0x8032, 0x4193
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_16
    WorkCmpConst 0x4193, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_16
    WorkAdd 0x4193, 1024
    VMReturn
L_LockerPutNext_16:
    WorkGet 0x8032, 0x418b
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_17
    WorkCmpConst 0x418b, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_17
    WorkAdd 0x418b, 1024
    VMReturn
L_LockerPutNext_17:
    WorkGet 0x8032, 0x4180
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_18
    WorkCmpConst 0x4180, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_18
    WorkAdd 0x4180, 1024
    VMReturn
L_LockerPutNext_18:
    WorkGet 0x8032, 0x4177
    WorkAnd 0x8032, 1023
    WorkCmpWork 0x8032, 0x8030
    VMJumpIf CMP_NE, L_LockerPutNext_19
    WorkCmpConst 0x4177, 64512
    VMJumpIf CMP_GE, L_LockerPutNext_19
    WorkAdd 0x4177, 1024
    VMReturn
L_LockerPutNext_19:
    WorkCmpConst 0x41a7, 0
    VMJumpIf CMP_NE, L_LockerPutFree_0
    WorkSet 0x41a7, 0x8030
    WorkAdd 0x41a7, 1024
    VMReturn
L_LockerPutFree_0:
    WorkCmpConst 0x41a6, 0
    VMJumpIf CMP_NE, L_LockerPutFree_1
    WorkSet 0x41a6, 0x8030
    WorkAdd 0x41a6, 1024
    VMReturn
L_LockerPutFree_1:
    WorkCmpConst 0x41a5, 0
    VMJumpIf CMP_NE, L_LockerPutFree_2
    WorkSet 0x41a5, 0x8030
    WorkAdd 0x41a5, 1024
    VMReturn
L_LockerPutFree_2:
    WorkCmpConst 0x41a4, 0
    VMJumpIf CMP_NE, L_LockerPutFree_3
    WorkSet 0x41a4, 0x8030
    WorkAdd 0x41a4, 1024
    VMReturn
L_LockerPutFree_3:
    WorkCmpConst 0x41a3, 0
    VMJumpIf CMP_NE, L_LockerPutFree_4
    WorkSet 0x41a3, 0x8030
    WorkAdd 0x41a3, 1024
    VMReturn
L_LockerPutFree_4:
    WorkCmpConst 0x41a2, 0
    VMJumpIf CMP_NE, L_LockerPutFree_5
    WorkSet 0x41a2, 0x8030
    WorkAdd 0x41a2, 1024
    VMReturn
L_LockerPutFree_5:
    WorkCmpConst 0x41a1, 0
    VMJumpIf CMP_NE, L_LockerPutFree_6
    WorkSet 0x41a1, 0x8030
    WorkAdd 0x41a1, 1024
    VMReturn
L_LockerPutFree_6:
    WorkCmpConst 0x41a0, 0
    VMJumpIf CMP_NE, L_LockerPutFree_7
    WorkSet 0x41a0, 0x8030
    WorkAdd 0x41a0, 1024
    VMReturn
L_LockerPutFree_7:
    WorkCmpConst 0x419e, 0
    VMJumpIf CMP_NE, L_LockerPutFree_8
    WorkSet 0x419e, 0x8030
    WorkAdd 0x419e, 1024
    VMReturn
L_LockerPutFree_8:
    WorkCmpConst 0x419d, 0
    VMJumpIf CMP_NE, L_LockerPutFree_9
    WorkSet 0x419d, 0x8030
    WorkAdd 0x419d, 1024
    VMReturn
L_LockerPutFree_9:
    WorkCmpConst 0x419c, 0
    VMJumpIf CMP_NE, L_LockerPutFree_10
    WorkSet 0x419c, 0x8030
    WorkAdd 0x419c, 1024
    VMReturn
L_LockerPutFree_10:
    WorkCmpConst 0x419b, 0
    VMJumpIf CMP_NE, L_LockerPutFree_11
    WorkSet 0x419b, 0x8030
    WorkAdd 0x419b, 1024
    VMReturn
L_LockerPutFree_11:
    WorkCmpConst 0x419a, 0
    VMJumpIf CMP_NE, L_LockerPutFree_12
    WorkSet 0x419a, 0x8030
    WorkAdd 0x419a, 1024
    VMReturn
L_LockerPutFree_12:
    WorkCmpConst 0x4199, 0
    VMJumpIf CMP_NE, L_LockerPutFree_13
    WorkSet 0x4199, 0x8030
    WorkAdd 0x4199, 1024
    VMReturn
L_LockerPutFree_13:
    WorkCmpConst 0x4198, 0
    VMJumpIf CMP_NE, L_LockerPutFree_14
    WorkSet 0x4198, 0x8030
    WorkAdd 0x4198, 1024
    VMReturn
L_LockerPutFree_14:
    WorkCmpConst 0x4197, 0
    VMJumpIf CMP_NE, L_LockerPutFree_15
    WorkSet 0x4197, 0x8030
    WorkAdd 0x4197, 1024
    VMReturn
L_LockerPutFree_15:
    WorkCmpConst 0x4193, 0
    VMJumpIf CMP_NE, L_LockerPutFree_16
    WorkSet 0x4193, 0x8030
    WorkAdd 0x4193, 1024
    VMReturn
L_LockerPutFree_16:
    WorkCmpConst 0x418b, 0
    VMJumpIf CMP_NE, L_LockerPutFree_17
    WorkSet 0x418b, 0x8030
    WorkAdd 0x418b, 1024
    VMReturn
L_LockerPutFree_17:
    WorkCmpConst 0x4180, 0
    VMJumpIf CMP_NE, L_LockerPutFree_18
    WorkSet 0x4180, 0x8030
    WorkAdd 0x4180, 1024
    VMReturn
L_LockerPutFree_18:
    WorkCmpConst 0x4177, 0
    VMJumpIf CMP_NE, L_LockerPutFree_19
    WorkSet 0x4177, 0x8030
    WorkAdd 0x4177, 1024
    VMReturn
L_LockerPutFree_19:
    WorkSetConst 0x8031, 0
    VMReturn
L_LockerCompact:
    WorkCmpConst 0x41a7, 0
    VMJumpIf CMP_NE, L_LockerCompact_0
    WorkSet 0x41a7, 0x41a6
    WorkSetConst 0x41a6, 0
L_LockerCompact_0:
    WorkCmpConst 0x41a6, 0
    VMJumpIf CMP_NE, L_LockerCompact_1
    WorkSet 0x41a6, 0x41a5
    WorkSetConst 0x41a5, 0
L_LockerCompact_1:
    WorkCmpConst 0x41a5, 0
    VMJumpIf CMP_NE, L_LockerCompact_2
    WorkSet 0x41a5, 0x41a4
    WorkSetConst 0x41a4, 0
L_LockerCompact_2:
    WorkCmpConst 0x41a4, 0
    VMJumpIf CMP_NE, L_LockerCompact_3
    WorkSet 0x41a4, 0x41a3
    WorkSetConst 0x41a3, 0
L_LockerCompact_3:
    WorkCmpConst 0x41a3, 0
    VMJumpIf CMP_NE, L_LockerCompact_4
    WorkSet 0x41a3, 0x41a2
    WorkSetConst 0x41a2, 0
L_LockerCompact_4:
    WorkCmpConst 0x41a2, 0
    VMJumpIf CMP_NE, L_LockerCompact_5
    WorkSet 0x41a2, 0x41a1
    WorkSetConst 0x41a1, 0
L_LockerCompact_5:
    WorkCmpConst 0x41a1, 0
    VMJumpIf CMP_NE, L_LockerCompact_6
    WorkSet 0x41a1, 0x41a0
    WorkSetConst 0x41a0, 0
L_LockerCompact_6:
    WorkCmpConst 0x41a0, 0
    VMJumpIf CMP_NE, L_LockerCompact_7
    WorkSet 0x41a0, 0x419e
    WorkSetConst 0x419e, 0
L_LockerCompact_7:
    WorkCmpConst 0x419e, 0
    VMJumpIf CMP_NE, L_LockerCompact_8
    WorkSet 0x419e, 0x419d
    WorkSetConst 0x419d, 0
L_LockerCompact_8:
    WorkCmpConst 0x419d, 0
    VMJumpIf CMP_NE, L_LockerCompact_9
    WorkSet 0x419d, 0x419c
    WorkSetConst 0x419c, 0
L_LockerCompact_9:
    WorkCmpConst 0x419c, 0
    VMJumpIf CMP_NE, L_LockerCompact_10
    WorkSet 0x419c, 0x419b
    WorkSetConst 0x419b, 0
L_LockerCompact_10:
    WorkCmpConst 0x419b, 0
    VMJumpIf CMP_NE, L_LockerCompact_11
    WorkSet 0x419b, 0x419a
    WorkSetConst 0x419a, 0
L_LockerCompact_11:
    WorkCmpConst 0x419a, 0
    VMJumpIf CMP_NE, L_LockerCompact_12
    WorkSet 0x419a, 0x4199
    WorkSetConst 0x4199, 0
L_LockerCompact_12:
    WorkCmpConst 0x4199, 0
    VMJumpIf CMP_NE, L_LockerCompact_13
    WorkSet 0x4199, 0x4198
    WorkSetConst 0x4198, 0
L_LockerCompact_13:
    WorkCmpConst 0x4198, 0
    VMJumpIf CMP_NE, L_LockerCompact_14
    WorkSet 0x4198, 0x4197
    WorkSetConst 0x4197, 0
L_LockerCompact_14:
    WorkCmpConst 0x4197, 0
    VMJumpIf CMP_NE, L_LockerCompact_15
    WorkSet 0x4197, 0x4193
    WorkSetConst 0x4193, 0
L_LockerCompact_15:
    WorkCmpConst 0x4193, 0
    VMJumpIf CMP_NE, L_LockerCompact_16
    WorkSet 0x4193, 0x418b
    WorkSetConst 0x418b, 0
L_LockerCompact_16:
    WorkCmpConst 0x418b, 0
    VMJumpIf CMP_NE, L_LockerCompact_17
    WorkSet 0x418b, 0x4180
    WorkSetConst 0x4180, 0
L_LockerCompact_17:
    WorkCmpConst 0x4180, 0
    VMJumpIf CMP_NE, L_LockerCompact_18
    WorkSet 0x4180, 0x4177
    WorkSetConst 0x4177, 0
L_LockerCompact_18:
    VMReturn

// The world editor's locked doors (EFU_SCRIPT_LOCK_FIRST): each lock's sign, written by gen_efu.py from
// tools/efu/world_locks.json
Script_LockNone:
    VMHalt
