"""Escape from Unova: the first exploration zone's maps, two matrices of the overworld's chunks.

Idempotent, like build_base.py. The zone runs Route 3 → Route 2 → Pinwheel Forest → Route 19 → Route 20 (docs/efu.md):
- MAP_MATRIX_EFU_ZONE_1 (res/field/matrices/efu_zone_1.json): Route 3, the west chunk of Striaton (its garden) and
  Route 2, each where it is in the overworld, so their ground meets as it always did and their events keep their
  coordinates. Striaton's other chunks are forest, and a path is cut through the trees between the garden and Route 2
  (CUTS), the way on from Route 3's road south;
- MAP_MATRIX_EFU_ZONE_2 (efu_zone_2.json): Route 19 moved one chunk east and one north, into Floccesy Town's place, and
  raised 16 units, so its path east meets Route 20's path west; Route 20 and Floccesy Ranch where they are;
- copies of the chunks that change (res/field/maps/models/efu_zone_*): cut, raised or with tiles blocked at a seam;
- each matrix's zones, so that crossing from Route 3 into Route 2 (or Route 19 into Route 20) is a zone change that
  runs the zone's init script, and the zones' headers (res/field/zones/*.json), for their matrix.
Everything else in a matrix is forest (MAP_OUTTREE), all of it blocked. build_raid.py moves the events of the moved
chunks into the matrix's coordinates (moved()).
"""
import csv, json, os, re

import build_coast as bc

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
MODELS = os.path.join(root, 'res/field/maps/models')
TEXTURES = os.path.join(root, 'res/field/maps/textures')
TREE = 'MAP_MODEL_OVERWORLD_2_MAP_OUTTREE'
# The overworld's size, so that every matrix keeps its chunks' overworld coordinates
MATRIX_SIZE = (29, 27)

# Each matrix: its file, the zone of its forest, and its chunks, by overworld chunk (column, row of
# MAP_MATRIX_OVERWORLD): where each goes in the matrix and its zone there
MATRICES = {
    'MAP_MATRIX_EFU_ZONE_1': {
        'file': 'res/field/matrices/efu_zone_1.json', 'name': 'efu_zone_1', 'forest_zone': 'ZONE_ROUTE_3',
        'texture_set': 'MAP_TEXTURE_SET_SHARED_DANSA01A_6',
        # Its area's sets by season (Striaton's)
        'seasons': ['MAP_TEXTURE_SET_SHARED_DANSA01A_%d' % n for n in (6, 7, 8, 9)],
        'zones': ['ZONE_ROUTE_3', 'ZONE_ROUTE_2'],
        'chunks': {
            (21, 17): ((21, 17), 'ZONE_ROUTE_3'), (22, 17): ((22, 17), 'ZONE_ROUTE_3'),
            (23, 17): ((23, 17), 'ZONE_ROUTE_3'), (21, 18): ((21, 18), 'ZONE_ROUTE_3'),
            (22, 18): ((22, 18), 'ZONE_ROUTE_3'),
            # Striaton's garden, now the end of Route 3's road south
            (23, 18): ((23, 18), 'ZONE_ROUTE_3'),
            (23, 19): ((23, 19), 'ZONE_ROUTE_2'), (24, 19): ((24, 19), 'ZONE_ROUTE_2'),
            (23, 20): ((23, 20), 'ZONE_ROUTE_2'),
        },
    },
    'MAP_MATRIX_EFU_ZONE_2': {
        'file': 'res/field/matrices/efu_zone_2.json', 'name': 'efu_zone_2', 'forest_zone': 'ZONE_ROUTE_20',
        'texture_set': 'MAP_TEXTURE_SET_SHARED_DANSA01A_183',
        # Route 19's area's, which lack the textures of Route 19's west chunk, drawn with Aspertia's
        'seasons': ['MAP_TEXTURE_SET_SHARED_DANSA01A_%d' % n for n in (183, 184, 185, 186)],
        'zones': ['ZONE_ROUTE_19', 'ZONE_ROUTE_20', 'ZONE_FLOCCESY_RANCH'],
        'chunks': {
            (1, 21): ((2, 20), 'ZONE_ROUTE_19'), (2, 21): ((3, 20), 'ZONE_ROUTE_19'),
            (4, 19): ((4, 19), 'ZONE_FLOCCESY_RANCH'),
            (4, 20): ((4, 20), 'ZONE_ROUTE_20'), (5, 20): ((5, 20), 'ZONE_ROUTE_20'),
            (4, 21): ((4, 21), 'ZONE_ROUTE_20'), (5, 21): ((5, 21), 'ZONE_ROUTE_20'),
        },
    },
}
# Every chunk's place, by overworld chunk
ZONE_CHUNKS = {c: pos for m in MATRICES.values() for c, (pos, zone) in m['chunks'].items()}
# The chunks copied higher, and by how much (world units): Route 19's path east is at 16, Route 20's west at 32
RAISED = {(1, 21): 16, (2, 21): 16}
# The paths cut through the trees: in each chunk, a rectangle of tiles (x0, z0, x1, z1, the ends exclusive) where
# everything above the ground goes, grass is laid and the tiles are walked on. Tree rows stand every 32 units from
# x 16, so a cut from tile 17 to 20 keeps the rows at its sides as its walls
CUTS = {(23, 18): [(17, 28, 21, 32)], (23, 19): [(17, 0, 21, 10)]}
# Tiles blocked in a copy: Route 19's high ground at its east edge, which met Floccesy Town's and would let the player
# step down onto Route 20's lower ground
BLOCKED = {(2, 21): [(31, 0), (31, 1)]}
GROUND_MATERIAL = 'grass01ax'
WALL_MATERIAL = 'gake01a'
BLOCKED_TILE = 0x10000


def folder(chunk):
    return 'overworld_2_map%02d_%02d' % chunk


def matrix_of(chunk):
    return next(m for m in MATRICES.values() if chunk in m['chunks'])


def copied(chunk):
    return chunk in RAISED or chunk in CUTS or chunk in BLOCKED


def copy_folder(chunk):
    return '%s_%02d_%02d' % (matrix_of(chunk)['name'], *chunk)


def constant_of_original(chunk):
    return 'MAP_MODEL_OVERWORLD_2_MAP%02d_%02d' % chunk


def constant(chunk):
    if copied(chunk):
        return 'MAP_MODEL_' + copy_folder(chunk).upper()
    return constant_of_original(chunk)


def tables():
    """The terrain's plane normals (x, y, z, fx16) and heights (fx32), from field_map_chunk_height.c."""
    s = open(os.path.join(root, 'src/ov036/field_map_chunk_height.c')).read()

    def table(name):
        i = s.index(name + '[] = {')
        return [int(v, 0) for v in re.findall(r'-?0x[0-9a-fA-F]+|-?\d+', s[i + len(name) + 6:s.index('};', i)])]
    return table('MAP_HEIGHT_SLOPE_TABLE'), table('MAP_HEIGHT_OFFSET_TABLE')


SLOPES, OFFSETS = tables()


def moved_offset(slope, offset, dy):
    # A plane's height is -(offset + n.x * x + n.z * z) / n.y, so moving it by dy takes dy * n.y off its offset; the
    # table's nearest entry stands in (within a hundredth of a unit for the ground, about a unit on a few cliff faces)
    target = OFFSETS[offset] - dy * SLOPES[slope * 3 + 1]
    return min(range(len(OFFSETS)), key=lambda k: abs(OFFSETS[k] - target))


def clip_half(poly, axis, value, keep_below):
    """Sutherland-Hodgman: the part of a polygon (vertices as tuples, position first) on one side of a plane
    axis = value."""
    out = []
    for i, a in enumerate(poly):
        b = poly[(i + 1) % len(poly)]
        a_in = a[axis] <= value if keep_below else a[axis] >= value
        b_in = b[axis] <= value if keep_below else b[axis] >= value
        if a_in:
            out.append(a)
        if a_in != b_in:
            t = (value - a[axis]) / (b[axis] - a[axis])
            out.append(tuple(x + (y - x) * t for x, y in zip(a, b)))
    return out if len(out) >= 3 else []


def outside(poly, x0, z0, x1, z1):
    """The parts of a polygon outside the column x0 < x < x1, z0 < z < z1 (one lying on a side of it is kept whole)."""
    xs = [v[0] for v in poly]
    zs = [v[2] for v in poly]
    if max(xs) <= x0 or min(xs) >= x1 or max(zs) <= z0 or min(zs) >= z1:
        return [poly]
    parts = [clip_half(poly, 0, x0, True), clip_half(poly, 0, x1, False)]
    middle = clip_half(clip_half(poly, 0, x0, False), 0, x1, True)
    if middle:
        parts += [clip_half(middle, 2, z0, True), clip_half(middle, 2, z1, False)]
    return [p for p in parts if p and area(p) > 1e-3]


def area(p):
    total = [0.0, 0.0, 0.0]
    for i in range(1, len(p) - 1):
        a = [p[i][k] - p[0][k] for k in range(3)]
        b = [p[i + 1][k] - p[0][k] for k in range(3)]
        c = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
        total = [t + v for t, v in zip(total, c)]
    return sum(t * t for t in total) ** 0.5 / 2


def build_copy(chunk):
    """A copy of an overworld chunk, raised (RAISED), with paths cut through its trees (CUTS) and tiles blocked
    (BLOCKED)."""
    src = os.path.join(MODELS, folder(chunk))
    dst = os.path.join(MODELS, copy_folder(chunk))
    os.makedirs(dst, exist_ok=True)
    dy = RAISED.get(chunk, 0)
    cuts = [(x0 * bc.TILE - 256, z0 * bc.TILE - 256, x1 * bc.TILE - 256, z1 * bc.TILE - 256)
            for x0, z0, x1, z1 in CUTS.get(chunk, [])]
    doc, binary = bc.read_glb(os.path.join(src, 'model.glb'))
    mesh = [n for n in doc['nodes'] if 'mesh' in n][0]
    w = bc.Writer(mesh['name'])
    w.edge_low = {}
    ground = None
    for prim in doc['meshes'][mesh['mesh']]['primitives']:
        att = prim['attributes']
        positions = bc.accessor(doc, binary, att['POSITION'])
        uvs = bc.accessor(doc, binary, att['TEXCOORD_0'])
        colors = bc.accessor(doc, binary, att['COLOR_0'])
        normals = bc.accessor(doc, binary, att['NORMAL']) if 'NORMAL' in att else [(0.0, 1.0, 0.0)] * len(positions)
        idx = [i[0] for i in bc.accessor(doc, binary, prim['indices'])]
        old = doc['materials'][prim['material']]
        binding = old.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        uri = doc['images'][doc['textures'][binding['index']]['source']]['uri'] if binding else 'none.png'
        names = [m['name'] for m in w.doc['materials']]
        material = names.index(old['name']) if old['name'] in names else w.material(old, uri)
        if old['name'] == GROUND_MATERIAL:
            ground = material
        # Vertices as position, uv, color and normal in one tuple, so clipping interpolates them all
        verts = [tuple(float(c) for c in positions[i]) + tuple(float(c) for c in uvs[i])
                 + tuple(float(c) for c in colors[i][:3]) + tuple(float(c) for c in normals[i])
                 for i in range(len(positions))]
        polys = [[verts[i] for i in idx[k:k + 3]] for k in range(0, len(idx), 3)]
        for x0, z0, x1, z1 in cuts:
            polys = [part for p in polys for part in outside(p, x0, z0, x1, z1)]
        tris = [(p[0], p[j], p[j + 1]) for p in polys for j in range(1, len(p) - 1)]
        if not tris:
            continue
        vs = [(v[0], v[1] + dy, v[2]) + v[3:] for t in tris for v in t]
        bc_note_edges(w.edge_low, [v[:3] for v in vs])
        w.primitive(material, [v[0:3] for v in vs], [v[3:5] for v in vs],
                    [tuple(min(255, max(0, round(c))) for c in v[5:8]) for v in vs], [v[8:11] for v in vs],
                    [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])
    # Grass on the cut paths, lit like the ground around
    for x0, z0, x1, z1 in cuts:
        if ground is None:
            ground = w.material({'name': GROUND_MATERIAL, 'pbrMetallicRoughness': {
                'baseColorTexture': {'index': 0}, 'metallicFactor': 0}, 'extensions': {'KHR_materials_unlit': {}}},
                texture_uri(chunk, GROUND_MATERIAL))
        corners = [(x0, dy, z0), (x1, dy, z0), (x1, dy, z1), (x0, dy, z1)]
        w.primitive(ground, corners, [(x / 32, z / 32) for x, y, z in corners], [(254, 254, 254)] * 4,
                    [(0.0, 1.0, 0.0)] * 4, [(0, 2, 1), (0, 3, 2)])
    # The props, raised with the ground, but none where a path is cut
    for node in doc['nodes']:
        if not node.get('name', '').startswith('bw2_prop_'):
            continue
        n = {k: node[k] for k in ('name', 'translation', 'rotation', 'scale') if k in node}
        x, y, z = n['translation']
        if any(x0 - 8 < x < x1 + 8 and z0 - 8 < z < z1 + 8 for x0, z0, x1, z1 in cuts):
            continue
        n['translation'] = [x, y + dy, z]
        w.doc['nodes'].append(n)
        w.doc['scenes'][0]['nodes'].append(len(w.doc['nodes']) - 1)
    if dy:
        add_edge_walls(w, chunk, dy)
    w.save(os.path.join(dst, 'model.glb'))
    with open(os.path.join(dst, 'data.json'), 'w') as f:
        f.write(json.dumps({'$schema': '../map_model.schema.json', 'texture_set': matrix_of(chunk)['texture_set'],
                            'written': True, 'template': constant_of_original(chunk)}, indent=4) + '\n')
    rows = list(csv.DictReader(open(os.path.join(src, 'terrain_0.csv'))))
    at = {(int(r['x']), int(r['z'])): r for r in rows}
    for x0, z0, x1, z1 in CUTS.get(chunk, []):
        # Each tile of the path as the walkable ground tile nearest it
        walkable = [r for r in rows if not int(r['tile_type']) & BLOCKED_TILE and r['shape'] == '0']
        for x in range(x0, x1):
            for z in range(z0, z1):
                near = min(walkable, key=lambda r: abs(int(r['x']) - x) + abs(int(r['z']) - z))
                at[x, z].update({k: near[k] for k in ('shape', 'slope', 'offset', 'tile_type')})
    for x, z in BLOCKED.get(chunk, []):
        at[x, z]['tile_type'] = str(int(at[x, z]['tile_type']) | BLOCKED_TILE)
    if dy:
        for r in rows:
            if r['shape'] == '0':
                r['offset'] = str(moved_offset(int(r['slope']), int(r['offset']), dy))
    bc.write_csv(os.path.join(dst, 'terrain_0.csv'), rows)
    splits = list(csv.DictReader(open(os.path.join(src, 'terrain_0_splits.csv'))))
    if dy:
        for r in splits:
            r['offset0'] = str(moved_offset(int(r['slope0']), int(r['offset0']), dy))
            r['offset1'] = str(moved_offset(int(r['slope1']), int(r['offset1']), dy))
    with open(os.path.join(dst, 'terrain_0_splits.csv'), 'w', newline='\n') as f:
        out = csv.DictWriter(f, fieldnames=['index', 'unused', 'slope0', 'slope1', 'offset0', 'offset1'],
                             lineterminator='\n')
        out.writeheader()
        out.writerows(splits)
    register('generated/map_models.txt', constant(chunk))


def texture_uri(chunk, name):
    s = matrix_of(chunk)['texture_set'][len('MAP_TEXTURE_SET_'):].lower()
    return f'../../textures/{s}/{name}.png'


# The edges of a chunk: the neighbor's offset in chunks, and for a vertex, its distance from the edge and its place
# along it
EDGES = {
    'N': ((0, -1), lambda x, z: z + 256, lambda x, z: x),
    'S': ((0, 1), lambda x, z: 256 - z, lambda x, z: x),
    'W': ((-1, 0), lambda x, z: x + 256, lambda x, z: z),
    'E': ((1, 0), lambda x, z: 256 - x, lambda x, z: z),
}


def bc_note_edges(low, positions):
    for x, y, z in positions:
        for edge, (_, across, along) in EDGES.items():
            if abs(across(x, z)) < 0.6:
                tile = min(31, max(0, int((along(x, z) + 256) // 16)))
                low[edge, tile] = min(low.get((edge, tile), 1e9), y)


def add_edge_walls(w, chunk, dy):
    """Cliff faces down from a raised chunk's edges, where it meets a chunk that isn't raised with it, to below the
    ground there: the ground that ran on into the next chunk of the overworld would otherwise leave a gap under its
    edge."""
    raised = {ZONE_CHUNKS[c] for c in RAISED}
    x0, z0 = ZONE_CHUNKS[chunk]
    names = [m['name'] for m in w.doc['materials']]
    material = None
    for edge, ((ox, oz), _, _) in EDGES.items():
        if (x0 + ox, z0 + oz) in raised:
            continue
        for tile in range(32):
            top = w.edge_low.get((edge, tile))
            if top is None:
                continue
            bottom = -16.0
            if material is None:
                material = (names.index(WALL_MATERIAL) if WALL_MATERIAL in names else w.material(
                    {'name': WALL_MATERIAL, 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                                                      'metallicFactor': 0},
                     'extensions': {'KHR_materials_unlit': {}}}, texture_uri(chunk, WALL_MATERIAL)))
            a, b = tile * 16 - 256, tile * 16 - 240
            ends = {'N': [(a, -256), (b, -256)], 'S': [(a, 256), (b, 256)], 'W': [(-256, a), (-256, b)],
                    'E': [(256, a), (256, b)]}[edge]
            (ax, az), (bx, bz) = ends
            verts = [(ax, top, az), (bx, top, bz), (bx, bottom, bz), (ax, bottom, az)]
            uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, (top - bottom) / 16), (0.0, (top - bottom) / 16)]
            # Both faces, so it shows from whichever side the camera is on, lit like the ground, so they darken at
            # night with it
            w.primitive(material, verts, uvs, [(254, 254, 254)] * 4, [(0.0, 1.0, 0.0)] * 4,
                        [(0, 1, 2), (0, 2, 3), (0, 2, 1), (0, 3, 2)])


def register(path, name):
    lst = os.path.join(root, path)
    if name not in [l.split('=')[0].strip() for l in open(lst).read().split('\n')]:
        with open(lst, 'a') as f:
            f.write(name + '\n')


def set_folder(texture_set):
    return texture_set[len('MAP_TEXTURE_SET_'):].lower()


def build_imports(m):
    """The textures a matrix's copies use that its area's sets lack, imported into each season's set from the set
    the original chunk took them from (texture_imports.schema.json)."""
    need = {}
    for chunk in m['chunks']:
        if not copied(chunk):
            continue
        doc, _ = bc.read_glb(os.path.join(MODELS, copy_folder(chunk), 'model.glb'))
        for image in doc['images']:
            parts = image['uri'].split('/')
            need.setdefault(parts[-1][:-len('.png')], 'MAP_TEXTURE_SET_' + parts[-2].upper())
    for texture_set in m['seasons']:
        path = os.path.join(TEXTURES, set_folder(texture_set), 'imports.json')
        have = {f[:-4] for f in os.listdir(os.path.dirname(path)) if f.endswith('.png')}
        imports = [{'texture': t, 'from': src} for t, src in sorted(need.items()) if t not in have]
        if not imports:
            continue
        with open(path, 'w') as f:
            f.write(json.dumps({'$schema': '../texture_imports.schema.json', 'textures': imports}, indent=4) + '\n')


def build_matrix(constant_name, m):
    register('generated/map_matrices.txt', constant_name)
    at = {pos: (chunk, zone) for chunk, (pos, zone) in m['chunks'].items()}
    width, height = MATRIX_SIZE

    def rows(cell):
        return ',\n'.join('        [ ' + ', '.join('"%s"' % cell(x, z) for x in range(width)) + ' ]'
                          for z in range(height))

    maps = rows(lambda x, z: constant(at[x, z][0]) if (x, z) in at else TREE)
    zones = rows(lambda x, z: at[x, z][1] if (x, z) in at else m['forest_zone'])
    with open(os.path.join(root, m['file']), 'w') as f:
        f.write('{\n    "$schema": "map_matrix.schema.json",\n    "maps": [\n' + maps + '\n    ],\n    "zones": [\n'
                + zones + '\n    ]\n}\n')


def build_zones(constant_name, m):
    for zone in m['zones']:
        path = os.path.join(root, 'res/field/zones', zone[len('ZONE_'):].lower() + '.json')
        z = json.load(open(path))
        z['matrix'] = constant_name
        with open(path, 'w') as f:
            f.write(json.dumps(z, indent=4, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    for chunk in sorted({c for c in list(RAISED) + list(CUTS) + list(BLOCKED)}):
        build_copy(chunk)
    for constant_name, m in MATRICES.items():
        build_matrix(constant_name, m)
        build_zones(constant_name, m)
        build_imports(m)
