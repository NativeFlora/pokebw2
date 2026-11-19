"""Escape from Unova: builds the player's base, the walled-off south strip of Nacrene City.

Idempotent: it reads the original data from git (the commit in BASE_COMMIT) and writes the hack's versions, so it can
be run again after changing it. It edits:
- res/field/matrices/efu_nacrene.json, a matrix of Nacrene's two chunks and the Route 3 gate's, with sea to the west
  and forest around the rest, which ZONE_NACRENE_CITY uses instead of the overworld's;
- res/field/zones/nacrene_city.json, for that matrix and its Fly point;
- res/field/events/nacrene_city.json: everything moved to the new matrix's coordinates, no NPCs, and only the doors
  of the player's warehouse, the Pokémon Center and the gate open, the rest shut (the Day Care Lady's until she
  has joined);
- the two chunks' collision and props: the passages north are blocked with rubble.
"""
import csv, io, json, os, re, struct, subprocess

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
# The decomp's own data, which this script starts from
BASE_COMMIT = 'origin/main'


def orig(path):
    return subprocess.run(['git', 'show', f'{BASE_COMMIT}:{path}'], cwd=root, capture_output=True, check=True).stdout


def write(path, text):
    with open(os.path.join(root, path), 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


# The overworld chunks (column, row) and where they go in the new matrix
CHUNKS = {(19, 18): (1, 1), (20, 18): (2, 1), (21, 18): (3, 1)}
DX, DZ = (1 - 19) * 32, (1 - 18) * 32  # tiles from overworld to the new matrix
T, S = 'MAP_MODEL_OVERWORLD_2_MAP_OUTTREE', 'MAP_MODEL_OVERWORLD_2_MAP_OUTSEA'
# The sea comes in north of the base and west of it, with a beach where it meets the land (build_coast.py)
MATRIX = [
    [S, S, 'MAP_MODEL_EFU_COAST_N2', T, T],
    ['MAP_MODEL_EFU_COAST_W1', 'MAP_MODEL_OVERWORLD_2_MAP19_18', 'MAP_MODEL_OVERWORLD_2_MAP20_18',
     'MAP_MODEL_OVERWORLD_2_MAP21_18', T],
    ['MAP_MODEL_EFU_COAST_W2', T, T, T, T],
]
MATRIX_CONST = 'MAP_MATRIX_EFU_NACRENE'

# Doors: the warps kept by their target zone, and the others boarded up
OPEN_ZONES = {'ZONE_NACRENE_CITY_8', 'ZONE_NACRENE_CITY_POKEMON_CENTER', 'ZONE_NACRENE_GATE'}
# The Day Care Lady's warehouse's ground floor door (Nacrene's warp 2, EFU_DAYCARE_WARP): shut like the closed doors
# until she has joined, when Script_NacreneInit puts its warp back and its shut door prop goes (build_coast.py)
DAYCARE_DOOR = 2
SCRIPT_BOARDED = 11002  # EFU_SCRIPT_BOARDED_DOOR

# Tiles (overworld chunk 19_18 and 20_18 local x, z) to block, and the rubble props to put there (resource IDs of the
# area's bundle FIELD_PROPS_EXTERIOR_SHARED_PC_01_3: 21 rock_01, 258 rock_02, 134 cart_01, 156 out_dust01). The rubble
# stands on row 17, the first row of the streets north between the buildings, and both it and row 16 behind it are
# blocked: on row 16 alone the carts drew over the walkable row in front, so the player seemed to walk into them
BLOCK = {
    'overworld_2_map19_18': [(x, z) for x in range(21, 26) for z in (16, 17)],
    'overworld_2_map20_18': [(x, z) for x in range(11, 16) for z in (16, 17)],
}
RUBBLE = {
    'overworld_2_map19_18': [(21, 17, 21), (22.5, 17, 134), (24, 17, 258), (25, 17, 21)],
    'overworld_2_map20_18': [(11, 17, 258), (12.5, 17, 156), (14, 17, 21), (15, 17, 134)],
}
BLOCKED_TILE = 0x810001

efu_h = open(os.path.join(root, 'include/efu.h')).read()


def efu_script(name):
    return 11000 + int(re.search(r'#define EFU_SCRIPT_%s \(EFU_SCRIPT_FIRST \+ (\d+)\)' % name, efu_h).group(1))


def efu_const(name):
    return int(re.search(r'#define EFU_%s (\d+)' % name, efu_h).group(1))


def efu_flag(name):
    return 'EVENT_FLAG_0x%04x' % int(re.search(r'#define EFU_FLAG_%s (0x[0-9a-f]+)' % name, efu_h).group(1), 16)


def npc(i, model, script, flag, x, z, direction, movement='MOVE_CODE_NONE', y=0):
    return {'id': i, 'model': model, 'movement': movement, 'type': 'ACTOR_EVENT_TYPE_NONE', 'flag': flag,
            'script': script, 'direction': direction, 'params': [0, 0, 0], 'area': {'width': 0, 'height': 0},
            'grid': {'x': x, 'z': z, 'y': y}}


# The base clerk's stock (EFU_MART_SHOP_ID's list; the clerk charges EFU_MART_PRICE_FACTOR times the price)
MART = ['ITEM_POKE_BALL', 'ITEM_GREAT_BALL', 'ITEM_POTION', 'ITEM_SUPER_POTION', 'ITEM_REVIVE', 'ITEM_FULL_HEAL',
        'ITEM_REPEL', 'ITEM_ESCAPE_ROPE']
MART_SHOP_ID = int(re.search(r'#define EFU_MART_SHOP_ID (\d+)', efu_h).group(1))


def build_matrix():
    lst = os.path.join(root, 'generated/map_matrices.txt')
    names = open(lst).read().split('\n')
    if MATRIX_CONST not in [n.split('=')[0].strip() for n in names]:
        with open(lst, 'a') as f:
            f.write(MATRIX_CONST + '\n')
    rows = ',\n'.join('        [ ' + ', '.join(f'"{m}"' for m in r) + ' ]' for r in MATRIX)
    write('res/field/matrices/efu_nacrene.json',
          '{\n    "$schema": "map_matrix.schema.json",\n    "maps": [\n' + rows + '\n    ]\n}\n')


def build_zone():
    z = json.loads(orig('res/field/zones/nacrene_city.json'))
    z['matrix'] = MATRIX_CONST
    z['fly'] = {'x': z['fly']['x'] + DX, 'y': z['fly']['y'], 'z': z['fly']['z'] + DZ}
    write('res/field/zones/nacrene_city.json', json.dumps(z, indent=4, ensure_ascii=False) + '\n')


def build_events():
    e = json.loads(orig('res/field/events/nacrene_city.json'))
    out = {'$schema': e['$schema'], 'bg_events': [], 'npcs': [], 'warps': [], 'triggers': [], 'init_scripts': []}
    for i, w in enumerate(e['warps']):
        g = dict(w['grid'])
        g['x'] += DX * 16
        g['z'] += DZ * 16
        if w['zone'] not in OPEN_ZONES:
            if i == DAYCARE_DOOR:
                assert (efu_const('DAYCARE_WARP'), efu_const('DAYCARE_WARP_X'), efu_const('DAYCARE_WARP_Z')) == \
                    (i, g['x'] // 16, g['z'] // 16)
            if g['y'] == 0:
                # A shut door: a sign on the door's tile and the tiles beside it, since the doors are drawn wider
                # than their one-tile warp
                script = efu_script('DAYCARE_DOOR') if i == DAYCARE_DOOR else SCRIPT_BOARDED
                for dx in (-1, 0, 1):
                    out['bg_events'].append({'script': script, 'condition': 0, 'direction': 4,
                                             'grid': {'x': g['x'] // 16 + dx, 'y': g['z'] // 16, 'z': 0}})
            # The interiors' doors name Nacrene's warps by number, so a closed door's warp stays in the list, moved to
            # a corner of the sea where nobody can step on it
            g['x'], g['z'] = 8, 8
        out['warps'].append(dict(w, grid=g))
    # Run as the field starts (types 3 and 4, a new load and a reload), after the zone's events are loaded for it
    out['init_scripts'] = [{'type': 3, 'script': efu_script('NACRENE_INIT')},
                           {'type': 4, 'script': efu_script('NACRENE_INIT')}]
    write('res/field/events/nacrene_city.json', json.dumps(out, indent=4, ensure_ascii=False) + '\n')
    return [i for i, w in enumerate(e['warps']) if w['zone'] in OPEN_ZONES or i == DAYCARE_DOOR]


def edit_terrain(model):
    path = f'res/field/maps/models/{model}/terrain_0.csv'
    rows = list(csv.DictReader(io.StringIO(orig(path).decode())))
    block = set(BLOCK[model])
    for r in rows:
        if (int(r['x']), int(r['z'])) in block:
            r['shape'] = '0'
            r['tile_type'] = str(BLOCKED_TILE)
    f = io.StringIO()
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    write(path, f.getvalue())


def edit_props(model):
    path = f'res/field/maps/models/{model}/model.glb'
    b = orig(path)
    jl = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    rest = b[20 + jl:]
    count = sum(1 for n in j['nodes'] if n.get('name', '').startswith('bw2_prop_'))
    for i, (x, z, rid) in enumerate(RUBBLE[model]):
        j['nodes'].append({'name': f'bw2_prop_{count + i:04d}_id_{rid:05d}',
                           'translation': [x * 16 + 8 - 256.0, 0.0, z * 16 + 8 - 256.0],
                           'rotation': [0, 0.0, 0, 1.0]})
        j['scenes'][0]['nodes'].append(len(j['nodes']) - 1)
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    out = b[:12] + struct.pack('<I', len(js)) + b'JSON' + js + rest
    out = out[:8] + struct.pack('<I', len(out)) + out[12:]
    with open(os.path.join(root, path), 'wb') as f:
        f.write(out)


def build_spawn():
    # A new game starts beside the bed upstairs in the warehouse
    z = json.loads(orig('res/field/zones/nacrene_city_8.json'))
    z['fly'] = {'x': 3, 'y': 3, 'z': 3}
    z['matrix'] = LOCKERS['nacrene_city_8']['matrix']
    write('res/field/zones/nacrene_city_8.json', json.dumps(z, indent=4, ensure_ascii=False) + '\n')


# The locker (EFU_SCRIPT_LOCKER): the grey locker of Nimbasa's stadiums (shelf06, resource 126, which both rooms' prop
# bundles hold), two tiles wide, against a wall. The warehouse gets a copy of its map model with the locker in it, since
# the Day Care Lady's warehouse shares the original; the Pokémon Center's model is edited in place, since a copy would
# have to be written whole and its model is a skinned one the packer can't write, and no other Pokémon Center can be
# reached. By zone: the model, the copy's folder and its matrix (None to edit in place), the locker's centre (tiles)
# and height, its rotation (facing south, or west against a right wall), and the tiles it stands on, which are blocked
# and talked to
LOCKER_PROP = 126
FACE_SOUTH, FACE_WEST = [0, 0.0, 0, 1.0], [0, 0.7071067811865476, 0, -0.7071067811865475]
LOCKERS = {
    # Upstairs in the player's warehouse, against the back wall right of the bed
    'nacrene_city_8': {'model': 'nacrene_city_6_m_whouse01_00_00', 'folder': 'efu_home', 'matrix': 'MAP_MATRIX_EFU_HOME',
                       'at': (11.0, 2.5), 'y': 48, 'rotation': FACE_SOUTH, 'tiles': [(10, 2), (11, 2)]},
    # In the Pokémon Center, its back to the Poké Mart counter's west side, south of where the player talks to the clerk
    # (by the right wall north of the counter, the counter's back piece hid it)
    'nacrene_city_pokemon_center': {'model': 'black_city_pokemon_center_m_pc01_00_00', 'folder': None,
                                    'matrix': None, 'at': (9.5, 18.0), 'y': 0,
                                    'rotation': FACE_WEST, 'tiles': [(9, 17), (9, 18)]},
}


def add_constant(lst, constant):
    path = os.path.join(root, lst)
    names = [l.split('=')[0].strip() for l in open(path).read().split('\n')]
    if constant not in names:
        with open(path, 'a') as f:
            f.write(constant + '\n')


def build_lockers():
    for zone, L in LOCKERS.items():
        src = f'res/field/maps/models/{L["model"]}'
        folder = f'res/field/maps/models/{L["folder"]}' if L['folder'] else src
        if L['folder']:
            os.makedirs(os.path.join(root, folder), exist_ok=True)
            constant = 'MAP_MODEL_' + L['folder'].upper()
            add_constant('generated/map_models.txt', constant)
            data = json.loads(orig(f'{src}/data.json'))
            data.update(written=True, template='MAP_MODEL_' + L['model'].upper())
            write(f'{folder}/data.json', json.dumps(data, indent=4) + '\n')
            write(f'{folder}/terrain_0_splits.csv', orig(f'{src}/terrain_0_splits.csv').decode())
        rows = list(csv.DictReader(io.StringIO(orig(f'{src}/terrain_0.csv').decode())))
        for r in rows:
            if (int(r['x']), int(r['z'])) in L['tiles']:
                r['tile_type'] = str(BLOCKED_TILE)
        f = io.StringIO()
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator='\n')
        w.writeheader()
        w.writerows(rows)
        write(f'{folder}/terrain_0.csv', f.getvalue())
        b = orig(f'{src}/model.glb')
        jl = struct.unpack('<I', b[12:16])[0]
        j = json.loads(b[20:20 + jl])
        rest = b[20 + jl:]
        count = sum(1 for n in j['nodes'] if n.get('name', '').startswith('bw2_prop_'))
        x, z = L['at']
        j['nodes'].append({'name': f'bw2_prop_{count:04d}_id_{LOCKER_PROP:05d}',
                           'translation': [x * 16 - 256.0, float(L['y']), z * 16 - 256.0], 'rotation': L['rotation']})
        j['scenes'][0]['nodes'].append(len(j['nodes']) - 1)
        js = json.dumps(j, separators=(',', ':')).encode()
        js += b' ' * (-len(js) % 4)
        out = b[:12] + struct.pack('<I', len(js)) + b'JSON' + js + rest
        out = out[:8] + struct.pack('<I', len(out)) + out[12:]
        with open(os.path.join(root, folder, 'model.glb'), 'wb') as f:
            f.write(out)
        if not L['matrix']:
            continue
        add_constant('generated/map_matrices.txt', L['matrix'])
        write(f'res/field/matrices/{L["matrix"][len("MAP_MATRIX_"):].lower()}.json',
              '{\n    "$schema": "map_matrix.schema.json",\n    "maps": [\n        [ "' + constant + '" ]\n    ]\n}\n')


def locker_events(zone):
    # A background event on each of the locker's tiles, at the floor's height and the heights beside it (a background
    # event's height must be within 2 of the player's)
    L = LOCKERS[zone]
    return [{'script': efu_script('LOCKER'), 'condition': 0, 'direction': 4, 'grid': {'x': x, 'y': z, 'z': L['y'] + h}}
            for x, z in L['tiles'] for h in (-4, 0, 4)]


def build_interiors():
    # The player's warehouse: nobody else, and the bed by the left wall
    e = json.loads(orig('res/field/events/nacrene_city_8.json'))
    e['npcs'] = []
    e['init_scripts'] = []
    # The bed's tiles; a background event's height (z, world units) must be within 2 of the player's
    e['bg_events'] = [{'script': 11003, 'condition': 0, 'direction': 4, 'grid': {'x': 2, 'y': yy, 'z': h}} for yy in (2, 3) for h in (44, 48, 52)]
    e['bg_events'] += locker_events('nacrene_city_8')
    write('res/field/events/nacrene_city_8.json', json.dumps(e, indent=4, ensure_ascii=False) + '\n')
    # The Day Care Lady's warehouse, east of the Pokémon Center, the same as the player's: she is downstairs once she
    # has joined (her hide flag set from that by Script_DayCareInit), and its door is shut until then (build_events). Its way out upstairs leads out of its ground floor door instead, since the upper one stays shut
    e = json.loads(orig('res/field/events/nacrene_city_7.json'))
    e['npcs'] = [npc(0, 'OBJ_CODE_29', 2201, efu_flag('BASE_DAYCARE_HIDDEN'), 3, 8, 'DIR_RIGHT', 'MOVE_CODE_FACE_RIGHT')]
    e['init_scripts'] = [{'type': 2, 'script': efu_script('DAYCARE_INIT')}]
    e['bg_events'] = []
    e['triggers'] = []
    e['warps'] = [dict(w, warp=DAYCARE_DOOR) if w['zone'] == 'ZONE_NACRENE_CITY' else w for w in e['warps']]
    write('res/field/events/nacrene_city_7.json', json.dumps(e, indent=4, ensure_ascii=False) + '\n')
    # The Pokémon Center: the PC works, Nurse Joy is at the counter once she has joined, and the clerk sits in the
    # waiting area until the player has met them, then runs the Poké Mart counter (their hide flags set by
    # Script_PokecenInit)
    e = json.loads(orig('res/field/events/nacrene_city_pokemon_center.json'))
    e['npcs'] = [
        npc(1, 'OBJ_CODE_78', efu_script('NURSE'), efu_flag('BASE_JOY_HIDDEN'), 7, 10, 'DIR_DOWN', 'MOVE_CODE_FACE_DOWN'),
        npc(0, 'OBJ_CODE_77', efu_script('CLERK'), efu_flag('BASE_CLERK_HIDDEN'), 11, 16, 'DIR_LEFT', 'MOVE_CODE_FACE_LEFT'),
        npc(8, 'OBJ_CODE_77', efu_script('CLERK_INTRO'), efu_flag('CLERK_MET'), 1, 13, 'DIR_RIGHT', 'MOVE_CODE_FACE_RIGHT'),
    ]
    e['init_scripts'] = [{'type': 2, 'script': efu_script('POKECEN_INIT')}]
    e['bg_events'] = [b for b in e['bg_events'] if b['script'] == 2108]
    e['bg_events'] += locker_events('nacrene_city_pokemon_center')
    write('res/field/events/nacrene_city_pokemon_center.json', json.dumps(e, indent=4, ensure_ascii=False) + '\n')
    # The east gate, where raids start: nobody there. The hall runs from Nacrene's door (x 1) to Route 3's (x 15) over
    # rows 4 to 6. Stepping onto column 14, by Route 3's door, while home asks to leave (and saves); stepping onto
    # column 2, by Nacrene's, while out comes home (and saves). EFU_WORK_RAID (include/efu.h) picks which is live
    e = json.loads(orig('res/field/events/nacrene_gate.json'))
    # Its guide, behind the counter once the player has met them out in the zone (their hide flag set from that by
    # Script_GateInit), who will take the player farther out one day
    e['npcs'] = [npc(0, 'OBJ_CODE_76', efu_script('GATE_GUIDE'), efu_flag('BASE_GUIDE_HIDDEN'), 13, 2, 'DIR_DOWN',
                     'MOVE_CODE_FACE_DOWN')]
    e['init_scripts'] = [{'type': 2, 'script': efu_script('GATE_INIT')}]
    e['triggers'] = [
        {'script': 11004, 'var': 'EVENT_WORK_0x41ac', 'value': 0, 'type': 0,
         'grid': {'x': 14, 'z': 4, 'width': 1, 'height': 3, 'y': 0}, 'unk14': 0},
        {'script': 11005, 'var': 'EVENT_WORK_0x41ac', 'value': 1, 'type': 0,
         'grid': {'x': 2, 'z': 4, 'width': 1, 'height': 3, 'y': 0}, 'unk14': 0},
    ]
    write('res/field/events/nacrene_gate.json', json.dumps(e, indent=4, ensure_ascii=False) + '\n')


def build_mart():
    # Only that list's text changes, so the rest of the file keeps its layout
    text = orig('res/field/shops/shops.json').decode()
    at = text.index('[', text.index('"marts"') + len('"marts"')) + 1
    for _ in range(MART_SHOP_ID + 1):
        start = text.index('[', at)
        end = text.index(']', start) + 1
        at = end
    items = ',\n'.join(' ' * 12 + f'"{i}"' for i in MART)
    write('res/field/shops/shops.json', text[:start] + '[\n' + items + '\n        ]' + text[end:])


def build_gate_board():
    # The electric noticeboard in the east gate counts the explorations (EFU_WORK_RAID_COUNT) in the date's place, and
    # shows nothing else (GimmickGate_SetupDefaultMessages): its date message (the first) says so. No other gate's
    # board can be seen
    write('res/field/gate_boards/gates.json', orig('res/field/gate_boards/gates.json').decode())
    path = 'res/text/system/gate_news_board.txt'
    lines = orig(path).decode().split('\n')
    assert lines[0].startswith('GateNewsBoard_Text_20 = ')
    lines[0] = 'GateNewsBoard_Text_20 = Explorations so far: {0201:0}'
    write(path, '\n'.join(lines))


if __name__ == '__main__':
    build_gate_board()
    build_mart()
    build_lockers()
    build_spawn()
    build_interiors()
    build_matrix()
    build_zone()
    print('kept warps', build_events())
    for m in BLOCK:
        edit_terrain(m)
        edit_props(m)
    import build_coast
    build_coast.build_coast()
