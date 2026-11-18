"""Escape from Unova: the coast around the player's base.

The base's land (the strip of Nacrene south of its northern buildings, and the forest and Route 3's edge around it) meets
the sea through a sandy beach, in Undella Bay's sand, instead of dropping straight into the water. The town north of
the base is gone under the sea.

The sea and sand are one height field over the base's matrix (build_base.py's MATRIX), worked out from each point's
distance to the land: flat sand for EFU_FLAT units, then a slope down to the sea floor over EFU_SLOPE units. The water is
two planes over every sea tile, as the game's own sea chunk has it (an opaque floor and a translucent surface), and a
line of surf runs along the shore where the sand goes under the surface.

It writes:
- the sea chunks beside the land as new map models, written whole from their GLBs (data.json "written"), templated on
  the game's sea chunk: efu_coast_w1 (west of the base), efu_coast_w2 (south-west) and efu_coast_n2 (north, beside
  Route 3's forest);
- the base's two Nacrene chunks as written models: their geometry and props north of the base's buildings dropped, and
  the sea and sand added there;
- each chunk's collision: the sand west of the base is walkable, the rest of the coast is not;
- imports.json for Nacrene's four seasonal texture sets, which gain Undella Bay's sand and surf.

Run by build_base.py after it has written the chunks' rubble and collision.
"""
import csv, io, json, math, os, struct

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
MODELS = os.path.join(root, 'res/field/maps/models')
TEXTURES = os.path.join(root, 'res/field/maps/textures')

TILE = 16
CHUNK = 32
# Nacrene's texture sets by season, and Undella Bay's, whose sand and surf they import
NACRENE_SETS = ['MAP_TEXTURE_SET_SHARED_DANSA01A_10', 'MAP_TEXTURE_SET_SHARED_DANSA01A_11',
                'MAP_TEXTURE_SET_SHARED_DANSA01A_12', 'MAP_TEXTURE_SET_SHARED_DANSA01A_13']
UNDELLA_SETS = ['MAP_TEXTURE_SET_SHARED_DANSA01A_59', 'MAP_TEXTURE_SET_SHARED_DANSA01A_60',
                'MAP_TEXTURE_SET_SHARED_DANSA01A_61', 'MAP_TEXTURE_SET_SHARED_DANSA01A_62']
IMPORTED = ['sea_jimen', 'sea_zanami']

# The height field, in world units: flat sand next to the land, then the slope down to the floor of the sea
EFU_FLAT = 32
EFU_SLOPE = 72
SEA_FLOOR = -40
SEA_SURFACE = -27
SURF_WIDTH = 32

# The land, as rectangles of matrix tiles [x0, x1) x [z0, z1): the base's strip of the two Nacrene chunks (their rows 16
# and on), the Route 3 gate's chunk and the forest east of it, and the forest along the south
LAND = [(32, 96, 48, 64), (96, 160, 0, 64), (32, 160, 64, 96)]

# The chunks that are generated or edited: matrix column and row, the model, and its walkable sand's local rows
NEW_CHUNKS = {
    (0, 1): ('efu_coast_w1', 'MAP_MODEL_EFU_COAST_W1', range(16, 30)),
    (0, 2): ('efu_coast_w2', 'MAP_MODEL_EFU_COAST_W2', range(0)),
    (2, 0): ('efu_coast_n2', 'MAP_MODEL_EFU_COAST_N2', range(0)),
}
NACRENE_CHUNKS = {(1, 1): 'overworld_2_map19_18', (2, 1): 'overworld_2_map20_18'}
# The Nacrene rows that are now sea
NACRENE_SEA_ROWS = 16

BLOCKED = {'shape': '0', 'slope': '0', 'offset': '3', 'tile_type': str(0x810001), 'diagonal': '0'}
SAND = {'shape': '0', 'slope': '0', 'offset': '3', 'tile_type': str(0x880019), 'diagonal': '0'}


def distance(gx, gz):
    """World units from a point of the matrix (in world units) to the nearest land."""
    best = 1e9
    for x0, x1, z0, z1 in LAND:
        dx = max(x0 * TILE - gx, 0, gx - x1 * TILE)
        dz = max(z0 * TILE - gz, 0, gz - z1 * TILE)
        best = min(best, math.hypot(dx, dz))
    return best


def is_land(tx, tz):
    return any(x0 <= tx < x1 and z0 <= tz < z1 for x0, x1, z0, z1 in LAND)


def height(d):
    if d <= EFU_FLAT:
        return 0.0
    return max(SEA_FLOOR - 1.0, -(d - EFU_FLAT) * (-SEA_FLOOR) / EFU_SLOPE)


class Prims:
    """The new primitives of a GLB: per material, its vertices (position, UV) and triangles."""

    def __init__(self):
        self.by_material = {}

    def quad(self, material, corners):
        """corners: four (x, y, z, u, v), in order around the quad."""
        verts, tris = self.by_material.setdefault(material, ([], []))
        base = len(verts)
        verts.extend(corners)
        # Facing up: (0, 1, 2) and (0, 2, 3) with the corners going clockwise seen from above
        tris.extend([(base, base + 2, base + 1), (base, base + 3, base + 2)])


def water_uv(x, z):
    # As the game's sea chunk lays sea_mizu1 out, so the water lines up with it across chunks
    return -x / 64, 1 - z / 64


def sea_tiles(cx, cz, sea_rows=None):
    for tz in range(CHUNK):
        for tx in range(CHUNK):
            if sea_rows is not None and tz >= sea_rows:
                continue
            if not is_land(cx * CHUNK + tx, cz * CHUNK + tz):
                yield tx, tz


def coast_prims(cx, cz, sea_rows=None):
    p = Prims()
    tiles = list(sea_tiles(cx, cz, sea_rows))

    def corner(tx, tz):
        x, z = tx * TILE - 256, tz * TILE - 256
        d = distance(cx * CHUNK * TILE + tx * TILE, cz * CHUNK * TILE + tz * TILE)
        return x, z, d

    # The water: runs of sea tiles along each row, at the sea's floor and surface
    rows = {}
    for tx, tz in tiles:
        rows.setdefault(tz, []).append(tx)
    for tz, xs in rows.items():
        xs.sort()
        start = prev = xs[0]
        for tx in xs[1:] + [None]:
            if tx is not None and tx == prev + 1:
                prev = tx
                continue
            x0, x1 = start * TILE - 256, (prev + 1) * TILE - 256
            z0, z1 = tz * TILE - 256, (tz + 1) * TILE - 256
            for material, y in (('sea_mizu1', SEA_FLOOR), ('sea_mizu1_1', SEA_SURFACE)):
                p.quad(material, [(x, y, z) + water_uv(x, z) for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))])
            if tx is not None:
                start = prev = tx
    # The sand where it rises above the floor, and the surf where it meets the surface
    for tx, tz in tiles:
        cs = [corner(tx + dx, tz + dz) for dx, dz in ((0, 0), (1, 0), (1, 1), (0, 1))]
        hs = [height(d) for _, _, d in cs]
        if max(hs) > SEA_FLOOR:
            p.quad('sea_jimen', [(x, h, z, x / TILE, z / TILE) for (x, z, _), h in zip(cs, hs)])
        # The surf: from where the sand goes under (v 0, the foam) out to SURF_WIDTH beyond (v 1, clear)
        shore = EFU_FLAT + EFU_SLOPE * (SEA_SURFACE / SEA_FLOOR)
        vs = [(d - shore) / SURF_WIDTH for _, _, d in cs]
        if min(vs) < 1 and max(vs) > -0.5:
            p.quad('sea_zanami', [(x, SEA_SURFACE + 0.5, z, (x + z) / TILE, min(1.0, max(0.0, v)))
                                  for (x, z, _), v in zip(cs, vs)])
    return p


MATERIALS = {
    'sea_mizu1': {'name': 'sea_mizu1', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0},
                  'extensions': {'KHR_materials_unlit': {}}},
    'sea_mizu1_1': {'name': 'sea_mizu1_1', 'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 0}, 'metallicFactor': 0, 'baseColorFactor': [1, 1, 1, 0.5161290168762207]},
        'extensions': {'KHR_materials_unlit': {}}, 'alphaMode': 'BLEND'},
    'sea_jimen': {'name': 'sea_jimen', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0},
                  'extensions': {'KHR_materials_unlit': {}}},
    'grass01ax': {'name': 'grass01ax', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0},
                  'extensions': {'KHR_materials_unlit': {}}},
    'sea_zanami': {'name': 'sea_zanami', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                                                  'metallicFactor': 0},
                   'extensions': {'KHR_materials_unlit': {}}, 'alphaMode': 'BLEND'},
}
# Where each new material's image is (the packer binds it by the file's name)
IMAGE_SET = {'sea_mizu1': 'shared_dansa01a_10', 'sea_mizu1_1': 'shared_dansa01a_10',
             'sea_jimen': 'shared_dansa01a_59', 'sea_zanami': 'shared_dansa01a_59', 'grass01ax': 'shared_dansa01a_10'}


def covered_tiles(triangles):
    """The tiles whose centers flat triangles (ground, not trees) cover, as (x, z)."""
    def side(p, a, b):
        return (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])

    tiles = set()
    for t in triangles:
        ys = [v[1] for v in t]
        if max(ys) - min(ys) > 6 or sum(ys) / 3 > 12:
            continue
        a, b, c = [(v[0], v[2]) for v in t]
        xs, zs = [v[0] for v in t], [v[2] for v in t]
        for tz in range(max(0, int((min(zs) + 256) // TILE)), min(CHUNK, int((max(zs) + 256) // TILE) + 1)):
            for tx in range(max(0, int((min(xs) + 256) // TILE)), min(CHUNK, int((max(xs) + 256) // TILE) + 1)):
                p = (tx * TILE - 256 + TILE / 2, tz * TILE - 256 + TILE / 2)
                d = (side(p, a, b), side(p, b, c), side(p, c, a))
                if not (min(d) < 0 < max(d)):
                    tiles.add((tx, tz))
    return tiles


def read_glb(path):
    b = open(path, 'rb').read()
    jl = struct.unpack('<I', b[12:16])[0]
    doc = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack('<I', b[off:off + 4])[0]
    return doc, b[off + 8:off + 8 + bl]


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    bv = doc['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    fmt, size = {5126: ('f', 4), 5123: ('H', 2), 5125: ('I', 4), 5121: ('B', 1)}[a['componentType']]
    stride = bv.get('byteStride') or size * n
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return [struct.unpack_from('<' + fmt * n, binary, start + i * stride) for i in range(a['count'])]


class Writer:
    """A GLB of one mesh, written from scratch."""

    def __init__(self, mesh_name):
        self.doc = {'asset': {'version': '2.0'}, 'extensionsUsed': ['KHR_materials_unlit'],
                    'nodes': [{'name': 'polySurface1'}, {'name': mesh_name, 'mesh': 0}],
                    'scenes': [{'nodes': [0, 1]}], 'scene': 0, 'meshes': [{'name': mesh_name, 'primitives': []}],
                    'samplers': [{'wrapS': 10497, 'wrapT': 10497, 'magFilter': 9728, 'minFilter': 9728}],
                    'images': [], 'textures': [], 'materials': [], 'accessors': [], 'bufferViews': [],
                    'buffers': [{'byteLength': 0}]}
        self.binary = bytearray()

    def add(self, fmt, values, kind, component, normalized=False, target=None):
        while len(self.binary) % 4:
            self.binary.append(0)
        start = len(self.binary)
        for v in values:
            self.binary += struct.pack('<' + fmt, *v)
        view = {'buffer': 0, 'byteOffset': start, 'byteLength': len(self.binary) - start}
        if target:
            view['target'] = target
        self.doc['bufferViews'].append(view)
        acc = {'bufferView': len(self.doc['bufferViews']) - 1, 'componentType': component, 'count': len(values),
               'type': kind}
        if normalized:
            acc['normalized'] = True
        if kind == 'VEC3' and component == 5126:
            acc['min'] = [min(v[i] for v in values) for i in range(3)]
            acc['max'] = [max(v[i] for v in values) for i in range(3)]
        self.doc['accessors'].append(acc)
        return len(self.doc['accessors']) - 1

    def material(self, material, uri):
        material = json.loads(json.dumps(material))
        self.doc['images'].append({'uri': uri})
        self.doc['textures'].append({'source': len(self.doc['images']) - 1, 'sampler': 0})
        binding = material.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if binding is not None:
            binding['index'] = len(self.doc['textures']) - 1
        self.doc['materials'].append(material)
        return len(self.doc['materials']) - 1

    def primitive(self, material, positions, uvs, colors, normals, triangles):
        attributes = {'POSITION': self.add('fff', positions, 'VEC3', 5126, target=34962),
                      'TEXCOORD_0': self.add('ff', uvs, 'VEC2', 5126, target=34962),
                      'COLOR_0': self.add('BBB', colors, 'VEC3', 5121, normalized=True, target=34962)}
        if normals is not None:
            attributes['NORMAL'] = self.add('fff', normals, 'VEC3', 5126, target=34962)
        indices = self.add('H', [(i,) for t in triangles for i in t], 'SCALAR', 5123, target=34963)
        self.doc['meshes'][0]['primitives'].append({'attributes': attributes, 'indices': indices,
                                                    'material': material})

    def add_prims(self, prims):
        for name, (verts, tris) in prims.by_material.items():
            image = name.split('_1')[0] if name == 'sea_mizu1_1' else name
            names = [m['name'] for m in self.doc['materials']]
            material = names.index(name) if name in names else self.material(
                MATERIALS[name], f'../../textures/{IMAGE_SET[name]}/{image}.png')
            # Lit from straight above like the original ground (the writer turns light 0 on for shapes with normals),
            # so the beach and the sea darken at night with the rest of the map
            for chunk_start in range(0, len(tris), 20000):
                part = tris[chunk_start:chunk_start + 20000]
                used = sorted({i for t in part for i in t})
                remap = {old: new for new, old in enumerate(used)}
                self.primitive(material, [verts[i][:3] for i in used], [verts[i][3:] for i in used],
                               [(254, 254, 254)] * len(used), [(0.0, 1.0, 0.0)] * len(used),
                               [tuple(remap[i] for i in t) for t in part])

    def save(self, path):
        while len(self.binary) % 4:
            self.binary.append(0)
        self.doc['buffers'][0]['byteLength'] = len(self.binary)
        encoded = json.dumps(self.doc, separators=(',', ':')).encode()
        encoded += b' ' * (-len(encoded) % 4)
        data = (struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(encoded) + 8 + len(self.binary))
                + struct.pack('<II', len(encoded), 0x4e4f534a) + encoded
                + struct.pack('<II', len(self.binary), 0x004e4942) + bytes(self.binary))
        with open(path, 'wb') as f:
            f.write(data)


def write_csv(path, rows):
    f = io.StringIO()
    w = csv.DictWriter(f, fieldnames=['x', 'z', 'shape', 'slope', 'offset', 'tile_type', 'diagonal'],
                       lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    with open(path, 'w', newline='\n') as out:
        out.write(f.getvalue())


def coast_terrain(cx, cz, walk_rows):
    rows = []
    for tz in range(CHUNK):
        for tx in range(CHUNK):
            d = distance(cx * CHUNK * TILE + tx * TILE + TILE / 2, cz * CHUNK * TILE + tz * TILE + TILE / 2)
            cell = SAND if (d <= EFU_FLAT and tz in walk_rows) else BLOCKED
            rows.append(dict(cell, x=str(tx), z=str(tz)))
    return rows


def build_new_chunk(pos, folder, constant, walk_rows):
    path = os.path.join(MODELS, folder)
    os.makedirs(path, exist_ok=True)
    w = Writer('map_outsea')
    w.add_prims(coast_prims(*pos))
    w.save(os.path.join(path, 'model.glb'))
    with open(os.path.join(path, 'data.json'), 'w') as f:
        f.write(json.dumps({'$schema': '../map_model.schema.json', 'texture_set': NACRENE_SETS[0], 'written': True,
                            'template': 'MAP_MODEL_OVERWORLD_2_MAP_OUTSEA'}, indent=4) + '\n')
    write_csv(os.path.join(path, 'terrain_0.csv'), coast_terrain(*pos, walk_rows))
    with open(os.path.join(path, 'terrain_0_splits.csv'), 'w') as f:
        f.write('index,unused,slope0,slope1,offset0,offset1\n')
    lst = os.path.join(root, 'generated/map_models.txt')
    names = [l.split('=')[0].strip() for l in open(lst).read().split('\n')]
    if constant not in names:
        with open(lst, 'a') as f:
            f.write(constant + '\n')


def build_nacrene_chunk(pos, folder):
    """Rewrites a Nacrene chunk as a written model: what lies north of the base goes, and the coast comes in."""
    path = os.path.join(MODELS, folder)
    doc, binary = read_glb(os.path.join(path, 'model.glb'))
    mesh = doc['meshes'][0]
    w = Writer(mesh['name'])
    edge = NACRENE_SEA_ROWS * TILE - 256
    ground = set()
    for prim in mesh['primitives']:
        att = prim['attributes']
        positions = accessor(doc, binary, att['POSITION'])
        uvs = accessor(doc, binary, att['TEXCOORD_0'])
        colors = accessor(doc, binary, att['COLOR_0'])
        normals = accessor(doc, binary, att['NORMAL']) if 'NORMAL' in att else None
        idx = [i[0] for i in accessor(doc, binary, prim['indices'])]
        tris = [tuple(idx[k:k + 3]) for k in range(0, len(idx), 3)]
        # A triangle stays if it is mostly south of the edge, and a flat one (the ground) only if none of it reaches
        # past; the tall ones (trees along the edge) may lean over it
        def keep(t):
            zs = [positions[i][2] for i in t]
            ys = [positions[i][1] for i in t]
            if sum(zs) / 3 < edge - 2:
                return False
            return not (min(zs) < edge - 4 and max(ys) - min(ys) < 4)
        tris = [t for t in tris if keep(t)]
        if not tris:
            continue
        if doc['materials'][prim['material']].get('alphaMode') != 'BLEND':
            ground |= covered_tiles([[positions[i] for i in t] for t in tris])
        used = sorted({i for t in tris for i in t})
        remap = {old: new for new, old in enumerate(used)}
        old = doc['materials'][prim['material']]
        binding = old.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        uri = doc['images'][doc['textures'][binding['index']]['source']]['uri'] if binding else 'none.png'
        # Two materials of one name (20_18 has) can't both be in the written model: the first one serves both
        names = [m['name'] for m in w.doc['materials']]
        material = names.index(old['name']) if old['name'] in names else w.material(old, uri)
        w.primitive(material, [positions[i] for i in used], [uvs[i] for i in used], [colors[i] for i in used],
                    [normals[i] for i in used] if normals is not None else None,
                    [tuple(remap[i] for i in t) for t in tris])
    prims = coast_prims(*pos, sea_rows=NACRENE_SEA_ROWS)
    # Sand just under the ground of the first two rows of the base, where the street north used to run: the ground the
    # dropped triangles took leaves holes there, between the beach and the backs of the buildings
    for tz in (NACRENE_SEA_ROWS, NACRENE_SEA_ROWS + 1):
        z0, z1 = tz * TILE - 256, (tz + 1) * TILE - 256
        for tx in range(CHUNK):
            x0, x1 = tx * TILE - 256, (tx + 1) * TILE - 256
            prims.quad('sea_jimen', [(x, -1.0, z, x / TILE, z / TILE) for x, z in ((x0, z0), (x1, z0), (x1, z1),
                                                                                  (x0, z1))])
    # Grass under what the drop left bare further south: the trees in the north-west corner stood on ground that reached
    # past the edge
    for tz in range(NACRENE_SEA_ROWS + 2, CHUNK):
        for tx in range(CHUNK):
            if (tx, tz) not in ground:
                x0, z0 = tx * TILE - 256, tz * TILE - 256
                prims.quad('grass01ax', [(x, -0.5, z, x / TILE, z / TILE) for x, z in ((x0, z0), (x0 + TILE, z0),
                                                                                     (x0 + TILE, z0 + TILE),
                                                                                     (x0, z0 + TILE))])
    w.add_prims(prims)
    # The props: those north of the edge go (the rubble along it stays)
    for node in doc['nodes']:
        name = node.get('name', '')
        if name.startswith('bw2_prop_') and node['translation'][2] >= edge:
            w.doc['nodes'].append({k: node[k] for k in ('name', 'translation', 'rotation', 'scale') if k in node})
            w.doc['scenes'][0]['nodes'].append(len(w.doc['nodes']) - 1)
    w.save(os.path.join(path, 'model.glb'))
    data = json.load(open(os.path.join(path, 'data.json')))
    data = {'$schema': data['$schema'], 'texture_set': NACRENE_SETS[0], 'written': True}
    with open(os.path.join(path, 'data.json'), 'w') as f:
        f.write(json.dumps(data, indent=4) + '\n')
    # The collision north of the edge is the sea's
    rows = list(csv.DictReader(open(os.path.join(path, 'terrain_0.csv'))))
    for r in rows:
        if int(r['z']) < NACRENE_SEA_ROWS:
            r.update(BLOCKED)
    write_csv(os.path.join(path, 'terrain_0.csv'), rows)


def build_imports():
    for nacrene, undella in zip(NACRENE_SETS, UNDELLA_SETS):
        folder = nacrene[len('MAP_TEXTURE_SET_'):].lower()
        with open(os.path.join(TEXTURES, folder, 'imports.json'), 'w') as f:
            f.write(json.dumps({'$schema': '../texture_imports.schema.json',
                                'textures': [{'texture': t, 'from': undella} for t in IMPORTED]}, indent=4) + '\n')


def build_coast():
    build_imports()
    for pos, (folder, constant, walk_rows) in NEW_CHUNKS.items():
        build_new_chunk(pos, folder, constant, walk_rows)
    for pos, folder in NACRENE_CHUNKS.items():
        build_nacrene_chunk(pos, folder)


if __name__ == '__main__':
    build_coast()
