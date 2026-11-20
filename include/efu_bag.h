#ifndef POKEBW2_EFU_BAG_H
#define POKEBW2_EFU_BAG_H

#include "types.h"
#include "constants/bag.h"
#include "constants/items.h"
#include "efu.h"
#include "save/bag.h"
#include "save/event_work.h"
#include "save/save_control.h"

// Escape from Unova's small bag: of the items a Pokémon can hold (those of the Items, Medicine and Berries pockets, Poké
// Balls among them), the bag carries one at most, or EFU_BAG_UPGRADED_MAX once the tinkerer has upgraded it
// (EFU_FLAG_BAG_UPGRADED), counting each one of a stack. Key Items and TMs and HMs don't count. Main's bag code can't
// change (its size is in the secure area), so each place that puts an item in the bag asks Efu_BagHasRoom first: the
// script commands (scrcmd_item.c), taking a held item in the party (plist_sys.c) and in the PC (box2_seq.c), and
// buying (scrcmd_shop.c). Giving an item to a Pokémon that holds one swaps them, which leaves the count as it was
#define EFU_BAG_HOLDABLE_MAX 1
#define EFU_BAG_UPGRADED_MAX 3

// How many holdable items the bag carries now. The flag is read from the save's event work, which the game data's
// is, since the bag's users don't all have the game data
static inline u32 Efu_BagHoldableMax(void) {
    if (EventWork_FlagGet(getConstDataBlock(SaveControl_GetInstance()), EFU_FLAG_BAG_UPGRADED)) {
        return EFU_BAG_UPGRADED_MAX;
    }
    return EFU_BAG_HOLDABLE_MAX;
}

// How many holdable items the bag holds, each one of a stack
static inline u32 Efu_BagHoldableCount(BagSave *bag) {
    u32 count = 0;
    u32 pocket;
    u16 i;
    BagItem *slot;

    for (pocket = BAG_POCKET_ITEMS; pocket <= BAG_POCKET_BERRIES; pocket++) {
        if (pocket != BAG_POCKET_TMS_HMS) {
            for (i = 0; (slot = BagSave_GetItemIndexHandle(bag, pocket, i)) != NULL; i++) {
                if (slot->item != ITEM_NONE) {
                    count += slot->count;
                }
            }
        }
    }
    return count;
}

// How many more of an item fit in the bag: what is left of its holdable items for one that counts, any number for
// one that doesn't
static inline u32 Efu_BagRoom(BagSave *bag, u16 item) {
    u32 pocket = BagSave_GetActualItemPocket(bag, item);
    u32 count;
    u32 max;

    if (pocket != BAG_POCKET_ITEMS && pocket != BAG_POCKET_MEDICINE && pocket != BAG_POCKET_BERRIES) {
        return 999;
    }
    count = Efu_BagHoldableCount(bag);
    max = Efu_BagHoldableMax();
    return count < max ? max - count : 0;
}

// Whether count of an item fits in the bag
static inline BOOL Efu_BagHasRoom(BagSave *bag, u16 item, u16 count) {
    return count <= Efu_BagRoom(bag, item);
}

// The bag shows the Items, Medicine and Berries pockets that hold an item, the first of them named Items (this one), or
// the Items pocket when none holds one
static inline u32 Efu_BagItemPocket(BagSave *bag) {
    if (BagSave_GetPocketItemCountCore(bag, BAG_POCKET_ITEMS, TRUE) > 0) {
        return BAG_POCKET_ITEMS;
    }
    if (BagSave_GetPocketItemCountCore(bag, BAG_POCKET_MEDICINE, TRUE) > 0) {
        return BAG_POCKET_MEDICINE;
    }
    if (BagSave_GetPocketItemCountCore(bag, BAG_POCKET_BERRIES, TRUE) > 0) {
        return BAG_POCKET_BERRIES;
    }
    return BAG_POCKET_ITEMS;
}

// The bag's first holdable item, or ITEM_NONE
static inline u16 Efu_BagHoldableItem(BagSave *bag) {
    u32 pocket;
    BagItem *slot;

    for (pocket = BAG_POCKET_ITEMS; pocket <= BAG_POCKET_BERRIES; pocket++) {
        if (pocket != BAG_POCKET_TMS_HMS) {
            slot = BagSave_GetItemIndexHandle(bag, pocket, 0);
            if (slot != NULL && slot->item != ITEM_NONE && slot->count != 0) {
                return slot->item;
            }
        }
    }
    return ITEM_NONE;
}

// The pocket whose name and tab the bag shows for one of its pockets, with itemPocket the one it names Items
static inline u32 Efu_BagShownPocket(u32 pocket, u32 itemPocket) {
    return pocket == itemPocket ? BAG_POCKET_ITEMS : pocket;
}

#endif // POKEBW2_EFU_BAG_H
