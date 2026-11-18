"""Escape from Unova: writes res/field/scripts/efu.s and res/text/script/efu.txt from the templates in this directory,
adding the starter menus (a type list, then a list per type) from starters.py's pool."""
import json, collections, os, subprocess
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
# Loot: each tier's table (items with their weights), and how often a spot of the tier comes up empty, in percent
# The first zone is free to travel to, so its loot is cheap: mostly Tiny Mushrooms and Poke Balls on the route, with
# Pearls, Stardust and the odd Nugget in the caves and the target. The bag carries one item a Pokemon can hold
# (include/efu_bag.h), so every roll gives one
LOOT = {
    'Route': (40, {'TINY_MUSHROOM': 6, 'POKE_BALL': 6, 'ORAN_BERRY': 3, 'POTION': 3, 'CHERI_BERRY': 1,
                   'PECHA_BERRY': 1, 'RAWST_BERRY': 1, 'ANTIDOTE': 1}),
    'Cave': (25, {'TINY_MUSHROOM': 4, 'POKE_BALL': 4, 'PEARL': 3, 'STARDUST': 2, 'POTION': 2, 'ORAN_BERRY': 2,
                  'GREAT_BALL': 1, 'NUGGET': 1}),
    'Target': (15, {'PEARL': 3, 'STARDUST': 3, 'POKE_BALL': 3, 'TINY_MUSHROOM': 2, 'SUPER_POTION': 2, 'GREAT_BALL': 2,
                    'NUGGET': 2}),
}
items = [l.split('=')[0].strip() for l in open(root + '/generated/items.txt') if l.startswith('ITEM_')]
loot = []
for tier, (empty, table) in LOOT.items():
    # Random picks a slot of the table laid out by weight, and a binary search of comparisons finds its item
    slots = [items.index('ITEM_' + i) for i, w in table.items() for _ in range(w)]
    loot.append(f'L_LootPick{tier}:\n    Random 0x8020, {len(slots)}\n')
    def pick(lo, hi, label):
        if hi - lo == 1 or len(set(slots[lo:hi])) == 1:
            loot.append(f'{label}:\n    WorkSetConst 0x800c, {slots[lo]}\n    VMReturn\n')
            return
        mid = (lo + hi) // 2
        loot.append(f'{label}:\n    WorkCmpConst 0x8020, {mid}\n    VMJumpIf CMP_GE, {label}_H\n')
        pick(lo, mid, label + '_L')
        pick(mid, hi, label + '_H')
    pick(0, len(slots), f'L_LootPick{tier}_')
# Heading out: each spot's ball is out (its hide flag cleared) unless its tier's empty chance comes up
spots = json.load(open(os.path.join(here, 'loot.json')))
loot.append('L_LootRoll:\n')
for i, spot in enumerate(spots):
    flag = int(spot['flag'].split('0x')[1], 16)
    empty = LOOT[spot['tier'].capitalize()][0]
    loot.append(f'    Random 0x8020, 100\n    WorkCmpConst 0x8020, {empty}\n    VMJumpIf CMP_GE, L_LootOut_{i}\n'
                f'    FlagSet {flag:#x}\n    VMJump L_LootNext_{i}\nL_LootOut_{i}:\n    FlagReset {flag:#x}\n'
                f'L_LootNext_{i}:\n')
loot.append('    VMReturn\n')
tmpl = open(os.path.join(here, 'efu.s.in')).read()
tmpl = tmpl.replace('@LOST_SOUL@\n', ''.join(ls))
tmpl = tmpl.replace('@LOOT@\n', ''.join(loot))
tmpl = tmpl.replace('@POKE_BALL@', str(items.index('ITEM_POKE_BALL')))
open(root + '/res/field/scripts/efu.s', 'w').write(tmpl.replace('@STARTER_MENUS@\n', ''.join(s)))
hand = open(os.path.join(here, 'efu.txt.in'), encoding='utf-8').read()
open(root + '/res/text/script/efu.txt', 'w', encoding='utf-8').write(hand + '\n'.join(text) + '\n')
