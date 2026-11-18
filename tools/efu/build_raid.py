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
import json, os, re, subprocess

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
BASE_COMMIT = 'origin/main'

WILD_LEVELS = (2, 15)
SCAV_LEVELS = (40, 60)
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
    'backers_may_mal': (True, "No more cheering! Only taking!\nHand over your stuff!{be01}", "Boo! Hiss!",
                        "I used to cheer on Trainers.\nNow I cheer when they drop things."),
}
# The scavs' Trainer class, whichever it was: Team Plasma's Grunts, renamed
SCAV_CLASS = {False: 'TRAINER_CLASS_TEAM_PLASMA_GRUNT_M', True: 'TRAINER_CLASS_TEAM_PLASMA_GRUNT_F'}
SCAV_MODEL = {False: 'OBJ_CODE_TEAM_PLASMA_GRUNT_M', True: 'OBJ_CODE_TEAM_PLASMA_GRUNT_F'}
SCAV_CLASS_NAME = 'Scav'
FLAG_SCAV_FIRST = int(re.search(r'#define EFU_FLAG_SCAV_FIRST (0x[0-9a-f]+)', efu_h).group(1), 16)
SCAV_MAX = int(re.search(r'#define EFU_SCAV_MAX (\d+)', efu_h).group(1))


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
    return e['param'] if e['method'].startswith('EVO_METHOD_LEVEL') else OTHER_EVOLUTION_LEVEL


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


def build_encounters():
    e = json.loads(orig('res/field/encounters/route_3.json'))
    lo, hi = WILD_LEVELS

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
    write('res/field/encounters/route_3.json', e)


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


def build_events():
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
            npcs.append(n)
        elif n['flag']:
            # Item balls, which have their flag
            npcs.append(n)
    assert len(scavs) <= SCAV_MAX
    e['npcs'] = npcs
    write('res/field/events/route_3.json', e)
    return scavs


def build_trainers(trainer_ids):
    lo, hi = SCAV_LEVELS
    for i, tid in enumerate(sorted(trainer_ids)):
        path = trainer_file(tid)
        t = json.loads(orig(path))
        level = lo + (i * (hi - lo)) // max(1, len(trainer_ids) - 1)
        t['battle_style'] = 'BTL_STYLE_SINGLE'
        female, start, lose, after = SCAVS[scav_key(tid)]
        t['class'] = SCAV_CLASS[female]
        t['messages'] = [{'type': 'TRMSG_START', 'text': start}, {'type': 'TRMSG_LOSE', 'text': lose},
                         {'type': 2, 'text': after}]
        for j, mon in enumerate(t['party']):
            mon['level'] = min(100, level + j % 2)
            mon['species'] = at_level(mon['species'], mon['level'])
        write(path, t)
        print(path, level, [m['species'][8:] for m in t['party']])


if __name__ == '__main__':
    build_encounters()
    build_classes()
    build_trainers(build_events())
