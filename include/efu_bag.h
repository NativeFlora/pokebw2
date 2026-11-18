#ifndef POKEBW2_EFU_BAG_H
#define POKEBW2_EFU_BAG_H

#include "types.h"
#include "constants/bag.h"
#include "save/bag.h"

// Escape from Unova's one-item bag: of the items a Pokémon can hold (those of the Items, Medicine and Berries pockets,
// Poké Balls among them), the bag carries this many at most, counting each one of a stack. Key Items and TMs and HMs
// don't count. Main's bag code can't change (its size is in the secure area), so each place that puts an item in the
// bag asks Efu_BagHasRoom first: the script commands (scrcmd_item.c), taking a held item in the party (plist_sys.c) and
// in the PC (box2_seq.c). Giving an item to a Pokémon that holds one swaps them, which leaves the count as it was
// The limit, which Efu_BagHasRoom assumes is 1
#define EFU_BAG_HOLDABLE_MAX 1

// Whether count of an item fit in the one-item bag: one that counts fits only alone, and only in a bag without one
// (BagSave_GetPocketItemCountCore counts a pocket's slots, those in the Free Space too)
static inline BOOL Efu_BagHasRoom(BagSave *bag, u16 item, u16 count) {
    u32 pocket = BagSave_GetActualItemPocket(bag, item);

    if (pocket != BAG_POCKET_ITEMS && pocket != BAG_POCKET_MEDICINE && pocket != BAG_POCKET_BERRIES) {
        return TRUE;
    }
    return count <= EFU_BAG_HOLDABLE_MAX && BagSave_GetPocketItemCountCore(bag, BAG_POCKET_ITEMS, TRUE) +
                                                    BagSave_GetPocketItemCountCore(bag, BAG_POCKET_MEDICINE, TRUE) +
                                                    BagSave_GetPocketItemCountCore(bag, BAG_POCKET_BERRIES, TRUE) ==
                                                0;
}

#endif // POKEBW2_EFU_BAG_H
