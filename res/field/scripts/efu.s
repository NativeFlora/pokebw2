#include "asm/field_script.inc"
#include "text/script/efu.h"

// Escape from Unova's own script commands (EVCMD_TABLE in src/ov012/scrcmd_vm.c, from 0x2f3; each also needs
// a row of EVCMD_PERM_TABLE in src/ov012/script_sys.c)
    .macro EfuPokePartyRecoverHalf
    FieldCommand 0x2f3
    .endm
// Escape from Unova's own scripts, global IDs from 11000 (EFU_SCRIPT_* in include/efu.h)
    ScriptEntry Script_NewGameSetup
    ScriptEntry Script_NewGameStart
    ScriptEntry Script_BoardedDoor
    ScriptEntry Script_Bed
    ScriptEntriesEnd

// Runs before the first fade-in of a new game
Script_NewGameSetup:
    ActorsPauseAll
    FinishAllEvents
    ActorsUnpauseAll
    VMHalt

// Runs after the first fade-in of a new game: the player picks the Pokémon they were left with
Script_NewGameStart:
    ActorsPauseAll
    SystemMsg Efu_Text_Wake, 2
    LastKeyWait
    VMCall L_ChooseStarter
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
