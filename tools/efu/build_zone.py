"""Escape from Unova: the first exploration zone's map, which ZONE_ROUTE_3 uses instead of the overworld's.

Idempotent, like build_base.py. It writes
- res/field/matrices/efu_zone_1.json: Route 3's chunks with Route 20's south of its east end, in Striaton's place,
  where Route 3's road south meets Route 20's north path, all walled in by forest. No chunk of a town is in
  it, so nothing leads out of the zone but the gate home and the doors of its caves and its target;
- copies of Route 20's chunks (res/field/maps/models/efu_zone_1_*), 32 units lower so that their ground meets Route 3's,
  with each terrain plane moved to the height table's entry for the lowered plane;
- the textures of Route 20 that Route 3's texture sets lack, imported from Route 19's sets season by season;
- res/field/zones/route_3.json, for the matrix.
build_raid.py moves the events of both routes into the matrix's coordinates (ZONE_CHUNKS).
"""
import csv, json, os, re, shutil

import build_coast as bc

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
MODELS = os.path.join(root, 'res/field/maps/models')
TEXTURES = os.path.join(root, 'res/field/maps/textures')
TREE = 'MAP_MODEL_OVERWORLD_2_MAP_OUTTREE'
MATRIX_CONST = 'MAP_MATRIX_EFU_ZONE_1'
MATRIX_FILE = 'res/field/matrices/efu_zone_1.json'

# The zone's chunks, by overworld chunk (column, row of MAP_MATRIX_OVERWORLD): where each goes in the matrix. Route 3
# keeps its place, so the matrix is the overworld's size, forest wherever no chunk is, and a save made on Route 3 by
# an older build still stands somewhere real; Route 20 takes Striaton's place, south of Route 3's east end
ZONE_CHUNKS = {
    (21, 17): (21, 17), (22, 17): (22, 17), (23, 17): (23, 17),
    (21, 18): (21, 18), (22, 18): (22, 18),
    (4, 20): (23, 18), (5, 20): (24, 18),
    (4, 21): (23, 19), (5, 21): (24, 19),
}
MATRIX_SIZE = (29, 27)
# The chunks copied lower, and by how much (world units): Route 20's ground at the seam is 32 above Route 3's
LOWERED = {(4, 20): -32, (5, 20): -32, (4, 21): -32, (5, 21): -32}
# The zone's texture sets by season (Striaton's area, which Route 3's zone uses) and Route 19's, which Route 20 uses
ZONE_SETS = ['MAP_TEXTURE_SET_SHARED_DANSA01A_6', 'MAP_TEXTURE_SET_SHARED_DANSA01A_7',
             'MAP_TEXTURE_SET_SHARED_DANSA01A_8', 'MAP_TEXTURE_SET_SHARED_DANSA01A_9']
ROUTE_20_SETS = ['MAP_TEXTURE_SET_SHARED_DANSA01A_183', 'MAP_TEXTURE_SET_SHARED_DANSA01A_184',
                 'MAP_TEXTURE_SET_SHARED_DANSA01A_185', 'MAP_TEXTURE_SET_SHARED_DANSA01A_186']
# The props of Striaton's bundle (FIELD_PROPS_EXTERIOR_SHARED_PC_01_2) a copied chunk may keep, by resource ID
PROP_BUNDLE = 'shared_pc_01_2'


def folder(chunk):
    return 'overworld_2_map%02d_%02d' % chunk


def copy_folder(chunk):
    return 'efu_zone_1_%02d_%02d' % chunk


def constant_of_original(chunk):
    return 'MAP_MODEL_OVERWORLD_2_MAP%02d_%02d' % chunk


def constant(chunk):
    if chunk in LOWERED:
        return 'MAP_MODEL_' + copy_folder(chunk).upper()
    return 'MAP_MODEL_OVERWORLD_2_MAP%02d_%02d' % chunk


def tables():
    """The terrain's plane normals (x, y, z, fx16) and heights (fx32), from field_map_chunk_height.c."""
    s = open(os.path.join(root, 'src/ov036/field_map_chunk_height.c')).read()

    def table(name):
        i = s.index(name + '[] = {')
        return [int(v, 0) for v in re.findall(r'-?0x[0-9a-fA-F]+|-?\d+', s[i + len(name) + 6:s.index('};', i)])]
    return table('MAP_HEIGHT_SLOPE_TABLE'), table('MAP_HEIGHT_OFFSET_TABLE')


SLOPES, OFFSETS = tables()


def lowered_offset(slope, offset, dy):
    # A plane's height is -(offset + n.x * x + n.z * z) / n.y, so moving it by dy takes dy * n.y off its offset; the
    # table's nearest entry stands in (within a hundredth of a unit for the ground, about a unit on a few cliff faces)
    target = OFFSETS[offset] - dy * SLOPES[slope * 3 + 1]
    return min(range(len(OFFSETS)), key=lambda k: abs(OFFSETS[k] - target))


def bundle_ids():
    ids = set()
    base = os.path.join(root, 'res/field/props/exterior/models', PROP_BUNDLE)
    for d in os.listdir(base):
        ids.add(json.load(open(os.path.join(base, d, 'data.json')))['res_id'])
    return ids


def build_lowered(chunk, dy, props):
    src = os.path.join(MODELS, folder(chunk))
    dst = os.path.join(MODELS, copy_folder(chunk))
    os.makedirs(dst, exist_ok=True)
    doc, binary = bc.read_glb(os.path.join(src, 'model.glb'))
    mesh = [n for n in doc['nodes'] if 'mesh' in n][0]
    w = bc.Writer(mesh['name'])
    w.edge_low = {}
    for prim in doc['meshes'][mesh['mesh']]['primitives']:
        att = prim['attributes']
        positions = [(x, y + dy, z) for x, y, z in bc.accessor(doc, binary, att['POSITION'])]
        note_edges(w.edge_low, positions)
        uvs = bc.accessor(doc, binary, att['TEXCOORD_0'])
        colors = bc.accessor(doc, binary, att['COLOR_0'])
        normals = bc.accessor(doc, binary, att['NORMAL']) if 'NORMAL' in att else None
        idx = [i[0] for i in bc.accessor(doc, binary, prim['indices'])]
        old = doc['materials'][prim['material']]
        binding = old.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        uri = doc['images'][doc['textures'][binding['index']]['source']]['uri'] if binding else 'none.png'
        names = [m['name'] for m in w.doc['materials']]
        material = names.index(old['name']) if old['name'] in names else w.material(old, uri)
        w.primitive(material, positions, uvs, colors, normals, [tuple(idx[k:k + 3]) for k in range(0, len(idx), 3)])
    # The props Striaton's bundle has too, lowered with the ground
    for node in doc['nodes']:
        m = re.match(r'bw2_prop_\d+_id_(\d+)', node.get('name', ''))
        if m and int(m.group(1)) in props:
            n = {k: node[k] for k in ('name', 'translation', 'rotation', 'scale') if k in node}
            n['translation'] = [n['translation'][0], n['translation'][1] + dy, n['translation'][2]]
            w.doc['nodes'].append(n)
            w.doc['scenes'][0]['nodes'].append(len(w.doc['nodes']) - 1)
    add_edge_walls(w, chunk, dy)
    w.save(os.path.join(dst, 'model.glb'))
    with open(os.path.join(dst, 'data.json'), 'w') as f:
        f.write(json.dumps({'$schema': '../map_model.schema.json', 'texture_set': ZONE_SETS[0], 'written': True,
                            'template': constant_of_original(chunk)}, indent=4) + '\n')
    rows = list(csv.DictReader(open(os.path.join(src, 'terrain_0.csv'))))
    for r in rows:
        if r['shape'] == '0':
            r['offset'] = str(lowered_offset(int(r['slope']), int(r['offset']), dy))
    bc.write_csv(os.path.join(dst, 'terrain_0.csv'), rows)
    splits = list(csv.DictReader(open(os.path.join(src, 'terrain_0_splits.csv'))))
    for r in splits:
        r['offset0'] = str(lowered_offset(int(r['slope0']), int(r['offset0']), dy))
        r['offset1'] = str(lowered_offset(int(r['slope1']), int(r['offset1']), dy))
    with open(os.path.join(dst, 'terrain_0_splits.csv'), 'w', newline='\n') as f:
        out = csv.DictWriter(f, fieldnames=['index', 'unused', 'slope0', 'slope1', 'offset0', 'offset1'],
                             lineterminator='\n')
        out.writeheader()
        out.writerows(splits)
    register('generated/map_models.txt', constant(chunk))


# The edges of a chunk: the neighbor's offset in chunks, and for a vertex, its distance from the edge and its place
# along it
EDGES = {
    'N': ((0, -1), lambda x, z: z + 256, lambda x, z: x),
    'S': ((0, 1), lambda x, z: 256 - z, lambda x, z: x),
    'W': ((-1, 0), lambda x, z: x + 256, lambda x, z: z),
    'E': ((1, 0), lambda x, z: 256 - x, lambda x, z: z),
}
WALL_MATERIAL = 'gake01a'


def note_edges(low, positions):
    for x, y, z in positions:
        for edge, (_, across, along) in EDGES.items():
            if abs(across(x, z)) < 0.6:
                tile = min(31, max(0, int((along(x, z) + 256) // 16)))
                low[edge, tile] = min(low.get((edge, tile), 0.0), y)


def add_edge_walls(w, chunk, dy):
    """Cliff faces down from the zone's ground (0) along the edges a lowered chunk shares with a chunk that isn't
    lowered with it: the river beds and cliffs that ran on into the next chunk of the overworld would leave a hole to
    the sky there."""
    lowered = {pos for c, pos in ZONE_CHUNKS.items() if c in LOWERED}
    x0, z0 = ZONE_CHUNKS[chunk]
    names = [m['name'] for m in w.doc['materials']]
    material = None
    for edge, ((ox, oz), _, _) in EDGES.items():
        if (x0 + ox, z0 + oz) in lowered:
            continue
        for tile in range(32):
            bottom = w.edge_low.get((edge, tile), 0.0)
            if bottom > -1:
                continue
            if material is None:
                material = (names.index(WALL_MATERIAL) if WALL_MATERIAL in names else w.material(
                    {'name': WALL_MATERIAL, 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                                                      'metallicFactor': 0},
                     'extensions': {'KHR_materials_unlit': {}}},
                    '../../textures/%s/%s.png' % (ZONE_SETS[0][len('MAP_TEXTURE_SET_'):].lower(), WALL_MATERIAL)))
            a, b = tile * 16 - 256, tile * 16 - 240
            if edge == 'N':
                ends = [(a, -256), (b, -256)]
            elif edge == 'S':
                ends = [(a, 256), (b, 256)]
            elif edge == 'W':
                ends = [(-256, a), (-256, b)]
            else:
                ends = [(256, a), (256, b)]
            (ax, az), (bx, bz) = ends
            verts = [(ax, 0.0, az), (bx, 0.0, bz), (bx, bottom, bz), (ax, bottom, az)]
            uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, -bottom / 16), (0.0, -bottom / 16)]
            # Both faces, so it shows from whichever side the camera is on
            # Lit like the ground, so they darken at night with it
            w.primitive(material, verts, uvs, [(254, 254, 254)] * 4, [(0.0, 1.0, 0.0)] * 4,
                        [(0, 1, 2), (0, 2, 3), (0, 2, 1), (0, 3, 2)])


def register(path, name):
    lst = os.path.join(root, path)
    if name not in [l.split('=')[0].strip() for l in open(lst).read().split('\n')]:
        with open(lst, 'a') as f:
            f.write(name + '\n')


def missing_textures():
    """The textures the lowered chunks use that the zone's sets lack."""
    have = {f[:-4] for f in os.listdir(os.path.join(TEXTURES, ZONE_SETS[0][len('MAP_TEXTURE_SET_'):].lower()))}
    need = set()
    for chunk in LOWERED:
        doc, _ = bc.read_glb(os.path.join(MODELS, copy_folder(chunk), 'model.glb'))
        need |= {os.path.basename(i['uri'])[:-4] for i in doc['images']}
    return sorted(need - have)


def build_imports():
    textures = missing_textures()
    for zone_set, route_set in zip(ZONE_SETS, ROUTE_20_SETS):
        path = os.path.join(TEXTURES, zone_set[len('MAP_TEXTURE_SET_'):].lower(), 'imports.json')
        with open(path, 'w') as f:
            f.write(json.dumps({'$schema': '../texture_imports.schema.json',
                                'textures': [{'texture': t, 'from': route_set} for t in textures]}, indent=4) + '\n')


def build_matrix():
    register('generated/map_matrices.txt', MATRIX_CONST)
    at = {pos: chunk for chunk, pos in ZONE_CHUNKS.items()}
    width, height = MATRIX_SIZE
    rows = ',\n'.join('        [ ' + ', '.join('"%s"' % (constant(at[x, z]) if (x, z) in at else TREE)
                                               for x in range(width)) + ' ]' for z in range(height))
    with open(os.path.join(root, MATRIX_FILE), 'w') as f:
        f.write('{\n    "$schema": "map_matrix.schema.json",\n    "maps": [\n' + rows + '\n    ]\n}\n')


def build_zone():
    path = os.path.join(root, 'res/field/zones/route_3.json')
    z = json.load(open(path))
    z['matrix'] = MATRIX_CONST
    with open(path, 'w') as f:
        f.write(json.dumps(z, indent=4, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    props = bundle_ids()
    for chunk, dy in LOWERED.items():
        build_lowered(chunk, dy, props)
    build_imports()
    build_matrix()
    build_zone()
    print('imported', missing_textures())
