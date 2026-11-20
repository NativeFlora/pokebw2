"""Escape from Unova: the first exploration zone's people, items and wild Pokémon (docs/efu.md).

Idempotent, like build_base.py: it reads the originals from git (BASE_COMMIT) and writes
- the encounters of its routes, caves and target (res/field/encounters): every wild Pokémon at a random level in the
  place's range (WILD_LEVELS, PLACE_LEVELS), each species at the stage it has reached by the lowest;
- the scavs' Trainers (res/trainers/data): single battles with two to six Pokémon at 65 to 90% of the level cap,
  evolved as far as that level takes them, with new lines;
- the events of its routes (Route 3, Route 2, Route 19, Route 20 and Floccesy Ranch, in their matrices' coordinates,
  build_zone.py): nobody but the scavs and the items; a scav at each spot where one of the route's people stood, a
  Team Plasma Grunt to look at, hidden by its own flag (EFU_FLAG_SPOT_FIRST), and the garden's; each stands looking around (MOVE_CODE_TURN_RANDOM) once it comes
  out, never stepping until it has seen the player, and its Trainer sight is EFU_SCAV_CATCH tiles; the pursuit
  (event_trainer_eye.c), which sees EFU_SCAV_SIGHT, does the rest. Their doors are rewired into the zone: the garden's
  path south into Pinwheel Forest and its road east to Route 2's south end, the forest out to Route 19, Route 2's and
  Route 20's gates home;
- the caves' and the target's events, the childcare centre's and the Day Care's: Wellspring Cave's Cut trees, the
  inner forest's bridge obstacles and its grass patch's scav, Floccesy Ranch's scavs, and Burgh in Rumination Field
  with his Challenge Mode team (leader_burgh.json);
- the PC's menu, deposit only on a raid (global_10090.s);
- include/efu_wild_swap.h, the species each wild one may be swapped for on an exploration;
- the Grunts' Trainer classes, named Scavenger.
"""
import json, os, random, re, subprocess

import build_zone as bz

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
BASE_COMMIT = 'origin/main'

WILD_LEVELS = (2, 15)
# Each place's wild Pokémon: the routes further in, the caves and the target a little tougher than Route 3's
PLACE_LEVELS = {'route_2': (4, 16), 'route_19': (10, 20), 'route_20': (10, 20), 'floccesy_ranch': (12, 22),
                'wellspring_cave': (8, 18), 'wellspring_cave_2': (8, 18),
                'pinwheel_forest_2': (12, 22)}
# The zone's level cap, its highest wild level, and the scavs' Pokémon from 65% to 90% of it, two to six of them each
LEVEL_CAP = max([WILD_LEVELS[1]] + [hi for lo, hi in PLACE_LEVELS.values()])
assert LEVEL_CAP == int(re.search(r'#define EFU_LEVEL_CAP (\d+)', open(os.path.join(root, 'include/efu.h')).read()).group(1))
SCAV_LEVELS = (round(LEVEL_CAP * 0.65), round(LEVEL_CAP * 0.9))
SCAV_TEAM = (2, 6)
efu_h = open(os.path.join(root, 'include/efu.h')).read()
# The scavs' Trainer sight, the original's battle on sight: only straight beside them (EFU_SCAV_CATCH); their pursuit
# notices the player much further off (EFU_SCAV_SIGHT, event_trainer_eye.c)
SCAV_SIGHT = int(re.search(r'#define EFU_SCAV_CATCH (\d+)', efu_h).group(1))
# How far a scav wanders from where it starts, in tiles either way
SCAV_WANDER = 3
# A Pokémon that evolves by a stone, trading or friendship has done so by this level
OTHER_EVOLUTION_LEVEL = 36
# Each scav, by its Trainer file: whether it shows as the female Team Plasma Grunt, and what it says before the battle,
# on losing it, and if spoken to after. Their own lines were about the old Route 3 (the school kids' lessons on Triple
# and Rotation Battles, a double-battle pair's cheering)
SCAVS = {
    'youngster_jimmy': (False, "This place was full of kids once.\nNow it's mine!{be01}", "Okay, okay! I'm going!",
                        "Don't come back here. There's\nnothing left worth taking."),
    'lass_shannon': (True, "Ooh, a straggler!\nWhat's in the bag?{be01}", "Ugh! Fine, keep your junk!",
                     "Everything out here belongs to\nwhoever's still standing."),
    'fisherman_bruce': (False, "I don't fish for food anymore.\nI fish for stragglers.{be01}", "The one that got away...",
                        "Nobody's left to stop me taking\nwhatever I want. Except you, I guess."),
    'fisherman_mack': (False, "You walked a long way from home.\nToo bad it ends here!{be01}",
                       "You're tougher than you look.", "Keep your head down. There are\nworse than me on this route."),
    'nursery_aide_autumn': (True, "This uniform was all I could find.\nThe Pokémon are all I have left!{be01}",
                            "No... Not again...", "Go home, if you still have one."),
    'preschooler_buster': (False, "Finders keepers!\nHand it over!{be01}", "Fine! Take it and go!",
                           "I take anything that isn't\nnailed down. Then I take the nails."),
    'preschooler_eva': (True, "Found you!\nYou can stop hiding now.{be01}", "You... You cheated!",
                        "I've been out here for ages.\nNobody ever finds me."),
    'preschooler_tyrone': (False, "Gotcha!\nEmpty your pockets!{be01}", "Whoops...",
                           "I'll get you next time.\nI always do."),
    'school_kid_edgar': (False, "Scavenging is simple math.\nYou have things. I want them.{be01}",
                         "I must have carried a one\nsomewhere...", "The numbers only add up for\nthe strong out here."),
    'school_kid_marsha': (True, "Running? I've had my eye on you\nfor a while now!{be01}", "I should have been faster...",
                          "There's nothing left out here.\nJust us, and whatever you're carrying."),
    # Route 20's
    'youngster_petey': (False, "Fresh legs! Fresh pockets!\nLet's see what you've got!{be01}", "Okay, okay! I'm going!",
                        "The forest past the old gate is\nfull of stuff. Full of trouble too."),
    'youngster_terrell': (False, "I've been watching the path.\nYou're the first in days!{be01}", "I should've kept watching.",
                          "Don't go into the caves alone.\nI went in with friends."),
    'lass_isabel': (True, "Pretty bag you've got.\nIt'd look better on me!{be01}", "Hmph! Keep it, then!",
                    "Everything nice gets taken out\nhere. Sooner or later."),
    'nursery_aide_kimya': (True, "I have mouths to feed.\nI'm sorry, I really am.{be01}", "Please... Just go.",
                           "They're waiting for me back\nthere. I'll find something else."),
    'pkmn_ranger_naoko': (True, "I used to protect this forest.\nNow it protects me!{be01}", "The forest let me down...",
                          "Rangers don't get paid anymore.\nSo I pay myself."),
    'pkmn_ranger_bret': (False, "This is my patch.\nYou're trespassing!{be01}", "You can pass. This time.",
                         "Stay off the high ground.\nThat's where we watch from."),
    'backers_may_mal': (True, "No more cheering! Only taking!\nHand over your stuff!{be01}", "Boo! Hiss!",
                        "I used to cheer on Trainers.\nNow I cheer when they drop things."),
    # The target's (TARGET_SCAVS)
    'youngster_nicholas': (False, "Every Pokémon in this grass is mine.\nAnd so is whatever you're carrying!{be01}",
                           "Take the grass, then. I'm off.", "There's nothing left in here but\nbugs and bad luck."),
    'pkmn_ranger_dwayne': (False, "Burgh's gone, so this field is mine.\nTurn around, or hand it all over!{be01}",
                           "Fine! It's yours. For now.", "Someone's always waiting to take\nwhat's left. Today it's you."),
    'veteran_sinan': (False, "I've outlasted everyone in these\nwoods. I'll outlast you too!{be01}", "Hah... Not bad.",
                      "The forest keeps what it takes.\nRemember that."),
    'pkmn_ranger_hillary': (True, "This forest is my larder now.\nAnd you're in it!{be01}", "I'll find easier prey.",
                            "The deeper you go, the more\nyou find. And the more find you."),
    'youngster_keita_2': (False, "I heard you coming a mile off.\nDrop the bag!{be01}", "Aw, man...",
                          "There's good stuff under these\ntrees. I'm not telling you where."),
    # Route 2's
    'veteran_rayne': (False, "I've seen worse than you crawl\nout of that forest.{be01}", "Heh. Not bad, kid.",
                      "The forest's way in is past the\ngarden. Go in light, come out heavy."),
    'lass_henrietta': (True, "Nobody walks this road anymore.\nExcept people with stuff!{be01}", "Hmph! Lucky shot!",
                       "The old gate south still works.\nFor a price."),
    'lass_mali': (True, "You look like you've got\nsomething to share!{be01}", "Okay, okay, I'll share mine...",
                  "I used to pick flowers here.\nNow I pick pockets."),
    'youngster_mikey': (False, "This is my road!\nPay the toll!{be01}", "Toll waived... this time.",
                        "Everybody heading home passes\nme. Everybody pays."),
    'veteran_oriana': (True, "I've fought through three winters\nout here. You won't stop me!{be01}",
                       "Maybe it's time to rest...", "Stay off the main path after\ndark. That's when we hunt."),
}
# The scavs' Trainer class, whichever it was: Team Plasma's Grunts, renamed
SCAV_CLASS = {False: 'TRAINER_CLASS_TEAM_PLASMA_GRUNT_M', True: 'TRAINER_CLASS_TEAM_PLASMA_GRUNT_F'}
SCAV_MODEL = {False: 'OBJ_CODE_TEAM_PLASMA_GRUNT_M', True: 'OBJ_CODE_TEAM_PLASMA_GRUNT_F'}
SCAV_CLASS_NAME = 'Scavenger'
FLAG_SPOT_FIRST = int(re.search(r'#define EFU_FLAG_SPOT_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
SPOT_MAX = int(re.search(r'#define EFU_SPOT_MAX (\d+)', efu_h).group(1))
FLAG_DOOR_FIRST = int(re.search(r'#define EFU_FLAG_DOOR_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
assert int(re.search(r'#define EFU_DOOR_COUNT (\d+)', efu_h).group(1)) == 3
FLAG_TARGET_SCAV_FIRST = int(re.search(r'#define EFU_FLAG_TARGET_SCAV_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
assert int(re.search(r'#define EFU_TARGET_SCAV_COUNT (\d+)', efu_h).group(1)) == 3
FLAG_LOOT_FIRST = int(re.search(r'#define EFU_FLAG_LOOT_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
# The scripts that pick up loot, by tier (gen_efu.py writes them from loot.json and its item tables)
LOOT_SCRIPTS = {t: 11000 + int(re.search(r'#define EFU_SCRIPT_LOOT_%s \(EFU_SCRIPT_FIRST \+ (\d+)\)' % t.upper(),
                                         efu_h).group(1)) for t in ('route', 'cave', 'target')}
SCRIPT_CHILDCARE = 11000 + int(re.search(r'#define EFU_SCRIPT_CHILDCARE \(EFU_SCRIPT_FIRST \+ (\d+)\)', efu_h).group(1))
FLAG_CHILDCARE_SCAV = int(re.search(r'#define EFU_FLAG_CHILDCARE_SCAV (0x[0-9a-f]+)', efu_h).group(1), 16)
# The Route 3 childcare centre's scavenger, Billy (Route 2's Youngster Jimmy's Trainer, renamed), whose team comes from
# the starters' pool, and the generic scavenger who takes over the centre once he's beaten (a Route 3 Trainer's,
# EFU_FLAG_CHILDCARE_GENERIC), and its Rare Candy
CHILDCARE_TRAINER = 401
CHILDCARE_NAME = 'Billy'
CHILDCARE_GENERIC_TRAINER = 398
CHILDCARE_CANDY_SCRIPT = 7280
EFU_WORK_RAID = int(re.search(r'#define EFU_WORK_RAID (0x[0-9a-f]+)', efu_h).group(1), 16)
# The work the Trainer battle scripts pass Script_ScavDrop its Trainer in, one global_3000.s never uses
SCAV_DROP_TRAINER_WORK = 0x803f
SCRIPT_SCAV_DROP = 11000 + int(re.search(r'#define EFU_SCRIPT_SCAV_DROP \(EFU_SCRIPT_FIRST \+ (\d+)\)', efu_h).group(1))
def efu_script(name):
    return 11000 + int(re.search(r'#define EFU_SCRIPT_%s \(EFU_SCRIPT_FIRST \+ (\d+)\)' % name, efu_h).group(1))


def efu_flag(name):
    return 'EVENT_FLAG_0x%04x' % int(re.search(r'#define EFU_FLAG_%s (0x[0-9a-f]+)' % name, efu_h).group(1), 16)


# Nurse Joy, in the northwest of the target (Pinwheel Forest's inner forest), until she joins the base
JOY = {'id': 120, 'model': 'OBJ_CODE_78', 'movement': 'MOVE_CODE_FACE_DOWN', 'type': 'ACTOR_EVENT_TYPE_NONE',
       'flag': efu_flag('JOY_JOINED'), 'script': efu_script('JOY_FOREST'), 'direction': 'DIR_DOWN',
       'params': [0, 0, 0], 'area': {'width': 0, 'height': 0}, 'grid': {'x': 12, 'z': 45, 'y': 0}}
# The original item balls' scripts (each gives its own item) and the hidden items'
ITEM_SCRIPTS = (7000, 7799)
HIDDEN_SCRIPTS = (8000, 8799)
# The target, Pinwheel Forest's inner forest, between Route 2 and Route 19
TARGET_ZONE = 'ZONE_PINWHEEL_FOREST_2'
# The caves and the target: each zone's loot tier, and which door of Route 3's leads in
PLACES = {
    'ZONE_WELLSPRING_CAVE': ('cave', 'ZONE_WELLSPRING_CAVE'),
    'ZONE_WELLSPRING_CAVE_2': ('cave', 'ZONE_WELLSPRING_CAVE'),
    'ZONE_CAVE_OF_BEING': ('cave', 'ZONE_CAVE_OF_BEING'),
    TARGET_ZONE: ('target', TARGET_ZONE),
}
# The target's Trainers that are scavs there, each out on EFU_SIDE_SCAV_CHANCE percent of entries
# (Script_TargetEnter), with a hide flag of their own from EFU_FLAG_TARGET_SCAV_FIRST
TARGET_SCAVS = [643, 642, 645]
# The zone's doors that are shut on some explorations, a boulder in front of each, hidden by its flag from
# EFU_FLAG_DOOR_FIRST in this order: the childcare centre, Wellspring Cave and the Cave of Being (the Day Care's door is
# never shut, so the Day Care Lady can always be reached)
DOORS = ['ZONE_ROUTE_3_2', 'ZONE_WELLSPRING_CAVE', 'ZONE_CAVE_OF_BEING']
# The doors behind Cut trees, always there, in place of the boulder (Wellspring Cave's flag is rolled but nothing reads it)
CUT_DOORS = ['ZONE_WELLSPRING_CAVE']
# The original's scripts of a Cut tree and a Strength boulder (global 10000)
CUT_TREE_SCRIPT = 10004
STRENGTH_SCRIPT = 10000
# The inner forest's two bridges on its road north, each two tiles wide: the tiles before them from the south, where
# heading out may put a Cut tree on the left one and a Strength boulder on the right one (EFU_FLAG_BRIDGE_*), so the
# forest's west path may be the only way through
BRIDGE_CUT = [(71, 55), (72, 55)]
BRIDGE_BOULDER = [(75, 55), (76, 55)]
# The scavenger always in the inner forest's grass patch right of the road (EFU_FLAG_FOREST_SCAV), a generic one: its
# Trainer and spot
FOREST_SCAV = {'trainer': 646, 'grid': {'x': 88, 'z': 45}}
# The tile a warp is walked into from, by the direction the player faces on arriving there (the warp's unk4, a DIR_*
# plus 1): the player walks into it the other way
APPROACH = {1: (0, -1), 2: (0, 1), 3: (-1, 0), 4: (1, 0)}
# The routes' scavs' NPC IDs, from this one (the garden's is the one before)
SPOT_ID_FIRST = 128
# The guide, out on Route 3 by the way in, until the player has met them (Script_GuideMeet)
GUIDE = {'id': 121, 'model': 'OBJ_CODE_76', 'movement': 'MOVE_CODE_FACE_DOWN', 'type': 'ACTOR_EVENT_TYPE_NONE',
         'flag': efu_flag('GUIDE_MET'), 'script': efu_script('GUIDE_MEET'), 'direction': 'DIR_DOWN',
         'params': [0, 0, 0], 'area': {'width': 0, 'height': 0}, 'grid': {'x': 684, 'z': 594, 'y': 0}}
# The inner forest's ways out, by the zone each led to: A, its way in from the garden's path south (its old way out to the
# outer forest), B, out to Route 19's old gate to Aspertia (its old gate to Skyarrow Bridge), and C, Rumination Field's
# (unchanged)
FOREST_WAYS = {
    'ZONE_PINWHEEL_FOREST': lambda route_warps: {'zone': 'ZONE_ROUTE_3', 'warp': route_warps['garden_south']},
    'ZONE_BRIDGE_GATE': lambda route_warps: {'zone': 'ZONE_ROUTE_19', 'warp': 0},
}
# New item balls, where nothing was: where the lake trio stood in the Cave of Being
NEW_BALLS = {'ZONE_CAVE_OF_BEING': [(27, 18), (17, 7), (9, 16)]}


def orig(path):
    return subprocess.run(['git', 'show', f'{BASE_COMMIT}:{path}'], cwd=root, capture_output=True,
                          check=True).stdout.decode('utf-8')


def write(path, data):
    with open(os.path.join(root, path), 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(data, indent=4, ensure_ascii=False) + '\n')


species = {}
for d in os.listdir(os.path.join(root, 'res/pokemon')):
    p = os.path.join(root, 'res/pokemon', d, 'data.json')
    if os.path.exists(p):
        species['SPECIES_' + d.upper()] = json.load(open(p))
previous = {}
for name, data in species.items():
    for e in data.get('evolutions') or []:
        previous.setdefault(e['species'], (name, e))


def evolution_level(e):
    # A level evolution with no level (by a Moss Rock, an Ice Rock or a magnetic field) counts as the others do
    if e['method'].startswith('EVO_METHOD_LEVEL') and isinstance(e['param'], int) and e['param'] > 0:
        return e['param']
    return OTHER_EVOLUTION_LEVEL


def at_level(name, level):
    """The species as it would be at the level: devolved while its evolution needs a higher level, evolved while its
    next stage's needs a lower one."""
    while name in previous and evolution_level(previous[name][1]) > level:
        name = previous[name][0]
    while True:
        evos = [e for e in (species.get(name, {}).get('evolutions') or []) if e['species'] != 'SPECIES_NONE']
        if not evos or evolution_level(evos[0]) > level:
            return name
        name = evos[0]['species']


def build_encounters(name, levels):
    e = json.loads(orig(f'res/field/encounters/{name}.json'))
    lo, hi = levels

    def slots(lst):
        # Every slot over the whole range: the game picks the level at random between a slot's lowest and highest
        return [[at_level(slot[0], lo), lo, hi] + slot[3:] for slot in lst]

    for season in e:
        if season.startswith('$'):
            continue
        for kind, value in e[season].items():
            if kind == 'rates':
                continue
            if isinstance(value, dict):
                e[season][kind] = {v: slots(l) for v, l in value.items()}
            else:
                e[season][kind] = slots(value)
    write(f'res/field/encounters/{name}.json', e)


# Each exploration swaps every wild slot's species for one of its wild group's (wild_groups.json) whose base stat total is
# within this of its own (Efu_WildSwap in enc_pokeset.c, from the table build_wild_swap writes)
SWAP_BST_BAND = 60


def base_stat_total(species):
    path = os.path.join(root, 'res/pokemon', species[len('SPECIES_'):].lower(), 'data.json')
    return sum(json.load(open(path))['base_stats'].values())


def build_wild_swap():
    """include/efu_wild_swap.h: for each species wild in the zone (as built), the species it may be swapped for, its
    own among them."""
    groups = json.load(open(os.path.join(here, 'wild_groups.json')))['groups']
    group_of = {sp: g for g, members in groups.items() for sp in members}
    wild = set()
    for name in ['route_3'] + list(PLACE_LEVELS):
        wild |= set(re.findall(r'"(SPECIES_[A-Z0-9_]+)"', open(os.path.join(root, f'res/field/encounters/{name}.json')).read()))
    wild.discard('SPECIES_NONE')
    species_ids = [l.split('#')[0].split('=')[0].strip() for l in open(os.path.join(root, 'generated/species.txt'))
                   if l.startswith('SPECIES_')]
    species, first, candidates = [], [0], []
    for sp in sorted(wild, key=species_ids.index):
        bst = base_stat_total(sp)
        options = [sp]
        if sp in group_of:
            options = [o for o in groups[group_of[sp]] if abs(base_stat_total(o) - bst) <= SWAP_BST_BAND]
        species.append(sp)
        candidates += options
        first.append(len(candidates))
    out = ['// Written by tools/efu/build_raid.py (build_wild_swap): the zone\'s wild species, sorted, and for each the\n',
           f'// species an exploration may swap it for, one of its wild group\'s within {SWAP_BST_BAND} of its base stat total\n',
           '#ifndef EFU_WILD_SWAP_H\n#define EFU_WILD_SWAP_H\n\n#include "constants/species.h"\n\n',
           f'#define EFU_SWAP_SPECIES_COUNT {len(species)}\n\n',
           'static const u16 EFU_SWAP_SPECIES[EFU_SWAP_SPECIES_COUNT] = {\n']
    out += [f'    {sp},\n' for sp in species]
    out.append('};\n\n// Where each species\' choices start in EFU_SWAP_CANDIDATES, and the end of the last\n')
    out.append('static const u16 EFU_SWAP_FIRST[EFU_SWAP_SPECIES_COUNT + 1] = {\n')
    out += [f'    {n},\n' for n in first]
    out.append('};\n\n' f'static const u16 EFU_SWAP_CANDIDATES[{len(candidates)}] = {{\n')
    out += [f'    {sp},\n' for sp in candidates]
    out.append('};\n\n#endif // EFU_WILD_SWAP_H\n')
    with open(os.path.join(root, 'include/efu_wild_swap.h'), 'w', newline='\n') as f:
        f.write(''.join(out))
    print('wild swap', len(species), 'species,', len(candidates), 'choices')


def trainer_file(trainer_id):
    names = [l.split('=')[0].strip() for l in open(os.path.join(root, 'generated/trainers.txt'))
             if l.startswith('TRAINER_')]
    return 'res/trainers/data/' + names[trainer_id][len('TRAINER_'):].lower() + '.json'


def scav_key(trainer_id):
    return os.path.basename(trainer_file(trainer_id))[:-len('.json')]


def build_classes():
    for female, cls in SCAV_CLASS.items():
        path = 'res/trainers/classes/' + cls[len('TRAINER_CLASS_'):].lower() + '.json'
        c = json.loads(orig(path))
        c['name'] = SCAV_CLASS_NAME
        c['name_with_article'] = 'a ' + SCAV_CLASS_NAME
        write(path, c)


def chunk_of(x, z):
    return (x // 32, z // 32)


def moved(chunk, x, z):
    zx, zz = bz.ZONE_CHUNKS[chunk]
    return x + (zx - chunk[0]) * 32, z + (zz - chunk[1]) * 32


def move_npc(n):
    g = n['grid']
    chunk = chunk_of(g['x'], g['z'])
    x, z = moved(chunk, g['x'], g['z'])
    return dict(n, grid=dict(g, x=x, z=z, y=g['y'] + bz.RAISED.get(chunk, 0) * 4096))


def move_warp(w):
    g = w['grid']
    chunk = chunk_of(g['x'] // 16, g['z'] // 16)
    x, z = moved(chunk, g['x'] // 16, g['z'] // 16)
    # The height is kept as 16 bits, a negative one wrapped
    y = (g['y'] + bz.RAISED.get(chunk, 0)) & 0xffff
    return dict(w, grid=dict(g, x=x * 16 + g['x'] % 16, z=z * 16 + g['z'] % 16, y=y))


def move_bg(b):
    # A background event's grid is x, y (the row) and z (the height)
    g = b['grid']
    chunk = chunk_of(g['x'], g['y'])
    x, z = moved(chunk, g['x'], g['y'])
    return dict(b, grid=dict(g, x=x, y=z, z=g['z'] + bz.RAISED.get(chunk, 0)))


def move_trigger(t):
    g = t['grid']
    chunk = chunk_of(g['x'], g['z'])
    x, z = moved(chunk, g['x'], g['z'])
    return dict(t, grid=dict(g, x=x, z=z, y=g['y'] + bz.RAISED.get(chunk, 0)))


def is_item_ball(n):
    return ITEM_SCRIPTS[0] <= n['script'] <= ITEM_SCRIPTS[1] and n['flag']


def scav_npc(n, tid, npc_id, flag):
    """A scav standing where n stood, fighting as Trainer tid, hidden by flag until it comes out."""
    female = SCAVS[scav_key(tid)][0]
    return dict(n, id=npc_id, model=SCAV_MODEL[female], movement='MOVE_CODE_TURN_RANDOM',
                type='ACTOR_EVENT_TYPE_TRAINER', script=3000 + tid, params=[SCAV_SIGHT, 0, 0],
                flag='EVENT_FLAG_0x%04x' % flag, area={'width': SCAV_WANDER, 'height': SCAV_WANDER})


def is_person(n):
    # A person, not an object (a boulder, a sign, a Pokémon), whose model is named for what they are
    model = n['model'][len('OBJ_CODE_'):]
    return not model[0].isdigit() and not model.startswith('MODEL_') and not (
        ITEM_SCRIPTS[0] <= n['script'] <= ITEM_SCRIPTS[1])


class Scavs:
    """The routes' scavs: one at each spot where one of a route's people stood (and the garden's, Striaton's west
    chunk, on Route 3), each hidden by its own flag from EFU_FLAG_SPOT_FIRST until a roll brings it out
    (Script_RouteEnter, EfuScav_Spawn). Each fights as one of its route's Trainers, in turn."""

    def __init__(self):
        self.next_flag = FLAG_SPOT_FIRST
        self.trainers = set()

    def spots(self, people, pool):
        npcs = []
        for i, n in enumerate(people):
            assert self.next_flag < FLAG_SPOT_FIRST + SPOT_MAX
            tid = pool[i % len(pool)]
            self.trainers.add(tid)
            npcs.append(move_npc(scav_npc(n, tid, SPOT_ID_FIRST + i, self.next_flag)))
            self.next_flag += 1
        return npcs


def is_scav(n):
    # One Trainer of a double battle pair (the second's script is 2000 above the first's) goes; the scavs fight alone
    return (n['type'].startswith('ACTOR_EVENT_TYPE_TRAINER') and n['script'] < 5000
            and scav_key(n['script'] - 3000) in SCAVS and n['script'] - 3000 != CHILDCARE_TRAINER)


def obstacle(npc_id, kind, flag, x, z, y=0):
    """A Cut tree or a Strength boulder (OBJ_CODE_MODEL_3, the boulder with a drawn model; the other rock codes draw
    nothing) with the original's script, hidden by flag (0 for always there)."""
    model, script = {'cut': ('OBJ_CODE_108', CUT_TREE_SCRIPT), 'strength': ('OBJ_CODE_MODEL_3', STRENGTH_SCRIPT)}[kind]
    return {'id': npc_id, 'model': model, 'movement': 'MOVE_CODE_NONE', 'type': 'ACTOR_EVENT_TYPE_NONE', 'flag': flag,
            'script': script, 'direction': 'DIR_DOWN', 'params': [0, 0, 0], 'area': {'width': 0, 'height': 0},
            'grid': {'x': x, 'z': z, 'y': y}}


def door_boulders(warps, zones, first_id, flag_of):
    """A boulder in front of each door that can be shut (one for each tile of a wider way in), hidden while open, and
    the Cut trees always in front of Wellspring Cave's."""
    npcs = []
    for zone in zones:
        w = next(w for w in warps if w['zone'] == zone)
        dx, dz = APPROACH[w['unk4']]
        g = w['grid']
        for tx in range(g['width']):
            for tz in range(g['height']):
                if zone in CUT_DOORS:
                    npcs.append(obstacle(first_id + len(npcs), 'cut', 0, g['x'] // 16 + tx + dx,
                                         g['z'] // 16 + tz + dz, ((g['y'] ^ 0x8000) - 0x8000) * 4096))
                    continue
                npcs.append({'id': first_id + len(npcs), 'model': 'OBJ_CODE_MODEL_3', 'movement': 'MOVE_CODE_NONE',
                             'type': 'ACTOR_EVENT_TYPE_NONE', 'flag': flag_of(zone),
                             'script': efu_script('BLOCKED_DOOR'), 'direction': 'DIR_DOWN', 'params': [0, 0, 0],
                             'area': {'width': 0, 'height': 0},
                             'grid': {'x': g['x'] // 16 + tx + dx, 'z': g['z'] // 16 + tz + dz,
                                      'y': ((g['y'] ^ 0x8000) - 0x8000) * 4096}})
    return npcs


def door_flag(zone):
    return 'EVENT_FLAG_0x%04x' % (FLAG_DOOR_FIRST + DOORS.index(zone))


def route_trainers(name):
    e = json.loads(orig(f'res/field/events/{name}.json'))
    return [n['script'] - 3000 for n in e['npcs'] if is_scav(n)]


def build_route(name, loot, scavs, pool, warps=None, extra_npcs=(), triggers=None, spot_extra=()):
    """A route of the zone: its scavs (one at each of its people's spots, and spot_extra's, fighting as pool's
    Trainers) and item balls (loot), in the matrix's coordinates, its signs, and its doors (warps: each original warp's
    new zone and warp, None to keep it); a scav may come out on each entry (Script_RouteEnter)."""
    e = json.loads(orig(f'res/field/events/{name}.json'))
    npcs = []
    for n in e['npcs']:
        if is_item_ball(n):
            npcs.append(move_npc(loot.ball(n, 'route')))
    npcs += scavs.spots([n for n in e['npcs'] if is_person(n)] + list(spot_extra), pool)
    # Signs and the like stay (the route's own scripts); the hidden items go, since they can't be rolled again
    e['bg_events'] = [move_bg(b) for b in e['bg_events'] if not HIDDEN_SCRIPTS[0] <= b['script'] <= HIDDEN_SCRIPTS[1]]
    # Their story's triggers (the rival's and Bianca's lessons) go, Route 3's aside
    e['triggers'] = [move_trigger(t) for t in e['triggers']] if triggers is None else triggers
    out = []
    for i, w in enumerate(e['warps']):
        w = move_warp(w)
        if warps and i in warps:
            if warps[i] is None:
                continue
            w = dict(w, **warps[i])
        out.append(w)
    for w in (warps or {}).get('new', []):
        out.append(w)
    e['warps'] = out
    first = max([n['id'] for n in npcs] + [0]) + 1
    npcs += door_boulders(out, [z for z in DOORS if any(w['zone'] == z for w in out)], first, door_flag)
    npcs += list(extra_npcs)
    e['npcs'] = npcs
    e['init_scripts'] = [{'type': 2, 'script': efu_script('ROUTE_ENTER')}]
    write(f'res/field/events/{name}.json', e)
    return e['warps']


# The garden's road east, where it met the rest of Striaton: a warp walked into (going right) on the forest's first
# column, to Route 2's south end, and that end's way back (going down), below the path's last tiles (tiles 14 and 15 of
# chunk 23, 20)
GARDEN_EAST = {'zone': 'ZONE_ROUTE_2', 'unk4': 3, 'transition': 4,
               'grid': {'x': (24 * 32) * 16 + 8, 'y': 0, 'z': (18 * 32 + 14) * 16 + 8, 'width': 1, 'height': 4,
                        'unk0a': 0}}
ROUTE_2_SOUTH = {'zone': 'ZONE_ROUTE_3', 'unk4': 1, 'transition': 4,
                 'grid': {'x': (23 * 32 + 14) * 16 + 8, 'y': 0, 'z': (20 * 32 + 14) * 16 + 8, 'width': 2,
                          'height': 1, 'unk0a': 0}}
# The forest's way in (A on Tom's map): the end of the path cut south from the garden (build_zone.py's CUTS), a warp
# walked into going down on the trees' first row past it (tiles 17 to 20 of chunk 23, 19)
GARDEN_SOUTH = {'zone': 'ZONE_PINWHEEL_FOREST_2', 'warp': 0, 'unk4': 1, 'transition': 4,
                'grid': {'x': (23 * 32 + 17) * 16 + 8, 'y': 0, 'z': (19 * 32) * 16 + 8, 'width': 4, 'height': 1,
                         'unk0a': 0}}
# The garden's scav, out on every raid from the start (EFU_FLAG_GARDEN_SCAV): its Trainer, and the spot it stands on
# (the Pokémon Breeder's), which no other scav takes
GARDEN_SCAV = {'trainer': 395, 'grid': {'x': 755, 'z': 588}}
# Striaton's people in the garden: Route 3's spots there
GARDEN_CHUNK = (23, 18)


def garden_people():
    e = json.loads(orig('res/field/events/striaton_city.json'))
    return [n for n in e['npcs'] if is_person(n) and chunk_of(n['grid']['x'], n['grid']['z']) == GARDEN_CHUNK
            and (n['grid']['x'], n['grid']['z']) != (GARDEN_SCAV['grid']['x'], GARDEN_SCAV['grid']['z'])]


def garden_scav():
    e = json.loads(orig('res/field/events/striaton_city.json'))
    n = next(n for n in e['npcs'] if (n['grid']['x'], n['grid']['z']) == (GARDEN_SCAV['grid']['x'],
                                                                         GARDEN_SCAV['grid']['z']))
    return move_npc(scav_npc(n, GARDEN_SCAV['trainer'], SPOT_ID_FIRST - 1,
                             int(efu_flag('GARDEN_SCAV')[len('EVENT_FLAG_'):], 16)))


def build_events(loot):
    """The zone's routes: Route 3 (with Striaton's garden), Route 2, Route 19, Route 20 and Floccesy Ranch."""
    scavs = Scavs()
    route_3_pool = route_trainers('route_3')
    route_20_pool = route_trainers('route_20')
    route_2_pool = route_trainers('route_2')
    scavs.trainers.add(GARDEN_SCAV['trainer'])
    route_2_n = len(json.loads(orig('res/field/events/route_2.json'))['warps'])
    route_3_n = len(json.loads(orig('res/field/events/route_3.json'))['warps'])
    route_3 = build_route('route_3', loot, scavs, route_3_pool, extra_npcs=[GUIDE, garden_scav()],
                          spot_extra=garden_people(),
                          warps={'new': [dict(GARDEN_EAST, warp=route_2_n), GARDEN_SOUTH]})
    build_route('route_20', loot, scavs, route_20_pool, warps={
        # The gate to Virbank is a way home, and the Cave of Being a cave
        0: {'zone': 'ZONE_NACRENE_GATE', 'warp': 0}}, triggers=[])
    gate = json.loads(orig('res/field/events/route_2.json'))['warps'][0]['grid']
    dx, dz = APPROACH[3]
    build_route('route_2', loot, scavs, route_2_pool, warps={
        # Its old gate to Accumula Town is a ride home for a fee (Script_PaidExit, a trigger in front of it)
        0: {'zone': 'ZONE_NACRENE_GATE', 'warp': 0}, 'new': [dict(ROUTE_2_SOUTH, warp=route_3_n)]},
        triggers=[{'script': efu_script('PAID_EXIT'), 'var': 'EVENT_WORK_0x%04x' % EFU_WORK_RAID, 'value': 1,
                   'type': 0, 'grid': {'x': gate['x'] // 16 + dx, 'z': gate['z'] // 16 + dz, 'width': 1,
                                       'height': gate['height'], 'y': 0}, 'unk14': 0}])
    # Route 19's gate to Aspertia is the forest's way out (B), now a path into the trees. It has no Trainers of its
    # own, so its scavs are Route 20's
    build_route('route_19', loot, scavs, route_20_pool, warps={0: {'zone': 'ZONE_PINWHEEL_FOREST_2', 'warp': 1}},
                triggers=[])
    build_route('floccesy_ranch', loot, scavs, route_20_pool, triggers=[])
    build_ranch(route_20_pool)
    print('route spots', scavs.next_flag - FLAG_SPOT_FIRST, 'of', SPOT_MAX)
    route_warps = {'route_3': {w['zone']: i for i, w in enumerate(route_3)}, 'garden_south': route_3_n + 1}
    return sorted(scavs.trainers), route_warps


# Floccesy Ranch, overrun: scavengers at these spots of the ranch itself (ZONE_FLOCCESY_RANCH_2, on its ground at height
# 32, spread over its fields), fighting as Route 20's Trainers, each out by chance like the target's. The roll is the
# ranch entrance's init script (Script_RanchEnter), since the ranch keeps its own, and the entrance is its only way in
RANCH_SPOTS = [(10, 40), (36, 40), (50, 38), (38, 52), (46, 25), (36, 14)]
RANCH_HEIGHT = 32
FLAG_RANCH_SCAV_FIRST = int(re.search(r'#define EFU_FLAG_RANCH_SCAV_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
assert int(re.search(r'#define EFU_RANCH_SCAV_COUNT (\d+)', efu_h).group(1)) == len(RANCH_SPOTS)

# The tinkerer, at the ranch's back (north) end, always there (Script_Tinkerer)
TINKERER = {'model': 'OBJ_CODE_SCIENTIST_F_46', 'movement': 'MOVE_CODE_FACE_DOWN', 'type': 'ACTOR_EVENT_TYPE_NONE',
            'flag': 0, 'script': efu_script('TINKERER'), 'direction': 'DIR_DOWN', 'params': [0, 0, 0],
            'area': {'width': 0, 'height': 0}, 'grid': {'x': 40, 'z': 10, 'y': RANCH_HEIGHT * 4096}}


def build_ranch(pool):
    """Floccesy Ranch's scavengers (RANCH_SPOTS), whose rolls on each entry to its entrance (Script_RanchEnter) take
    the place of a route's."""
    path = 'res/field/events/floccesy_ranch_2.json'
    e = json.loads(orig(path))
    first = max([n['id'] for n in e['npcs']] + [0]) + 1
    for i, (x, z) in enumerate(RANCH_SPOTS):
        tid = pool[i % len(pool)]
        n = {'id': first + i, 'model': '', 'movement': '', 'type': '', 'flag': 0, 'script': 0, 'direction': 'DIR_DOWN',
             'params': [0, 0, 0], 'area': {}, 'grid': {'x': x, 'z': z, 'y': RANCH_HEIGHT * 4096}}
        e['npcs'].append(scav_npc(n, tid, first + i, FLAG_RANCH_SCAV_FIRST + i))
    e['npcs'].append(dict(TINKERER, id=first + len(RANCH_SPOTS)))
    write(path, e)
    path = 'res/field/events/floccesy_ranch.json'
    e = json.load(open(os.path.join(root, path)))
    e['init_scripts'] = [{'type': 2, 'script': efu_script('RANCH_ENTER')}]
    write(path, e)
    with open(os.path.join(here, 'ranch_scavs.txt'), 'w') as f:
        f.write(' '.join(str(pool[i % len(pool)]) for i in range(len(RANCH_SPOTS))) + '\n')


# Rumination Field: Burgh, its boss, until he is beaten (EFU_FLAG_BURGH_BEATEN), then sometimes a generic scavenger in his
# place (EFU_FLAG_RUMINATION_SCAV): their spot and the scavenger's Trainer
RUMINATION_SPOT = {'x': 16, 'z': 10}
RUMINATION_SCAV = {'trainer': 640}
BURGH_MODEL = 'OBJ_CODE_225'
# Burgh's team: his Challenge Mode one (leader_burgh_2, 2 levels up as Castelia's Gym gives it) and two more Bug types
# to make six, at its levels. He fights as LEADER_BURGH, whose own team the Gym would use
BURGH_TEAM = [('SPECIES_SWADLOON', 24, ['MOVE_STRUGGLE_BUG', 'MOVE_RAZOR_LEAF', 'MOVE_STRING_SHOT', 'MOVE_PROTECT']),
              ('SPECIES_WHIRLIPEDE', 25, ['MOVE_POISON_TAIL', 'MOVE_PURSUIT', 'MOVE_PROTECT', 'MOVE_SCREECH'])]
BURGH_LEVEL_UP = 2


def build_rumination():
    path = 'res/field/events/rumination_field.json'
    e = json.loads(orig(path))
    grid = dict(RUMINATION_SPOT, y=0)
    burgh = {'id': 0, 'model': BURGH_MODEL, 'movement': 'MOVE_CODE_FACE_DOWN', 'type': 'ACTOR_EVENT_TYPE_NONE',
             'flag': efu_flag('BURGH_BEATEN'), 'script': efu_script('BURGH'), 'direction': 'DIR_DOWN',
             'params': [0, 0, 0], 'area': {'width': 0, 'height': 0}, 'grid': grid}
    scav = scav_npc(dict(burgh, grid=grid), RUMINATION_SCAV['trainer'], 1,
                    int(efu_flag('RUMINATION_SCAV')[len('EVENT_FLAG_'):], 16))
    e['npcs'] = [burgh, scav]
    e['init_scripts'] = []
    write(path, e)
    t = json.loads(orig('res/trainers/data/leader_burgh_2.json'))
    team = [dict(t['party'][0], species=sp, level=lv, moves=mv, item='ITEM_NONE') for sp, lv, mv in BURGH_TEAM]
    team += [dict(p, level=p['level'] + BURGH_LEVEL_UP) for p in t['party']]
    team.sort(key=lambda p: p['level'])
    burgh_trainer = json.loads(orig('res/trainers/data/leader_burgh.json'))
    burgh_trainer['party'] = team
    write('res/trainers/data/leader_burgh.json', burgh_trainer)
    return RUMINATION_SCAV['trainer']


def build_daycare():
    """Route 3's Day Care (ROUTE_3_3): only the Day Care Lady, who offers to join the base for a fee and takes
    Pokémon in but never gives them back here (Script_DayCareJoin); they come back at her base warehouse. Her original
    script (global 2201) leaves Withdraw out of its menu while EFU_FLAG_DAYCARE_DEPOSIT_ONLY is set."""
    e = json.loads(orig('res/field/events/route_3_3.json'))
    lady = [n for n in e['npcs'] if n['script'] == 2201][0]
    e['npcs'] = [dict(lady, script=efu_script('DAYCARE_JOIN'))]
    write('res/field/events/route_3_3.json', e)
    path = 'res/field/scripts/global_2200.s'
    text = orig(path)
    withdraw = '    VMJumpIf CMP_STACK, L_03A7\n    ListMenuAdd 31, 65535, 31\n'
    assert text.count(withdraw) == 1
    flag = int(re.search(r'#define EFU_FLAG_DAYCARE_DEPOSIT_ONLY (0x[0-9a-f]+)', efu_h).group(1), 16)
    with open(os.path.join(root, path), 'w', newline='\n') as f:
        f.write(text.replace(withdraw, '    VMJumpIf CMP_STACK, L_03A7\n'
                             '    // Escape from Unova: no Withdraw where she only takes Pokémon in (build_raid.py)\n'
                             f'    FlagGet 0x{flag:x}, 0x8020\n    WorkCmpConst 0x8020, 1\n    VMJumpIf CMP_EQ, L_03A7\n'
                             '    ListMenuAdd 31, 65535, 31\n'))


def build_pc():
    """The PC (global 10090): out on a raid it only takes Pokémon in, so its menu keeps Deposit and Log Off. Only the
    base's PC gives them back."""
    path = 'res/field/scripts/global_10090.s'
    text = orig(path)
    menu = ('    ListMenuAdd 15, 21, 15\n    ListMenuAdd 16, 22, 16\n    ListMenuAdd 17, 23, 17\n'
            '    ListMenuAdd 20, 26, 20\n    ListMenuAdd 18, 24, 18\n    ListMenuAdd 19, 25, 19\n')
    assert text.count(menu) == 1
    raid = int(re.search(r'#define EFU_WORK_RAID (0x[0-9a-f]+)', efu_h).group(1), 16)
    with open(os.path.join(root, path), 'w', newline='\n') as f:
        f.write(text.replace(menu, '    ListMenuAdd 15, 21, 15\n'
                             '    // Escape from Unova: out on a raid, the PC only takes Pokémon in (build_raid.py)\n'
                             f'    WorkCmpConst 0x{raid:x}, 0\n    VMJumpIf CMP_NE, L_EfuDepositOnly\n'
                             '    ListMenuAdd 16, 22, 16\n    ListMenuAdd 17, 23, 17\n'
                             '    ListMenuAdd 20, 26, 20\n    ListMenuAdd 18, 24, 18\n'
                             'L_EfuDepositOnly:\n    ListMenuAdd 19, 25, 19\n'))


def build_childcare(loot):
    """The childcare centre on Route 3 (ROUTE_3_2): nobody left but its Rare Candy, out on 10% of explorations, and on
    30% of entries a scav (Script_ChildcareEnter)."""
    e = json.loads(orig('res/field/events/route_3_2.json'))
    candy = next(n for n in e['npcs'] if n['script'] == CHILDCARE_CANDY_SCRIPT)
    loot.spots.append({'flag': candy['flag'], 'place': 'candy'})
    first = max(n['id'] for n in e['npcs']) + 1
    scavs = []
    for i, (tid, flag) in enumerate([(CHILDCARE_TRAINER, efu_flag('CHILDCARE_SCAV')),
                                     (CHILDCARE_GENERIC_TRAINER, efu_flag('CHILDCARE_GENERIC'))]):
        female = SCAVS[scav_key(tid)][0]
        scavs.append({'id': first + i, 'model': SCAV_MODEL[female], 'movement': 'MOVE_CODE_TURN_RANDOM',
                      'type': 'ACTOR_EVENT_TYPE_TRAINER', 'flag': flag, 'script': 3000 + tid, 'direction': 'DIR_DOWN',
                      'params': [SCAV_SIGHT, 0, 0], 'area': {'width': 1, 'height': 1},
                      'grid': {'x': 5, 'z': 5, 'y': 0}})
    e['npcs'] = [candy] + scavs
    e['init_scripts'] = [{'type': 2, 'script': SCRIPT_CHILDCARE}]
    write('res/field/events/route_3_2.json', e)
    return CHILDCARE_TRAINER


def build_places(loot, route_warps):
    """The caves and the target: only their item balls, as loot, and their way out to the zone."""
    for zone, (tier, door) in PLACES.items():
        name = zone[len('ZONE_'):].lower()
        e = json.loads(orig(f'res/field/events/{name}.json'))
        e['npcs'] = [loot.ball(n, tier) for n in e['npcs'] if is_item_ball(n)]
        for i, (x, z) in enumerate(NEW_BALLS.get(zone, [])):
            e['npcs'].append(loot.ball({'id': 100 + i, 'model': 'OBJ_CODE_110', 'movement': 'MOVE_CODE_NONE',
                                        'type': 'ACTOR_EVENT_TYPE_NONE', 'flag': loot.new_flag(), 'script': 0,
                                        'direction': 'DIR_DOWN', 'params': [0, 0, 0],
                                        'area': {'width': 0, 'height': 0}, 'grid': {'x': x, 'z': z, 'y': 0}}, tier))
        e['bg_events'] = [b for b in e['bg_events'] if not HIDDEN_SCRIPTS[0] <= b['script'] <= HIDDEN_SCRIPTS[1]]
        # Their story (the lake trio, the forest's rangers and scientists) doesn't happen
        e['triggers'] = []
        e['init_scripts'] = []
        warps = []
        for w in e['warps']:
            if w['zone'] == 'ZONE_ROUTE_3':
                warps.append(dict(w, warp=route_warps['route_3'][door]))
            elif w['zone'] in FOREST_WAYS:
                # The forest's ways: in from Route 2 (A), out to Route 19 (B) and Rumination Field (C)
                warps.append(dict(w, **FOREST_WAYS[w['zone']](route_warps)))
            else:
                # Its other floors, and the Cave of Being's way back to Route 20, which keeps its warps' numbers
                warps.append(w)
        e['warps'] = warps
        if zone == TARGET_ZONE:
            e['npcs'].append(JOY)
            original = json.loads(orig(f'res/field/events/{name}.json'))
            for i, tid in enumerate(TARGET_SCAVS):
                n = next(n for n in original['npcs'] if n['script'] == 3000 + tid)
                female = SCAVS[scav_key(tid)][0]
                e['npcs'].append(dict(n, model=SCAV_MODEL[female], movement='MOVE_CODE_TURN_RANDOM',
                                      params=[SCAV_SIGHT, 0, 0], area={'width': 1, 'height': 1},
                                      flag='EVENT_FLAG_0x%04x' % (FLAG_TARGET_SCAV_FIRST + i)))
            n = next(n for n in original['npcs'] if n['script'] == 3000 + FOREST_SCAV['trainer'])
            e['npcs'].append(scav_npc(dict(n, grid=dict(n['grid'], **FOREST_SCAV['grid'], y=0)), FOREST_SCAV['trainer'],
                                      n['id'], int(efu_flag('FOREST_SCAV')[len('EVENT_FLAG_'):], 16)))
            first = max(n['id'] for n in e['npcs']) + 1
            for kind, tiles, flag in (('cut', BRIDGE_CUT, 'BRIDGE_CUT'), ('strength', BRIDGE_BOULDER, 'BRIDGE_BOULDER')):
                for x, z in tiles:
                    e['npcs'].append(obstacle(first, kind, efu_flag(flag), x, z))
                    first += 1
            e['init_scripts'] = [{'type': 2, 'script': efu_script('TARGET_ENTER')}]
        write(f'res/field/events/{name}.json', e)


class Loot:
    """The loot spots: each item ball's flag and tier, for gen_efu.py's scripts (loot.json)."""

    def __init__(self):
        self.spots = []
        self.flags = iter(range(FLAG_LOOT_FIRST, FLAG_LOOT_FIRST + 0x10))

    def new_flag(self):
        return 'EVENT_FLAG_0x%04x' % next(self.flags)

    def ball(self, n, tier):
        self.spots.append({'flag': n['flag'], 'place': tier})
        return dict(n, script=LOOT_SCRIPTS[tier])

    def save(self):
        with open(os.path.join(here, 'loot.json'), 'w') as f:
            f.write(json.dumps(self.spots, indent=4) + '\n')


def wild_species():
    """The species found wild anywhere in the zone, as built (build_encounters)."""
    found = set()

    def walk(v):
        if isinstance(v, list) and v and isinstance(v[0], str) and v[0].startswith('SPECIES_'):
            found.add(v[0])
        elif isinstance(v, (list, dict)):
            for w in (v.values() if isinstance(v, dict) else v):
                walk(w)

    for name in ['route_3'] + list(PLACE_LEVELS):
        walk(json.load(open(os.path.join(root, f'res/field/encounters/{name}.json'))))
    found.discard('SPECIES_NONE')
    return sorted(found)


def build_trainers(trainer_ids):
    lo, hi = SCAV_LEVELS
    pool = wild_species()
    for i, tid in enumerate(sorted(trainer_ids)):
        path = trainer_file(tid)
        t = json.loads(orig(path))
        # Seeded by the Trainer, so a rebuild gives the same teams
        rng = random.Random(tid)
        level = lo + (i * (hi - lo)) // max(1, len(trainer_ids) - 1)
        size = rng.randint(*SCAV_TEAM)
        t['battle_style'] = 'BTL_STYLE_SINGLE'
        # Defeating a scav drops loot from the target's table (Script_ScavDrop), not the Trainer's own reward
        t['reward'] = 'ITEM_NONE'
        female, start, lose, after = SCAVS[scav_key(tid)]
        t['class'] = SCAV_CLASS[female]
        t['messages'] = [{'type': 'TRMSG_START', 'text': start}, {'type': 'TRMSG_LOSE', 'text': lose},
                         {'type': 2, 'text': after}]
        # Their own Pokémon first, then the zone's wild ones; Billy's from the starters' pool. On an exploration, the
        # wild groups of the place they fight in replace them (Efu_ScavParty in field_encount.c)
        party = t['party'][:size]
        while len(party) < size:
            party.append(dict(t['party'][0], species=rng.choice(pool), gender=0, ability=0))
        if tid == CHILDCARE_TRAINER:
            t['name'] = CHILDCARE_NAME
            starters = [c for c, n, types in json.load(open(os.path.join(here, 'starters.json')))]
            party = [dict(mon, species=rng.choice(starters), gender=0, ability=0) for mon in party]
        for j, mon in enumerate(party):
            mon['level'] = min(hi, level + j % 2)
            mon['species'] = at_level(mon['species'], mon['level'])
        t['party'] = party
        write(path, t)
        print(path, [(m['species'][8:], m['level']) for m in t['party']])


def build_trainer_scripts():
    """The Trainers' global script (3000): each win, single, double or multi, ends with the scavenger's drop
    (Script_ScavDrop), which takes the Trainer from SCAV_DROP_TRAINER_WORK: the battle's first opponent."""
    path = 'res/field/scripts/global_3000.s'
    out = []
    trainer = None
    for line in orig(path).splitlines(keepends=True):
        m = re.match(r'    CallTrainer(?:Multi)?Battle (0x[0-9a-f]+), (0x[0-9a-f]+|0)', line)
        if m:
            trainer = m.group(2) if 'Multi' in line else m.group(1)
        out.append(line)
        if line == '    CallTrainerBattleEnd\n':
            out.append(f'    WorkSet {SCAV_DROP_TRAINER_WORK:#x}, {trainer}\n    RTCallGlobal {SCRIPT_SCAV_DROP}\n')
    assert ''.join(out).count('    RTCallGlobal') - orig(path).count('    RTCallGlobal') == 5
    with open(os.path.join(root, path), 'w', newline='\n') as f:
        f.write(''.join(out))


if __name__ == '__main__':
    build_encounters('route_3', WILD_LEVELS)
    for place, levels in PLACE_LEVELS.items():
        build_encounters(place, levels)
    build_classes()
    loot = Loot()
    scavs, route_warps = build_events(loot)
    build_places(loot, route_warps)
    scavs.append(build_childcare(loot))
    scavs.append(CHILDCARE_GENERIC_TRAINER)
    scavs += TARGET_SCAVS + [FOREST_SCAV['trainer'], build_rumination()]
    build_daycare()
    build_pc()
    loot.save()
    build_trainers(sorted(set(scavs)))
    build_trainer_scripts()
    build_wild_swap()
