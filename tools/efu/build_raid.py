"""Escape from Unova: the first raid zone, Route 3.

Idempotent, like build_base.py: it reads the originals from git (BASE_COMMIT) and writes
- res/field/encounters/route_3.json: every wild Pokémon at a random level from 2 to 15, each species at the stage it
  has reached by the lowest;
- the route's Trainers (res/trainers/data): the scavs, single battles with their Pokémon at 40 to 60, evolved as far as
  that level takes them;
- res/field/events/route_3.json: nobody but the scavs and the items; each scav, a Team Plasma Grunt to look at, is
  hidden by its own flag from EFU_FLAG_SCAV_FIRST, stands looking around (MOVE_CODE_TURN_RANDOM) once it comes out, never stepping until it has seen the player, and sees
  EFU_SCAV_SIGHT tiles, and the pursuit (event_trainer_eye.c) does the rest;
- the Grunts' Trainer classes, named Scav.
"""
import json, os, random, re, subprocess

import build_zone as bz

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
BASE_COMMIT = 'origin/main'

WILD_LEVELS = (2, 15)
# The caves' and the target's wild Pokémon, a little tougher than the route's
PLACE_LEVELS = {'wellspring_cave': (8, 18), 'wellspring_cave_2': (8, 18), 'pinwheel_forest_2': (12, 22)}
# The zone's level cap, its highest wild level, and the scavs' Pokémon from 65% to 90% of it, two to six of them each
LEVEL_CAP = max([WILD_LEVELS[1]] + [hi for lo, hi in PLACE_LEVELS.values()])
SCAV_LEVELS = (round(LEVEL_CAP * 0.65), round(LEVEL_CAP * 0.9))
SCAV_TEAM = (2, 6)
efu_h = open(os.path.join(root, 'include/efu.h')).read()
SCAV_SIGHT = int(re.search(r'#define EFU_SCAV_SIGHT (\d+)', efu_h).group(1))
# How far a scav wanders from where it starts, in tiles either way
SCAV_WANDER = 3
# A Pokémon that evolves by a stone, trading or friendship has done so by this level
OTHER_EVOLUTION_LEVEL = 36
# Each scav, by its Trainer file: whether it shows as the female Team Plasma Grunt, and what it says before the battle,
# on losing it, and if spoken to after. Their own lines were about the old Route 3 (the school kids' lessons on Triple
# and Rotation Battles, a double-battle pair's cheering)
SCAVS = {
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
}
# The scavs' Trainer class, whichever it was: Team Plasma's Grunts, renamed
SCAV_CLASS = {False: 'TRAINER_CLASS_TEAM_PLASMA_GRUNT_M', True: 'TRAINER_CLASS_TEAM_PLASMA_GRUNT_F'}
SCAV_MODEL = {False: 'OBJ_CODE_TEAM_PLASMA_GRUNT_M', True: 'OBJ_CODE_TEAM_PLASMA_GRUNT_F'}
SCAV_CLASS_NAME = 'Scav'
FLAG_SCAV_FIRST = int(re.search(r'#define EFU_FLAG_SCAV_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
SCAV_MAX = int(re.search(r'#define EFU_SCAV_MAX (\d+)', efu_h).group(1))
FLAG_LOOT_FIRST = int(re.search(r'#define EFU_FLAG_LOOT_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
# The scripts that pick up loot, by tier (gen_efu.py writes them from loot.json and its item tables)
LOOT_SCRIPTS = {t: 11000 + int(re.search(r'#define EFU_SCRIPT_LOOT_%s \(EFU_SCRIPT_FIRST \+ (\d+)\)' % t.upper(),
                                         efu_h).group(1)) for t in ('route', 'cave', 'target')}
SCRIPT_SCAV_DROP = 11000 + int(re.search(r'#define EFU_SCRIPT_SCAV_DROP \(EFU_SCRIPT_FIRST \+ (\d+)\)', efu_h).group(1))
# The original item balls' scripts (each gives its own item) and the hidden items'
ITEM_SCRIPTS = (7000, 7799)
HIDDEN_SCRIPTS = (8000, 8799)
# The target, which Route 20's gate to Virbank now opens on
TARGET_ZONE = 'ZONE_PINWHEEL_FOREST_2'
# The caves and the target: each zone's loot tier, and which door of Route 3's leads in
PLACES = {
    'ZONE_WELLSPRING_CAVE': ('cave', 'ZONE_WELLSPRING_CAVE'),
    'ZONE_WELLSPRING_CAVE_2': ('cave', 'ZONE_WELLSPRING_CAVE'),
    'ZONE_CAVE_OF_BEING': ('cave', 'ZONE_CAVE_OF_BEING'),
    TARGET_ZONE: ('target', TARGET_ZONE),
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
    return dict(n, grid=dict(g, x=x, z=z, y=g['y'] + bz.LOWERED.get(chunk, 0) * 4096))


def move_warp(w):
    g = w['grid']
    chunk = chunk_of(g['x'] // 16, g['z'] // 16)
    x, z = moved(chunk, g['x'] // 16, g['z'] // 16)
    # The height is kept as 16 bits, a negative one wrapped
    y = (g['y'] + bz.LOWERED.get(chunk, 0)) & 0xffff
    return dict(w, grid=dict(g, x=x * 16 + g['x'] % 16, z=z * 16 + g['z'] % 16, y=y))


def move_bg(b):
    # A background event's grid is x, y (the row) and z (the height)
    g = b['grid']
    chunk = chunk_of(g['x'], g['y'])
    x, z = moved(chunk, g['x'], g['y'])
    return dict(b, grid=dict(g, x=x, y=z, z=g['z'] + bz.LOWERED.get(chunk, 0)))


def move_trigger(t):
    g = t['grid']
    chunk = chunk_of(g['x'], g['z'])
    x, z = moved(chunk, g['x'], g['z'])
    return dict(t, grid=dict(g, x=x, z=z, y=g['y'] + bz.LOWERED.get(chunk, 0)))


def is_item_ball(n):
    return ITEM_SCRIPTS[0] <= n['script'] <= ITEM_SCRIPTS[1] and n['flag']


def build_events(loot):
    """Route 3's events and Route 20's item balls and doors, in the zone's coordinates; the item balls become loot."""
    e = json.loads(orig('res/field/events/route_3.json'))
    npcs = []
    scavs = []
    for n in e['npcs']:
        if n['type'] == 'ACTOR_EVENT_TYPE_TRAINER':
            # One Trainer of a double battle pair (the second's script is 2000 above the first's) goes; the scavs
            # fight alone
            if n['script'] >= 5000:
                continue
            # Hidden by their own flag until EventTrainerEye_EfuPursue brings them out
            female = SCAVS[scav_key(n['script'] - 3000)][0]
            n = dict(n, model=SCAV_MODEL[female], movement='MOVE_CODE_TURN_RANDOM', params=[SCAV_SIGHT, 0, 0],
                     flag='EVENT_FLAG_0x%04x' % (FLAG_SCAV_FIRST + len(scavs)),
                     area={'width': SCAV_WANDER, 'height': SCAV_WANDER})
            scavs.append(n['script'] - 3000)
            npcs.append(move_npc(n))
        elif is_item_ball(n):
            npcs.append(move_npc(loot.ball(n, 'route')))
    r20 = json.loads(orig('res/field/events/route_20.json'))
    next_id = max(n['id'] for n in e['npcs']) + 1
    for n in r20['npcs']:
        if (n['type'].startswith('ACTOR_EVENT_TYPE_TRAINER') and n['script'] < 5000
                and scav_key(n['script'] - 3000) in SCAVS):
            female = SCAVS[scav_key(n['script'] - 3000)][0]
            n = dict(n, id=next_id, model=SCAV_MODEL[female], movement='MOVE_CODE_TURN_RANDOM',
                     params=[SCAV_SIGHT, 0, 0], flag='EVENT_FLAG_0x%04x' % (FLAG_SCAV_FIRST + len(scavs)),
                     area={'width': SCAV_WANDER, 'height': SCAV_WANDER})
            scavs.append(n['script'] - 3000)
            npcs.append(move_npc(n))
        elif is_item_ball(n):
            npcs.append(move_npc(dict(loot.ball(n, 'route'), id=next_id)))
        else:
            continue
        next_id += 1
    assert len(scavs) <= SCAV_MAX
    e['npcs'] = npcs
    # Signs and the like stay (Route 3's own scripts); the hidden items go, since they can't be rolled again
    e['bg_events'] = [move_bg(b) for b in e['bg_events'] if not HIDDEN_SCRIPTS[0] <= b['script'] <= HIDDEN_SCRIPTS[1]]
    e['triggers'] = [move_trigger(t) for t in e['triggers']]
    warps = [move_warp(w) for w in e['warps']]
    # Route 20's doors: the gate to Virbank opens on the target, and the Cave of Being is a cave
    for w in r20['warps']:
        w = move_warp(w)
        if w['zone'] == 'ZONE_VIRBANK_GATE':
            warps.append(dict(w, zone=TARGET_ZONE, warp=0))
        elif w['zone'] == 'ZONE_CAVE_OF_BEING':
            warps.append(dict(w, zone='ZONE_CAVE_OF_BEING', warp=0))
    e['warps'] = warps
    write('res/field/events/route_3.json', e)
    return scavs, {w['zone']: i for i, w in enumerate(warps)}


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
            if w['zone'] in ('ZONE_ROUTE_3', 'ZONE_ROUTE_20', 'ZONE_PINWHEEL_FOREST'):
                warps.append(dict(w, zone='ZONE_ROUTE_3', warp=route_warps[door]))
            elif w['zone'] in PLACES:
                # Its other floors
                warps.append(w)
            else:
                # Out anywhere else (the forest's ways to Skyarrow Bridge and Rumination Field) goes, and with it
                # the warp: these come last, so no other warp's number changes
                assert all(x['zone'] not in PLACES for x in e['warps'][e['warps'].index(w):])
                break
        e['warps'] = warps
        write(f'res/field/events/{name}.json', e)


class Loot:
    """The loot spots: each item ball's flag and tier, for gen_efu.py's scripts (loot.json)."""

    def __init__(self):
        self.spots = []
        self.flags = iter(range(FLAG_LOOT_FIRST, FLAG_LOOT_FIRST + 0x10))

    def new_flag(self):
        return 'EVENT_FLAG_0x%04x' % next(self.flags)

    def ball(self, n, tier):
        self.spots.append({'flag': n['flag'], 'tier': tier})
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
        # Their own Pokémon first, then the zone's wild ones
        party = t['party'][:size]
        while len(party) < size:
            party.append(dict(t['party'][0], species=rng.choice(pool), gender=0, ability=0))
        for j, mon in enumerate(party):
            mon['level'] = min(hi, level + j % 2)
            mon['species'] = at_level(mon['species'], mon['level'])
        t['party'] = party
        write(path, t)
        print(path, [(m['species'][8:], m['level']) for m in t['party']])


def build_trainer_scripts():
    """The Trainers' global script (3000): each win against a scav, single or double, ends with its drop."""
    path = 'res/field/scripts/global_3000.s'
    text = orig(path)
    drop = f'    CallTrainerBattleEnd\n    RTCallGlobal {SCRIPT_SCAV_DROP}\n'
    assert text.count('    CallTrainerBattleEnd\n') == 5
    with open(os.path.join(root, path), 'w', newline='\n') as f:
        f.write(text.replace('    CallTrainerBattleEnd\n', drop))


if __name__ == '__main__':
    build_encounters('route_3', WILD_LEVELS)
    for place, levels in PLACE_LEVELS.items():
        build_encounters(place, levels)
    build_classes()
    loot = Loot()
    scavs, route_warps = build_events(loot)
    build_places(loot, route_warps)
    loot.save()
    build_trainers(scavs)
    build_trainer_scripts()
