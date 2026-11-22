"""Escape from Unova: writes res/field/scripts/efu.s and res/text/script/efu.txt from the templates in this directory,
adding the starter menus (a type list, then a list per type) from starters.py's pool."""
import json, collections, os, re, subprocess
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
subprocess.run(['python3', os.path.join(here, 'starters.py')], check=True, stderr=subprocess.DEVNULL)
names = [l.split('=')[0].strip() for l in open(root + '/generated/species.txt') if l.startswith('SPECIES_')]
num = {c: i for i, c in enumerate(names)}
st = json.load(open(os.path.join(here, 'starters.json')))
TYPEORDER = ['TYPE_NORMAL', 'TYPE_FIRE', 'TYPE_WATER', 'TYPE_GRASS', 'TYPE_ELECTRIC', 'TYPE_ICE', 'TYPE_FIGHTING',
             'TYPE_POISON', 'TYPE_GROUND', 'TYPE_FLYING', 'TYPE_PSYCHIC', 'TYPE_BUG', 'TYPE_ROCK', 'TYPE_GHOST',
             'TYPE_DRAGON', 'TYPE_DARK', 'TYPE_STEEL']
by = collections.defaultdict(list)
for c, n, t in st:
    by[t[0]].append((c, n))
pages = []
for t in TYPEORDER:
    l = by.get(t, [])
    if not l:
        continue
    label = t[5:].capitalize()
    if len(l) > 31:  # a list menu holds 32 options, one of them Back
        h = (len(l) + 1) // 2
        pages += [(label + ' I', l[:h]), (label + ' II', l[h:])]
    else:
        pages.append((label, l))
text = []
s = ['L_ChooseStarter:\n    SystemMsg Efu_Text_WhichType, 2\n    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020\n']
for i, (label, l) in enumerate(pages):
    k = 'Efu_Text_Type_' + label.replace(' ', '_')
    text.append(f'{k} = {label}')
    s.append(f'    ListMenuAdd {k}, 65535, {i}\n')
s.append('    ListMenuShow\n')
for i in range(len(pages)):
    s.append(f'    WorkCmpConst 0x8020, {i}\n    VMJumpIf CMP_EQ, L_Page_{i}\n')
s.append('    VMJump L_ChooseStarter\n')
seen = set()
for i, (label, l) in enumerate(pages):
    s.append(f'\nL_Page_{i}:\n    SystemMsg Efu_Text_WhichOne, 2\n    ListMenuAnchorTopLeft 1, 1, 0, 0, 0x8020\n')
    for c, n in l:
        k = 'Efu_Text_Sp_' + c[8:].title().replace('_', '')
        if k not in seen:
            seen.add(k)
            text.append(f'{k} = {n}')
        s.append(f'    ListMenuAdd {k}, 65535, {num[c]}\n')
    s.append('    ListMenuAdd Efu_Text_Back, 65535, 0\n    ListMenuShow\n    VMJump L_ConfirmStarter\n')
# The lost soul: Random picks an index of the whole pool, and a binary search of comparisons turns it into a species
pool = [num[c] for c, n, t in st]
ls = [f'L_LostSoul:\n    Random 0x8020, {len(pool)}\n']
def tree(lo, hi, label):
    if hi - lo == 1:
        ls.append(f'{label}:\n    WorkSetConst 0x8025, {pool[lo]}\n    VMJump L_LostSoulFound\n')
        return
    mid = (lo + hi) // 2
    ls.append(f'{label}:\n    WorkCmpConst 0x8020, {mid}\n    VMJumpIf CMP_GE, {label}_H\n')
    tree(lo, mid, label + '_L')
    tree(mid, hi, label + '_H')
tree(0, len(pool), 'L_LostSoulPick')
# Loot comes in tiers, each a table of items with their weights, from everyday finds to the valuable ones; every item
# can be held, since the bag carries only items a Pokemon can hold (include/efu_bag.h), and every roll gives one
LOOT_TIERS = {
    'Common': {'TINY_MUSHROOM': 6, 'POKE_BALL': 6, 'ORAN_BERRY': 4, 'POTION': 4, 'ANTIDOTE': 2, 'PARLYZ_HEAL': 2,
               'REPEL': 2, 'AWAKENING': 1, 'BURN_HEAL': 1, 'ICE_HEAL': 1, 'CHERI_BERRY': 1, 'PECHA_BERRY': 1,
               'RAWST_BERRY': 1, 'ASPEAR_BERRY': 1, 'CHESTO_BERRY': 1},
    'Uncommon': {'GREAT_BALL': 4, 'SUPER_POTION': 4, 'PEARL': 4, 'STARDUST': 4, 'FULL_HEAL': 2, 'SITRUS_BERRY': 2,
                 'BIG_MUSHROOM': 2, 'SUPER_REPEL': 2, 'ETHER': 2, 'FRESH_WATER': 2},
    'Rare': {'ULTRA_BALL': 3, 'HYPER_POTION': 3, 'REVIVE': 3, 'NUGGET': 3, 'BIG_PEARL': 2, 'LUM_BERRY': 2, 'ELIXIR': 2,
             'RARE_CANDY': 1, 'HEART_SCALE': 1},
    'Valuable': {'STAR_PIECE': 3, 'MAX_REVIVE': 2, 'FULL_RESTORE': 2, 'PP_UP': 2, 'BIG_NUGGET': 1, 'COMET_SHARD': 1,
                 'LEFTOVERS': 1, 'QUICK_CLAW': 1, 'KINGS_ROCK': 1},
    # The Rare Candy in Route 3's childcare centre, its own item ball
    'Candy': {'RARE_CANDY': 1},
}
# Each kind of place: how often its spots come up empty on an exploration, in percent, and the chances of its tiers.
# The first zone is free to travel to, so its route is mostly common finds; its caves and target, and the scavs' drops,
# reach the better tiers
LOOT_PLACES = {
    'Route': (40, {'Common': 85, 'Uncommon': 15}),
    'Cave': (25, {'Common': 50, 'Uncommon': 40, 'Rare': 10}),
    'Target': (15, {'Common': 15, 'Uncommon': 50, 'Rare': 32, 'Valuable': 3}),
    'Scav': (0, {'Uncommon': 45, 'Rare': 45, 'Valuable': 10}),
    'Candy': (90, {'Candy': 100}),
}
items = [l.split('=')[0].strip() for l in open(root + '/generated/items.txt') if l.startswith('ITEM_')]
loot = []
for tier, table in LOOT_TIERS.items():
    # Random picks a slot of the table laid out by weight, and a binary search of comparisons finds its item
    slots = [items.index('ITEM_' + i) for i, w in table.items() for _ in range(w)]
    loot.append(f'L_LootTier{tier}:\n    Random 0x8020, {len(slots)}\n')
    def pick(lo, hi, label):
        if hi - lo == 1 or len(set(slots[lo:hi])) == 1:
            loot.append(f'{label}:\n    WorkSetConst 0x800c, {slots[lo]}\n    VMReturn\n')
            return
        mid = (lo + hi) // 2
        loot.append(f'{label}:\n    WorkCmpConst 0x8020, {mid}\n    VMJumpIf CMP_GE, {label}_H\n')
        pick(lo, mid, label + '_L')
        pick(mid, hi, label + '_H')
    pick(0, len(slots), f'L_LootTier{tier}_')
# A place's pick: a tier by its chances, then that tier's item (into 0x800c)
for place, (empty, tiers) in LOOT_PLACES.items():
    assert sum(tiers.values()) == 100
    loot.append(f'L_LootPick{place}:\n    Random 0x8020, 100\n')
    total = 0
    for tier, chance in list(tiers.items())[:-1]:
        total += chance
        loot.append(f'    WorkCmpConst 0x8020, {total}\n    VMJumpIf CMP_LT, L_LootTier{tier}\n')
    loot.append(f'    VMJump L_LootTier{list(tiers)[-1]}\n')
# Heading out: each spot's ball is out (its hide flag cleared) unless its place's empty chance comes up
spots = json.load(open(os.path.join(here, 'loot.json')))
loot.append('L_LootRoll:\n')
for i, spot in enumerate(spots):
    flag = int(spot['flag'].split('0x')[1], 16)
    empty = LOOT_PLACES[spot['place'].capitalize()][0]
    loot.append(f'    Random 0x8020, 100\n    WorkCmpConst 0x8020, {empty}\n    VMJumpIf CMP_GE, L_LootOut_{i}\n'
                f'    FlagSet {flag:#x}\n    VMJump L_LootNext_{i}\nL_LootOut_{i}:\n    FlagReset {flag:#x}\n'
                f'L_LootNext_{i}:\n')
loot.append('    VMReturn\n')
# The locker: LOCKER_SLOTS slots, each in an event work value of its own (docs/efu.md), holding an item and its count
# as item | count << 10 (BW2's items are under 1024), 0 when empty. The used slots come first, so the list menu's rows
# are the slots. L_LockerList adds a row per used slot (its value the slot) and counts them in 0x8029; L_LockerGet and
# L_LockerSet read and write slot 0x8027 through 0x8026; L_LockerPut puts one of item 0x8030 in its slot, or the first
# free one, and says in 0x8031 whether it did; L_LockerCompact closes the gap a slot that emptied leaves
LOCKER_WORKS = [0x41a7, 0x41a6, 0x41a5, 0x41a4, 0x41a3, 0x41a2, 0x41a1, 0x41a0, 0x419e, 0x419d, 0x419c, 0x419b, 0x419a,
                0x4199, 0x4198, 0x4197, 0x4193, 0x418b, 0x4180, 0x4177]
LOCKER_STACK = 63
lk = ['L_LockerList:\n    WorkSetConst 0x8029, 0\n']
for i, w in enumerate(LOCKER_WORKS):
    lk.append(f'    WorkCmpConst {w:#x}, 0\n    VMJumpIf CMP_EQ, L_LockerListDone\n'
              f'    WorkGet 0x8022, {w:#x}\n    WorkAnd 0x8022, 1023\n    WorkGet 0x8021, {w:#x}\n    WorkDiv 0x8021, 1024\n'
              f'    WordSetItemNameEx 0, 0x8022, 1, 0\n    WordSetNumber 1, 0x8021, 2\n'
              f'    ListMenuAdd Efu_Text_LockerSlot, 65535, {i}\n    WorkAdd 0x8029, 1\n')
lk.append('L_LockerListDone:\n    VMReturn\n')
for name, op in (('Get', 'WorkGet 0x8026, {w:#x}'), ('Set', 'WorkSet {w:#x}, 0x8026')):
    lk.append(f'L_Locker{name}:\n')
    for i, w in enumerate(LOCKER_WORKS):
        lk.append(f'    WorkCmpConst 0x8027, {i}\n    VMJumpIf CMP_EQ, L_Locker{name}_{i}\n')
    lk.append('    VMReturn\n')
    for i, w in enumerate(LOCKER_WORKS):
        lk.append(f'L_Locker{name}_{i}:\n    {op.format(w=w)}\n    VMReturn\n')
lk.append('L_LockerPut:\n    WorkSetConst 0x8031, 1\n')
for i, w in enumerate(LOCKER_WORKS):
    lk.append(f'    WorkGet 0x8032, {w:#x}\n    WorkAnd 0x8032, 1023\n    WorkCmpWork 0x8032, 0x8030\n'
              f'    VMJumpIf CMP_NE, L_LockerPutNext_{i}\n    WorkCmpConst {w:#x}, {LOCKER_STACK << 10}\n'
              f'    VMJumpIf CMP_GE, L_LockerPutNext_{i}\n    WorkAdd {w:#x}, 1024\n    VMReturn\nL_LockerPutNext_{i}:\n')
for i, w in enumerate(LOCKER_WORKS):
    lk.append(f'    WorkCmpConst {w:#x}, 0\n    VMJumpIf CMP_NE, L_LockerPutFree_{i}\n'
              f'    WorkSet {w:#x}, 0x8030\n    WorkAdd {w:#x}, 1024\n    VMReturn\nL_LockerPutFree_{i}:\n')
lk.append('    WorkSetConst 0x8031, 0\n    VMReturn\nL_LockerCompact:\n')
for i, (w, nxt) in enumerate(zip(LOCKER_WORKS, LOCKER_WORKS[1:])):
    lk.append(f'    WorkCmpConst {w:#x}, 0\n    VMJumpIf CMP_NE, L_LockerCompact_{i}\n'
              f'    WorkSet {w:#x}, {nxt:#x}\n    WorkSetConst {nxt:#x}, 0\nL_LockerCompact_{i}:\n')
lk.append('    VMReturn\n')
tmpl = open(os.path.join(here, 'efu.s.in')).read()
tmpl = tmpl.replace('@LOCKER@\n', ''.join(lk))
tmpl = tmpl.replace('@LOCKER_SLOTS@', str(len(LOCKER_WORKS)))
tmpl = tmpl.replace('@LOST_SOUL@\n', ''.join(ls))
tmpl = tmpl.replace('@LOOT@\n', ''.join(loot))
# The target's scavs fight again on each entry they are out (build_raid.py's TARGET_SCAVS)
target_scavs = re.search(r'^TARGET_SCAVS = \[([0-9, ]+)\]', open(os.path.join(here, 'build_raid.py')).read(), re.M)
tmpl = tmpl.replace('@TARGET_SCAV_RESET@\n', ''.join(f'    TrainerFlagReset {t.strip()}\n'
                                                      for t in target_scavs.group(1).split(',')))
garden = re.search(r'^GARDEN_SCAV = \{.*?\'trainer\': (\d+)', open(os.path.join(here, 'build_raid.py')).read(), re.M | re.S)
tmpl = tmpl.replace('@GARDEN_SCAV@', garden.group(1))
forest = re.search(r'^FOREST_SCAV = \{.*?\'trainer\': (\d+)', open(os.path.join(here, 'build_raid.py')).read(), re.M | re.S)
tmpl = tmpl.replace('@FOREST_SCAV@', forest.group(1))
rumination = re.search(r'^RUMINATION_SCAV = \{.*?\'trainer\': (\d+)', open(os.path.join(here, 'build_raid.py')).read(), re.M | re.S)
tmpl = tmpl.replace('@RUMINATION_SCAV@', rumination.group(1))
# Floccesy Ranch's scavengers fight again on each entry they are out (build_raid.py writes their Trainers)
ranch = open(os.path.join(here, 'ranch_scavs.txt')).read().split()
tmpl = tmpl.replace('@RANCH_SCAV_RESET@\n', ''.join(f'    TrainerFlagReset {t}\n' for t in sorted(set(ranch))))
childcare = re.search(r'^CHILDCARE_GENERIC_TRAINER = (\d+)', open(os.path.join(here, 'build_raid.py')).read(), re.M)
tmpl = tmpl.replace('@CHILDCARE_GENERIC@', childcare.group(1))
tmpl = tmpl.replace('@VOLCARONA@', str(num['SPECIES_VOLCARONA']))
tmpl = tmpl.replace('@POKE_BALL@', str(items.index('ITEM_POKE_BALL')))
# The world editor's locked doors (apply_world_edits.py writes world_locks.json): a sign script for each of the
# EFU_LOCK_COUNT locks, in EFU_SCRIPT_LOCK_FIRST's order, and the flags of those that lock again on each raid
efu_h = open(root + '/include/efu.h').read()
LOCK_COUNT = int(re.search(r'#define EFU_LOCK_COUNT (\d+)', efu_h).group(1))
assert re.search(r'#define EFU_SCRIPT_LOCK_FIRST \(EFU_SCRIPT_FIRST \+ 35\)', efu_h), 'the lock scripts follow Script_Tinkerer'
locks_path = os.path.join(here, 'world_locks.json')
locks = json.load(open(locks_path))['locks'] if os.path.exists(locks_path) else []
assert len(locks) <= LOCK_COUNT, 'more locks than EFU_LOCK_COUNT'
entries, lock_scripts, resets = [], ['Script_LockNone:\n    VMHalt\n'], []
for n in range(1, LOCK_COUNT + 1):
    lock = locks[n - 1] if n <= len(locks) else None
    if not lock or lock.get('unused'):
        entries.append('    ScriptEntry Script_LockNone\n')
        continue
    entries.append(f'    ScriptEntry Script_Lock_{n}\n')
    flag = f'EFU_FLAG_LOCK_FIRST + {n - 1}'
    if lock.get('relock'):
        resets.append(f'    FlagReset {flag}\n')
    body = [f'Script_Lock_{n}:\n    FlagGet {flag}, 0x8020\n    WorkCmpConst 0x8020, 0\n'
            f'    VMJumpIf CMP_NE, L_Lock_{n}_End\n    ActorsPauseAll\n']
    if lock.get('item'):
        item = items.index(lock['item'])
        body.append(f'    WordSetItemNameEx 0, {item}, 1, 0\n    ItemCheckAmount {item}, 1, 0x8021\n'
                    f'    WorkCmpConst 0x8021, 0\n    VMJumpIf CMP_EQ, L_Lock_{n}_Shut\n    FlagSet {flag}\n')
        if lock.get('consume'):
            body.append(f'    ItemSub {item}, 1, 0x8021\n    SystemMsg Efu_Text_LockUsed, 2\n')
        else:
            body.append('    SystemMsg Efu_Text_LockOpen, 2\n')
        body.append(f'    VMJump L_Lock_{n}_Close\nL_Lock_{n}_Shut:\n    SystemMsg Efu_Text_LockKey, 2\n')
    else:
        body.append('    SystemMsg Efu_Text_BoardedDoor, 2\n')
    body.append(f'L_Lock_{n}_Close:\n    LastKeyWait\n    SystemMsgClose\n    ActorsUnpauseAll\n'
                f'L_Lock_{n}_End:\n    VMHalt\n')
    lock_scripts.append(''.join(body))
tmpl = tmpl.replace('@LOCK_ENTRIES@\n', ''.join(entries))
tmpl = tmpl.replace('@LOCK_RESET@\n', ''.join(resets))
tmpl = tmpl.replace('@LOCKS@\n', '\n'.join(lock_scripts))
open(root + '/res/field/scripts/efu.s', 'w').write(tmpl.replace('@STARTER_MENUS@\n', ''.join(s)))
hand = open(os.path.join(here, 'efu.txt.in'), encoding='utf-8').read()
open(root + '/res/text/script/efu.txt', 'w', encoding='utf-8').write(hand + '\n'.join(text) + '\n')
