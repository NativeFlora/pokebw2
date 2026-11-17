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
tmpl = open(os.path.join(here, 'efu.s.in')).read()
open(root + '/res/field/scripts/efu.s', 'w').write(tmpl.replace('@STARTER_MENUS@\n', ''.join(s)))
hand = open(os.path.join(here, 'efu.txt.in'), encoding='utf-8').read()
open(root + '/res/text/script/efu.txt', 'w', encoding='utf-8').write(hand + '\n'.join(text) + '\n')
