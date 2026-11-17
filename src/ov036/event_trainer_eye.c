// The Trainers who see the player: finding them, and the event that walks them up to the player for the battle. The
// name is the ROM's own, from GFL_HeapAllocate's file argument. Function names from swan
// (https://github.com/ds-pokemon-hacking/swan, GPL-3.0)
#include "efu.h"
#include "types.h"
#include "constants/battle.h"
#include "field/encounter.h"
#include "field/event_trainer_eye.h"
#include "field/field.h"
#include "field/field_acmd.h"
#include "field/field_actor.h"
#include "field/field_comm_actor.h"
#include "field/field_effect.h"
#include "field/field_event.h"
#include "field/field_script_event.h"
#include "field/pair_sys.h"
#include "field/player_state.h"
#include "field/trainer_script.h"
#include "field/zone.h"
#include "gfl/heap.h"
#include "save/event_work.h"
#include "save/playtime.h"
#include "save/save_control.h"
#include "system/game_data.h"
#include "system/game_event.h"
#include "system/game_system.h"

// The script of a Trainer's battle, and of the Trainer whose actor uses SCRID_SPECIAL_TRAINER
#define SCRID_TRAINER_CLASH 0xee8
#define SCRID_SPECIAL_TRAINER_CLASH 0x29f8

enum {
    TRAINER_EYE_SEQ_START_MOVE,
    TRAINER_EYE_SEQ_FORCE_TRAINER_DIR,
    TRAINER_EYE_SEQ_DECIDE_JUMP_OUT,
    TRAINER_EYE_SEQ_TURN_TRAINER,
    TRAINER_EYE_SEQ_WAIT_TURN_TRAINER,
    TRAINER_EYE_SEQ_START_TERRAIN_EFFECT,
    TRAINER_EYE_SEQ_WAIT_TERRAIN_EFFECT,
    TRAINER_EYE_SEQ_JUMP_OUT,
    TRAINER_EYE_SEQ_WAIT_JUMP_OUT,
    TRAINER_EYE_SEQ_WAIT_30F,
    TRAINER_EYE_SEQ_DECIDE_WALK_OR_STOP,
    TRAINER_EYE_SEQ_WALK_ONE_STEP_TO_PLAYER,
    TRAINER_EYE_SEQ_DECREMENT_CLASH_DIST,
    TRAINER_EYE_SEQ_WAIT_8F,
    TRAINER_EYE_SEQ_TURN_PLAYER,
    TRAINER_EYE_SEQ_WAIT_TURN_PLAYER,
    TRAINER_EYE_SEQ_SET_IDLE_MOVE_CODE,
    TRAINER_EYE_SEQ_FINISH,
};

struct EventTrainerEyeWork {
    int seq;
    BOOL finished;
    TrainerClashData data;
    u32 unk20;
    // Set for the second Trainer of two, who leaves the player facing the first unless they battle at once
    BOOL isPair;
    int timer;
    FieldEffectTask *emote;
    Field *field;
    FieldPlayer *player;
};

typedef struct {
    EventTrainerEyeWork *eyes[2];
} EventTrainerEyeEvent;

typedef int (*TrainerLineOfSightFunc)(s16 range, const GridPos *trainer, const GridPos *player);
typedef BOOL (*EventTrainerEyeRoutine)(EventTrainerEyeWork *work);

static BOOL EventTrainerEye_FindClashActor(Field *field, FieldActor *exclude, TrainerClashData *data);
static int EventTrainerEye_CheckActorClash(EncountSystem *encounter, FieldActor *actor, FieldActor *player,
                                           u16 *dirOut);
static int EventTrainerEye_CalcLineOfSight(u16 dir, s16 range, const GridPos *trainer, const GridPos *player);
static int EventTrainerEye_CalcLineOfSight_U(s16 range, const GridPos *trainer, const GridPos *player);
static int EventTrainerEye_CalcLineOfSight_D(s16 range, const GridPos *trainer, const GridPos *player);
static int EventTrainerEye_CalcLineOfSight_L(s16 range, const GridPos *trainer, const GridPos *player);
static int EventTrainerEye_CalcLineOfSight_R(s16 range, const GridPos *trainer, const GridPos *player);
static BOOL EventTrainerEyeSub_StartMove(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_ForceTrainerDir(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_DecideJumpOut(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_TurnTrainer(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_WaitTurnTrainer(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_StartTerrainEffect(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_WaitTerrainEffect(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_JumpOut(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_WaitJumpOut(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_Wait30F(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_DecideWalkOrStop(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_WalkOneStepToPlayer(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_DecrementClashDist(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_Wait8F(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_TurnPlayer(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_WaitTurnPlayer(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_SetIdleMoveCode(EventTrainerEyeWork *work);
static BOOL EventTrainerEyeSub_Finish(EventTrainerEyeWork *work);
static BOOL EventTrainerEye_Update(EventTrainerEyeWork *work);
static GameEventReturnCode EventTrainerEye_Callback(GameEvent *event, u32 *state, void *data);
static u16 EventTrainerEye_GetSightType(FieldActor *actor);
static BOOL EventTrainerEye_CheckPathObstacle(FieldActor *actor, u16 dir, int range, EncountSystem *encounter);
static u16 EventTrainerEye_UsesSpecialScript(FieldActor *actor);
static BOOL CheckTrainerAlreadyDefeated(Field *field, FieldActor *actor);
static void InitFieldScriptTrainerSetup(TrainerClashData *data, FieldActor *actor, int range, u16 dir);
static FieldActor *EventTrainerEye_FindPairedTrainer(FieldActor *trainer, u16 trainerId);
static GameEvent *CreateTrainerClashEvent(Field *field, FieldActor *actor);
static BOOL Efu_IsOnRaid(Field *field);
static void EfuScav_StartChase(Field *field, FieldActor *actor);
static void EfuScav_StopChase(Field *field, FieldActor *actor);
static BOOL EfuScav_CanSee(FieldActor *actor, const GridPos *pos, const GridPos *playerPos);
static u16 EfuScav_DirTo(const GridPos *from, const GridPos *to, int *dist);
static BOOL EfuScav_CanStep(FieldActor *actor, const GridPos *pos, u16 dir);
static void EfuScav_Spawn(Field *field, const GridPos *playerPos);

static const TrainerLineOfSightFunc TRAINER_LOS_DIST_FUNCTIONS[4] = {
    EventTrainerEye_CalcLineOfSight_U,
    EventTrainerEye_CalcLineOfSight_D,
    EventTrainerEye_CalcLineOfSight_L,
    EventTrainerEye_CalcLineOfSight_R,
};

// clang-format off
static const EventTrainerEyeRoutine EVENT_TRAINER_EYE_ROUTINES[] = {
    EventTrainerEyeSub_StartMove,
    EventTrainerEyeSub_ForceTrainerDir,
    EventTrainerEyeSub_DecideJumpOut,
    EventTrainerEyeSub_TurnTrainer,
    EventTrainerEyeSub_WaitTurnTrainer,
    EventTrainerEyeSub_StartTerrainEffect,
    EventTrainerEyeSub_WaitTerrainEffect,
    EventTrainerEyeSub_JumpOut,
    EventTrainerEyeSub_WaitJumpOut,
    EventTrainerEyeSub_Wait30F,
    EventTrainerEyeSub_DecideWalkOrStop,
    EventTrainerEyeSub_WalkOneStepToPlayer,
    EventTrainerEyeSub_DecrementClashDist,
    EventTrainerEyeSub_Wait8F,
    EventTrainerEyeSub_TurnPlayer,
    EventTrainerEyeSub_WaitTurnPlayer,
    EventTrainerEyeSub_SetIdleMoveCode,
    EventTrainerEyeSub_Finish,
};

// clang-format on

GameEvent *EventTrainerEye_CheckAll(Field *field) {
    TrainerClashData data;
    TrainerClashData partner;
    u32 battleCount;
    int battleType;
    GameEvent *event = NULL;
    GameData *gameData = GSYS_GetGameData(Field_GetGameSystem(field));

    if (EventTrainerEye_FindClashActor(field, NULL, &data) == TRUE) {
        battleCount = FieldEventProvider_CountAlivePartyMembers(Field_GetGameSystem(field));
        if (EventTrainerEye_UsesSpecialScript(data.actor) == TRUE) {
            battleType = BTL_STYLE_SINGLE;
        } else {
            battleType = getBattleType(data.trainerId);
        }
        if (battleType == BTL_STYLE_SINGLE) {
            if (battleCount >= 1 && GetNowFollowerAllyTrID(gameData) != 0 &&
                EventTrainerEye_FindClashActor(field, data.actor, &partner) == TRUE) {
                event = CreateTrainerClashEvent(field, data.actor);
                data.kind = TRAINER_CLASH_WITH_PARTNER;
                SetupTrainerClashSlot(event, 0, &data);
                partner.kind = TRAINER_CLASH_WITH_PARTNER;
                SetupTrainerClashSlot(event, 1, &partner);
            } else if (battleCount < 2 || EventTrainerEye_FindClashActor(field, data.actor, &partner) == FALSE) {
                event = CreateTrainerClashEvent(field, data.actor);
                data.kind = TRAINER_CLASH_SINGLE;
                SetupTrainerClashSlot(event, 0, &data);
            } else {
                event = CreateTrainerClashEvent(field, data.actor);
                data.kind = TRAINER_CLASH_TWO_TRAINERS;
                SetupTrainerClashSlot(event, 0, &data);
                partner.kind = TRAINER_CLASH_TWO_TRAINERS;
                SetupTrainerClashSlot(event, 1, &partner);
            }
        } else if (battleType == BTL_STYLE_DOUBLE) {
            if (battleCount >= 2) {
                InitFieldScriptTrainerSetup(&partner, EventTrainerEye_FindPairedTrainer(data.actor, data.trainerId),
                                            data.range, data.dir);
                event = CreateTrainerClashEvent(field, data.actor);
                data.kind = TRAINER_CLASH_DOUBLE_PAIR;
                SetupTrainerClashSlot(event, 0, &data);
                partner.kind = TRAINER_CLASH_DOUBLE_PAIR;
                SetupTrainerClashSlot(event, 1, &partner);
            }
        } else if (battleType == BTL_STYLE_TRIPLE || battleType == BTL_STYLE_ROTATION) {
            if (battleCount >= 3) {
                event = CreateTrainerClashEvent(field, data.actor);
                data.kind = TRAINER_CLASH_SINGLE;
                SetupTrainerClashSlot(event, 0, &data);
            }
        }
    }
    return event;
}

int EventTrainerEyeSub_GetPlayerDistance(FieldActor *actor, u16 dir, int range, EncountSystem *encounter) {
    GridPos pos;
    GridPos playerPos;
    int dist;
    FieldActor *player = FindFieldActor(GetActorMModelSystem(actor), ACTOR_UID_PLAYER);

    if (player == NULL) {
        return -1;
    }
    FldAct_GetGPos(player, &playerPos);
    FldAct_GetGPos(actor, &pos);
    dist = EventTrainerEye_CalcLineOfSight(dir, range, &pos, &playerPos);
    if (dist != -1 && EventTrainerEye_CheckPathObstacle(actor, dir, dist, encounter) == TRUE) {
        dist = -1;
    }
    return dist;
}

// The first actor other than exclude that sees the player and is a Trainer still to battle
static BOOL EventTrainerEye_FindClashActor(Field *field, FieldActor *exclude, TrainerClashData *data) {
    FieldActor *actor;
    u32 index;
    u16 dir;
    int dist;
    EncountSystem *encounter = Field_GetEncountSystem(field);
    FieldActor *player = FieldPlayer_GetActor(Field_GetPlayer(field));
    MMSys *actorSys = Field_GetActorSystem(field);

    actor = NULL;
    index = 0;
    while (NextActor(actorSys, &actor, &index) == TRUE) {
        if (actor == player || (exclude != NULL && exclude == actor)) {
            continue;
        }
        // Escape from Unova: on a raid, a scav already on the player's trail is EventTrainerEye_EfuPursue's
        if (GetActorUserParam(actor, EFU_SCAV_PARAM_CHASE) != 0 && Efu_IsOnRaid(field)) {
            continue;
        }
        dist = EventTrainerEye_CheckActorClash(encounter, actor, player, &dir);
        if (dist != -1 && !CheckTrainerAlreadyDefeated(field, actor)) {
            InitFieldScriptTrainerSetup(data, actor, dist, dir);
            return TRUE;
        }
    }
    return FALSE;
}

// How far a Trainer sees the player, facing its way or, for one that looks around, any way; -1 if it doesn't
static int EventTrainerEye_CheckActorClash(EncountSystem *encounter, FieldActor *actor, FieldActor *player,
                                           u16 *dirOut) {
    GridPos pos;
    GridPos playerPos;
    u16 faceDir;
    int dist;
    s16 range;
    u16 dir;
    u16 eyeType = EventTrainerEye_GetSightType(actor);

    if (eyeType == TRAINER_SIGHT_FACING || eyeType == TRAINER_SIGHT_ALL_DIRS) {
        dir = DIR_UP;
        range = GetActorUserParam(actor, 0);
        FldAct_GetGPos(actor, &pos);
        FldAct_GetGPos(player, &playerPos);
        if (eyeType == TRAINER_SIGHT_FACING) {
            faceDir = GetActorFaceDir(actor);
            dist = EventTrainerEye_CalcLineOfSight(faceDir, range, &pos, &playerPos);
            if (dist != -1 && !EventTrainerEye_CheckPathObstacle(actor, faceDir, dist, encounter)) {
                *dirOut = faceDir;
                return dist;
            }
        } else {
            do {
                dist = EventTrainerEye_CalcLineOfSight(dir, range, &pos, &playerPos);
                if (dist != -1 && !EventTrainerEye_CheckPathObstacle(actor, dir, dist, encounter)) {
                    *dirOut = dir;
                    return dist;
                }
                dir++;
            } while (dir < 4);
        }
    }
    return -1;
}

static int EventTrainerEye_CalcLineOfSight(u16 dir, s16 range, const GridPos *trainer, const GridPos *player) {
    return TRAINER_LOS_DIST_FUNCTIONS[dir](range, trainer, player);
}

static int EventTrainerEye_CalcLineOfSight_U(s16 range, const GridPos *trainer, const GridPos *player) {
    if (trainer->x == player->x && trainer->y == player->y && player->z < trainer->z &&
        player->z >= trainer->z - range) {
        return trainer->z - player->z;
    }
    return -1;
}

static int EventTrainerEye_CalcLineOfSight_D(s16 range, const GridPos *trainer, const GridPos *player) {
    if (trainer->x == player->x && trainer->y == player->y && player->z > trainer->z &&
        player->z <= trainer->z + range) {
        return player->z - trainer->z;
    }
    return -1;
}

static int EventTrainerEye_CalcLineOfSight_L(s16 range, const GridPos *trainer, const GridPos *player) {
    if (trainer->z == player->z && trainer->y == player->y && player->x < trainer->x &&
        player->x >= trainer->x - range) {
        return trainer->x - player->x;
    }
    return -1;
}

static int EventTrainerEye_CalcLineOfSight_R(s16 range, const GridPos *trainer, const GridPos *player) {
    if (trainer->z == player->z && trainer->y == player->y && player->x > trainer->x &&
        player->x <= trainer->x + range) {
        return player->x - trainer->x;
    }
    return -1;
}

GameEvent *EventTrainerEye_Create(GameSystem *gsys, EventTrainerEyeWork *eye1, EventTrainerEyeWork *eye2) {
    GameEvent *event = GameEvent_Create(gsys, NULL, EventTrainerEye_Callback, sizeof(EventTrainerEyeEvent));
    EventTrainerEyeEvent *data = GameEvent_GetData(event);

    data->eyes[0] = eye1;
    data->eyes[1] = eye2;
    return event;
}

EventTrainerEyeWork *EventTrainerEye_CreateData(HeapID heapId, Field *field, const TrainerClashData *data,
                                                BOOL isPair) {
    EventTrainerEyeWork *work = GFL_HeapAllocate(heapId, sizeof(EventTrainerEyeWork), TRUE, "event_trainer_eye.c", 541);

    work->data = *data;
    work->unk20 = 0;
    work->isPair = isPair;
    work->field = field;
    work->player = Field_GetPlayer(field);
    return work;
}

static BOOL EventTrainerEyeSub_StartMove(EventTrainerEyeWork *work) {
    if (IsActorFlag16(work->data.actor) == TRUE) {
        EnableActorMovement(work->data.actor);
    }
    work->seq = TRAINER_EYE_SEQ_FORCE_TRAINER_DIR;
    return TRUE;
}

static BOOL EventTrainerEyeSub_ForceTrainerDir(EventTrainerEyeWork *work) {
    if (IsActorFlag16(work->data.actor) == TRUE) {
        return FALSE;
    }
    CheckSetActorFaceDir(work->data.actor, work->data.dir);
    DisableActorMovement(work->data.actor);
    work->seq = TRAINER_EYE_SEQ_DECIDE_JUMP_OUT;
    return TRUE;
}

// Trainers hidden in the terrain jump out; the others turn to the player
static BOOL EventTrainerEyeSub_DecideJumpOut(EventTrainerEyeWork *work) {
    u32 moveCode;

    if (!FldAct_CheckAcmdEnd(FieldPlayer_GetActor(work->player))) {
        return FALSE;
    }
    work->seq = TRAINER_EYE_SEQ_TURN_TRAINER;
    moveCode = GetActorMoveCode(work->data.actor);
    switch (moveCode) {
    case MOVE_CODE_HIDE_33:
    case MOVE_CODE_HIDE_34:
    case MOVE_CODE_HIDE_35:
    case MOVE_CODE_HIDE_36:
    case MOVE_CODE_HIDE_LEAVES:
        work->seq = TRAINER_EYE_SEQ_JUMP_OUT;
        break;
    }
    return TRUE;
}

static BOOL EventTrainerEyeSub_TurnTrainer(EventTrainerEyeWork *work) {
    if (IsAllActorAcmdFinished(work->data.actor) == TRUE) {
        FldAct_SetAcmd(work->data.actor, GetAcmdForDir(work->data.dir, ACMD_FACE));
        work->seq = TRAINER_EYE_SEQ_WAIT_TURN_TRAINER;
    }
    return FALSE;
}

static BOOL EventTrainerEyeSub_WaitTurnTrainer(EventTrainerEyeWork *work) {
    if (!FldAct_CheckAcmdEnd(work->data.actor)) {
        return FALSE;
    }
    work->seq = TRAINER_EYE_SEQ_START_TERRAIN_EFFECT;
    return TRUE;
}

// The exclamation mark over the Trainer
static BOOL EventTrainerEyeSub_StartTerrainEffect(EventTrainerEyeWork *work) {
    work->emote = FldeffEmotionBubble_SetActor(Field_GetFieldEffects(work->field), work->data.actor, 0, 0);
    work->seq = TRAINER_EYE_SEQ_WAIT_TERRAIN_EFFECT;
    return FALSE;
}

static BOOL EventTrainerEyeSub_WaitTerrainEffect(EventTrainerEyeWork *work) {
    if (FldeffEmotionBubble_IsFinished(work->emote) == TRUE) {
        FieldEffects_DeleteObject(work->emote);
        work->seq = TRAINER_EYE_SEQ_WAIT_30F;
    }
    return FALSE;
}

static BOOL EventTrainerEyeSub_JumpOut(EventTrainerEyeWork *work) {
    FldAct_SetAcmd(work->data.actor, 0x65);
    work->seq = TRAINER_EYE_SEQ_WAIT_JUMP_OUT;
    return FALSE;
}

static BOOL EventTrainerEyeSub_WaitJumpOut(EventTrainerEyeWork *work) {
    if (FldAct_CheckAcmdEnd(work->data.actor) == TRUE) {
        work->seq = TRAINER_EYE_SEQ_WAIT_30F;
    }
    return FALSE;
}

static BOOL EventTrainerEyeSub_Wait30F(EventTrainerEyeWork *work) {
    if (++work->timer >= 30) {
        work->timer = 0;
        work->seq = TRAINER_EYE_SEQ_DECIDE_WALK_OR_STOP;
    }
    return FALSE;
}

static BOOL EventTrainerEyeSub_DecideWalkOrStop(EventTrainerEyeWork *work) {
    if (work->data.range <= 1) {
        work->seq = TRAINER_EYE_SEQ_WAIT_8F;
        return TRUE;
    }
    work->seq = TRAINER_EYE_SEQ_WALK_ONE_STEP_TO_PLAYER;
    return TRUE;
}

static BOOL EventTrainerEyeSub_WalkOneStepToPlayer(EventTrainerEyeWork *work) {
    if (IsAllActorAcmdFinished(work->data.actor) == TRUE) {
        FldAct_SetAcmd(work->data.actor, GetAcmdForDir(work->data.dir, ACMD_WALK_8F));
        work->seq = TRAINER_EYE_SEQ_DECREMENT_CLASH_DIST;
    }
    return FALSE;
}

static BOOL EventTrainerEyeSub_DecrementClashDist(EventTrainerEyeWork *work) {
    if (!FldAct_CheckAcmdEnd(work->data.actor)) {
        return FALSE;
    }
    work->data.range--;
    work->seq = TRAINER_EYE_SEQ_DECIDE_WALK_OR_STOP;
    return TRUE;
}

static BOOL EventTrainerEyeSub_Wait8F(EventTrainerEyeWork *work) {
    if (++work->timer < 8) {
        return FALSE;
    }
    work->timer = 0;
    work->seq = TRAINER_EYE_SEQ_TURN_PLAYER;
    return TRUE;
}

static BOOL EventTrainerEyeSub_TurnPlayer(EventTrainerEyeWork *work) {
    FieldActor *player = FieldPlayer_GetActor(work->player);
    s16 playerX = GetGPosX(player);
    s16 playerZ = GetGPosZ(player);
    u16 dir = GetDirFromPosToPos(playerX, playerZ, GetGPosX(work->data.actor), GetGPosZ(work->data.actor));

    if (dir != GetActorFaceDir(player) && (!work->isPair || work->data.kind == TRAINER_CLASH_TWO_TRAINERS)) {
        if (IsAllActorAcmdFinished(player) == TRUE) {
            FldAct_SetAcmd(player, GetAcmdForDir(dir, ACMD_FACE));
            work->seq = TRAINER_EYE_SEQ_WAIT_TURN_PLAYER;
        }
    } else {
        work->seq = TRAINER_EYE_SEQ_SET_IDLE_MOVE_CODE;
    }
    return FALSE;
}

static BOOL EventTrainerEyeSub_WaitTurnPlayer(EventTrainerEyeWork *work) {
    FieldActor *player = FieldPlayer_GetActor(work->player);

    if (!FldAct_CheckAcmdEnd(player)) {
        return FALSE;
    }
    FldAct_EndAcmd(player);
    work->seq = TRAINER_EYE_SEQ_SET_IDLE_MOVE_CODE;
    return TRUE;
}

static BOOL EventTrainerEyeSub_SetIdleMoveCode(EventTrainerEyeWork *work) {
    FldAct_EndAcmd(work->data.actor);
    ChangeActorMoveCodeSeq(work->data.actor, MOVE_CODE_NONE);
    work->seq = TRAINER_EYE_SEQ_FINISH;
    return TRUE;
}

static BOOL EventTrainerEyeSub_Finish(EventTrainerEyeWork *work) {
    work->finished = TRUE;
    return FALSE;
}

// Run the routines until one waits; whether the Trainer is done
static BOOL EventTrainerEye_Update(EventTrainerEyeWork *work) {
    while (EVENT_TRAINER_EYE_ROUTINES[work->seq](work) == TRUE) {
    }
    if (work->finished == TRUE) {
        return TRUE;
    }
    return FALSE;
}

static GameEventReturnCode EventTrainerEye_Callback(GameEvent *event, u32 *state, void *data) {
    EventTrainerEyeEvent *eyeEvent = data;

    if (eyeEvent->eyes[0] != NULL && EventTrainerEye_Update(eyeEvent->eyes[0]) == TRUE) {
        GFL_HeapFree(eyeEvent->eyes[0]);
        eyeEvent->eyes[0] = NULL;
    }
    if (eyeEvent->eyes[1] != NULL && EventTrainerEye_Update(eyeEvent->eyes[1]) == TRUE) {
        GFL_HeapFree(eyeEvent->eyes[1]);
        eyeEvent->eyes[1] = NULL;
    }
    if (eyeEvent->eyes[0] == NULL && eyeEvent->eyes[1] == NULL) {
        return GAMEEVENT_DONE;
    }
    return GAMEEVENT_CONTINUE;
}

// How the actor looks for the player: TRAINER_SIGHT_FACING or TRAINER_SIGHT_ALL_DIRS for a Trainer
static u16 EventTrainerEye_GetSightType(FieldActor *actor) {
    return EvType_GetSightType(GetActorEvType(actor));
}

// Whether anything stands between the Trainer and the tile range tiles away in dir
static BOOL EventTrainerEye_CheckPathObstacle(FieldActor *actor, u16 dir, int range, EncountSystem *encounter) {
    GridPos pos;
    int i;
    s16 dx;
    s16 dz;

    if (range != 0) {
        i = 0;
        FldAct_GetGPos(actor, &pos);
        dx = GetDirectionVectorCompX(dir);
        dz = GetDirectionVectorCompZ(dir);
        pos.x += dx;
        pos.z += dz;
        for (; i < range - 1; i++) {
            if (ActorRouteCollCheck(actor, pos.x, pos.y, pos.z, dir) & ~ACTOR_COLL_WALK_AREA) {
                return TRUE;
            }
            if (encounter != NULL && EncountState_CheckSpecialEncountPos(encounter, &pos.x)) {
                return TRUE;
            }
            pos.x += dx;
            pos.z += dz;
        }
        if ((ActorRouteCollCheck(actor, pos.x, pos.y, pos.z, dir) & ~ACTOR_COLL_WALK_AREA) != ACTOR_COLL_ACTOR) {
            return TRUE;
        }
        if (encounter != NULL && EncountState_CheckSpecialEncountPos(encounter, &pos.x)) {
            return TRUE;
        }
    }
    return FALSE;
}

u16 GetNPCTrainerID(FieldActor *actor) {
    if (EventTrainerEye_UsesSpecialScript(actor) != TRUE) {
        return GetNPCTrainerIDFromSCRID(FldAct_GetSCRID(actor));
    }
    return GetActorUID(actor);
}

// Whether the actor uses the special Trainer script, whose Trainer ID is its UID
static u16 EventTrainerEye_UsesSpecialScript(FieldActor *actor) {
    return FldAct_GetSCRID(actor) == SCRID_SPECIAL_TRAINER;
}

static BOOL CheckTrainerAlreadyDefeated(Field *field, FieldActor *actor) {
    u32 index;
    KeyDataSave *keyData;
    GameData *gameData = GSYS_GetGameData(Field_GetGameSystem(field));
    EventWork *eventWork = GameData_GetEventWork(gameData);

    if (EventTrainerEye_UsesSpecialScript(actor) != TRUE) {
        return TrainerFlagGet(eventWork, GetNPCTrainerID(actor));
    }
    index = GetNPCTrainerID(actor) - 0xb0;
    keyData = getKeyDataBlkAddress(GameData_GetSaveControl(gameData));
    return KeyDataSave_IsTrainerDefeated(keyData, KeyDataSave_GetFloorInArea(keyData), index);
}

static void InitFieldScriptTrainerSetup(TrainerClashData *data, FieldActor *actor, int range, u16 dir) {
    data->range = range;
    data->dir = dir;
    data->scrId = FldAct_GetSCRID(actor);
    data->trainerId = GetNPCTrainerID(actor);
    data->actor = actor;
}

// The other Trainer of a double battle pair
static FieldActor *EventTrainerEye_FindPairedTrainer(FieldActor *trainer, u16 trainerId) {
    FieldActor *actor;
    u32 index = 0;
    MMSys *actorSys = GetActorMModelSystem(trainer);
    u16 eyeType;

    while (NextActor(actorSys, &actor, &index) == TRUE) {
        if (actor != trainer) {
            eyeType = EventTrainerEye_GetSightType(actor);
            if ((eyeType == TRAINER_SIGHT_FACING || eyeType == TRAINER_SIGHT_ALL_DIRS) &&
                trainerId == GetNPCTrainerID(actor)) {
                return actor;
            }
        }
    }
    return NULL;
}

static GameEvent *CreateTrainerClashEvent(Field *field, FieldActor *actor) {
    GameSystem *gsys = Field_GetGameSystem(field);

    if (EventTrainerEye_UsesSpecialScript(actor) != TRUE) {
        return EventScriptCall_Create(gsys, SCRID_TRAINER_CLASH, actor, 1);
    }
    return EventScriptCall_Create(gsys, SCRID_SPECIAL_TRAINER_CLASH, actor, 1);
}

// Escape from Unova: the scavs' pursuit. A raid's Trainers wander, and their sight range (user parameter 0) is
// EFU_SCAV_SIGHT. A wandering scav notices the player with nothing in between, within EFU_SCAV_CATCH tiles whichever way
// it faces or up to EFU_SCAV_SIGHT tiles away in the quarter it faces, and gives chase. While it chases, its user
// parameter EFU_SCAV_PARAM_CHASE is 1 more than the steps the player has been out of its sight, and
// EFU_SCAV_PARAM_MOVE_CODE keeps the move code it goes back to once it loses the player

static BOOL Efu_IsOnRaid(Field *field) {
    EventWork *eventWork = GameData_GetEventWork(GSYS_GetGameData(Field_GetGameSystem(field)));

    return *EventWork_GetWkPtr(eventWork, EFU_WORK_RAID) != 0;
}

// A "!" over the scav, with its sound, so the player knows it is coming
static void EfuScav_StartChase(Field *field, FieldActor *actor) {
    SetActorUserParam(actor, GetActorMoveCode(actor), EFU_SCAV_PARAM_MOVE_CODE);
    ChangeActorMoveCodeSeq(actor, MOVE_CODE_NONE);
    FldeffEmotionBubble_StartHeld(Field_GetFieldEffects(field), actor, EMOTION_BUBBLE_EXCLAMATION, TRUE);
}

// And a "?" once it has lost the player
static void EfuScav_StopChase(Field *field, FieldActor *actor) {
    SetActorUserParam(actor, 0, EFU_SCAV_PARAM_CHASE);
    ChangeActorMoveCodeSeq(actor, GetActorUserParam(actor, EFU_SCAV_PARAM_MOVE_CODE));
    FldeffEmotionBubble_StartHeld(Field_GetFieldEffects(field), actor, EMOTION_BUBBLE_QUESTION, TRUE);
}

// The direction of the longer way from one tile to another (across on a tie), and the steps between them with diagonal
// ones allowed
static u16 EfuScav_DirTo(const GridPos *from, const GridPos *to, int *dist) {
    int dx = to->x - from->x;
    int dz = to->z - from->z;
    int adx = dx < 0 ? -dx : dx;
    int adz = dz < 0 ? -dz : dz;

    if (adx >= adz) {
        *dist = adx;
        return dx < 0 ? DIR_LEFT : DIR_RIGHT;
    }
    *dist = adz;
    return dz < 0 ? DIR_UP : DIR_DOWN;
}

// Whether the scav sees the player: no more than EFU_SCAV_SIGHT tiles away, with no wall, water, ledge or edge of the
// map on the straight line between them
static BOOL EfuScav_CanSee(FieldActor *actor, const GridPos *pos, const GridPos *playerPos) {
    int dx = playerPos->x - pos->x;
    int dz = playerPos->z - pos->z;
    int steps;
    u16 dir = EfuScav_DirTo(pos, playerPos, &steps);
    int i;

    if (steps > EFU_SCAV_SIGHT) {
        return FALSE;
    }
    for (i = 1; i < steps; i++) {
        s16 x = pos->x + (dx * i + (dx < 0 ? -steps : steps) / 2) / steps;
        s16 z = pos->z + (dz * i + (dz < 0 ? -steps : steps) / 2) / steps;

        if (ActorRouteCollCheck(actor, x, pos->y, z, dir) &
            (ACTOR_COLL_BLOCKED | ACTOR_COLL_HEIGHT | ACTOR_COLL_OUT_OF_BOUNDS)) {
            return FALSE;
        }
    }
    return TRUE;
}

// Whether the scav can take a step in the direction; other actors and its own walking area don't stop it
static BOOL EfuScav_CanStep(FieldActor *actor, const GridPos *pos, u16 dir) {
    return (ActorRouteCollCheck(actor, pos->x + GetDirectionVectorCompX(dir), pos->y,
                                pos->z + GetDirectionVectorCompZ(dir), dir) &
            ~ACTOR_COLL_WALK_AREA) == 0;
}

// The scavs come out one at a time (EFU_SCAV_SPAWN_SECONDS): the hidden one furthest from the player, with its defeat
// on an earlier exploration forgotten
static void EfuScav_Spawn(Field *field, const GridPos *playerPos) {
    GameData *gameData = GSYS_GetGameData(Field_GetGameSystem(field));
    EventWork *eventWork = GameData_GetEventWork(gameData);
    PlayTime *time = GameData_GetPlayTime(gameData);
    u16 now = (PlayTime_GetHours(time) * 60 + PlayTime_GetMinutes(time)) * 60 + PlayTime_GetSeconds(time);
    u16 *start = EventWork_GetWkPtr(eventWork, EFU_WORK_EXPLORE_START);
    u16 *out = EventWork_GetWkPtr(eventWork, EFU_WORK_SCAVS_OUT);
    EventData *eventData;
    ZoneNPC *npc;
    ZoneNPC *furthest;
    u32 count;
    int furthestDist;

    if (*start == 0) {
        *start = now + 1;
    }
    if ((u16)(now + 1 - *start) < (*out + 1) * EFU_SCAV_SPAWN_SECONDS) {
        return;
    }
    eventData = GameData_GetEventData(gameData);
    furthest = NULL;
    furthestDist = -1;
    for (npc = GetZoneNPCs(eventData), count = GetZoneNPCsCount(eventData); count != 0; npc++, count--) {
        GridPos pos;
        int dist;

        pos.x = npc->pos.grid.x;
        pos.z = npc->pos.grid.z;
        EfuScav_DirTo(playerPos, &pos, &dist);
        if (npc->spawnFlag >= EFU_FLAG_SCAV_FIRST && npc->spawnFlag < EFU_FLAG_SCAV_FIRST + EFU_SCAV_MAX &&
            EventWork_FlagGet(eventWork, npc->spawnFlag) && dist > furthestDist) {
            furthest = npc;
            furthestDist = dist;
        }
    }
    if (furthest != NULL) {
        (*out)++;
        EventWork_FlagReset(eventWork, furthest->spawnFlag);
        clearTrainerBattleFlag(eventWork, GetNPCTrainerIDFromSCRID(furthest->scrId));
        SpawnZoneNPCByUID(Field_GetActorSystem(field), GetZoneNPCs(eventData),
                          PlayerState_GetZoneID(GameData_GetPlayerState(gameData)), GetZoneNPCsCount(eventData),
                          eventWork, furthest->uid);
    }
}

// Each step the player takes: a wandering scav may notice the player, every scav on the chase takes one step the most
// direct way it can toward the tile the player stepped onto, and one within EFU_SCAV_CATCH tiles starts its battle. One
// that hasn't seen the player for EFU_SCAV_LOSE_STEPS steps in a row gives up and goes back to wandering
GameEvent *EventTrainerEye_EfuPursue(Field *field) {
    FieldActor *player;
    MMSys *actorSys;
    FieldActor *actor;
    u32 index;
    GridPos pos;
    GridPos playerPos;

    if (!Efu_IsOnRaid(field)) {
        return NULL;
    }
    player = FieldPlayer_GetActor(Field_GetPlayer(field));
    actorSys = Field_GetActorSystem(field);
    FldAct_GetGPos(player, &playerPos);
    EfuScav_Spawn(field, &playerPos);
    actor = NULL;
    index = 0;
    while (NextActor(actorSys, &actor, &index) == TRUE) {
        u16 sight;
        u16 chase;
        u16 dir;
        int dist;

        sight = EventTrainerEye_GetSightType(actor);
        if (actor == player || (sight != TRAINER_SIGHT_FACING && sight != TRAINER_SIGHT_ALL_DIRS) ||
            CheckTrainerAlreadyDefeated(field, actor)) {
            continue;
        }
        FldAct_GetGPos(actor, &pos);
        chase = GetActorUserParam(actor, EFU_SCAV_PARAM_CHASE);
        dir = EfuScav_DirTo(&pos, &playerPos, &dist);
        if (EfuScav_CanSee(actor, &pos, &playerPos)) {
            if (chase == 0) {
                if (dist > EFU_SCAV_CATCH && dir != GetActorFaceDir(actor)) {
                    continue;
                }
                EfuScav_StartChase(field, actor);
            }
            chase = 1;
        } else if (chase == 0) {
            continue;
        } else if (++chase > EFU_SCAV_LOSE_STEPS) {
            EfuScav_StopChase(field, actor);
            continue;
        }
        SetActorUserParam(actor, chase, EFU_SCAV_PARAM_CHASE);
        if (dist > EFU_SCAV_CATCH && IsAllActorAcmdFinished(actor) == TRUE) {
            // The longer way first, then the other way if that's blocked, or if the player is straight ahead, a step to
            // either side to get around what's in the way
            GridPos side = playerPos;
            BOOL across = dir == DIR_LEFT || dir == DIR_RIGHT;

            if (across) {
                side.x = pos.x;
            } else {
                side.z = pos.z;
            }
            if (!EfuScav_CanStep(actor, &pos, dir)) {
                dir = EfuScav_DirTo(&pos, &side, &dist);
                if (dist == 0) {
                    dir = across ? DIR_UP : DIR_LEFT;
                    if (!EfuScav_CanStep(actor, &pos, dir)) {
                        dir = GetInverseDirection(dir);
                    }
                }
                if (!EfuScav_CanStep(actor, &pos, dir)) {
                    dir = DIR_NONE;
                }
            }
            if (dir != DIR_NONE) {
                FldAct_SetAcmd(actor, GetAcmdForDir(dir, ACMD_WALK_8F));
                pos.x += GetDirectionVectorCompX(dir);
                pos.z += GetDirectionVectorCompZ(dir);
            }
            dir = EfuScav_DirTo(&pos, &playerPos, &dist);
        }
        if (dist <= EFU_SCAV_CATCH) {
            TrainerClashData data;
            GameEvent *event;

            SetActorUserParam(actor, 0, EFU_SCAV_PARAM_CHASE);
            InitFieldScriptTrainerSetup(&data, actor, 1, dir);
            event = CreateTrainerClashEvent(field, actor);
            data.kind = TRAINER_CLASH_SINGLE;
            SetupTrainerClashSlot(event, 0, &data);
            return event;
        }
    }
    return NULL;
}
