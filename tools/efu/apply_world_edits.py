"""Escape from Unova: apply the world editor's edits (tools/efu/world_edits.json) to res/.

Run after build_raid.py, since the edits sit on top of what build_zone.py and build_raid.py write; idempotent, so it
can run again at any time. The editor (tools/efu/world_editor/) saves the file: a list of operations, in order:

- {"op": "matrix", "matrix", "x", "z", "model"?, "zone"?}: a chunk of a matrix shows another model or is another zone.
  A new model drops the chunk's earlier edits;
- {"op": "cut", "matrix", "x", "z", "rect": [x0, z0, x1, z1], "ground", "groundY"}: everything in the tiles' column
  goes (ground, trees, props), the ground material (if any) is laid flat at groundY, and each tile copies the nearest
  walkable tile (build_zone.py's CUTS, done anywhere);
- {"op": "stamp", "matrix", "x", "z", "from": MAP_MODEL_X, "rect", "to": [x, z], "props"}: a rectangle of a model's
  geometry and tiles (and its props, when both places use the same prop bundle) copied over the chunk at tile `to`;
- {"op": "tiles", "matrix", "x", "z", "set": {"x,z": {"tile_type": n}}}: tiles' types (collision, class);
- {"op": "erase", "matrix", "rect": [x0, z0, x1, z1], "layers", "ground"?, "groundY"?}: a rectangle of the matrix's
  tiles (global, ends exclusive) cleared on the given layers (geometry.js's LAYERS: ground, props, collision, class):
  the ground's geometry goes, the ground material is laid flat at groundY and the tiles take the nearest walkable
  tile's heights; props go; collision clears; the class takes the nearest walkable tile's;
- {"op": "copy", "from": {"matrix", "rect"}, "matrix", "to": [[x, z], ...], "layers"}: a rectangle of a matrix's tiles
  copied, on the given layers, with its top left at each tile of `to`, all read before any is written (the editor's
  move, paste and pattern brush);
- {"op": "prop", "matrix", "x", "z", "action": "add" | "set" | "delete", "match"?, "value"?}: a field prop of a chunk,
  {resId, translation, rotation, scale} in the chunk's own units, found by its id, place and turn;
- {"op": "event", "zone", "kind", "action": "add" | "set" | "delete", "match"?, "value"?}: a zone's NPC, warp,
  trigger or background event, found by all of its fields (match), but a warp's lock (grid.unk0a). A set or delete
  whose match isn't there is taken as done already and skipped (with a note, so that a change by build_raid.py to the
  same event shows);
- {"op": "lock", "zone", "x", "z", "locked", "item"?, "consume"?, "relock"?}: the zone's warp at grid x, z (world
  units) is locked until opened, with the key item if any (used up if consume), and locks again on each raid if
  relock. Each lock keeps its number in world_locks.json (EFU_LOCK_COUNT of them, never reused, since saves keep
  their flags): the warp's grid.unk0a is the number, and a sign on its tile runs the lock's script (gen_efu.py).

Edits run in order, each on the chunks as the edits before it left them, as the editor shows them.

A chunk with edits gets its own model, efu_edit_<matrix less EFU_>_<x>_<z> (MAP_MODEL_EFU_EDIT_*), rebuilt each run from its base
(the model the matrix had there before; recorded in world_edit_bases.json for runs after the first), written whole
like build_zone.py's copies, with its area's texture sets importing any texture its geometry names that they lack.
"""
import copy
import csv
import json
import math
import os
import re
import sys

import build_coast as bc
import build_zone as bz

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
RES = os.path.join(root, 'res', 'field')
MODELS = os.path.join(RES, 'maps', 'models')
TEXTURES = os.path.join(RES, 'maps', 'textures')
EDITS = os.path.join(here, 'world_edits.json')
BASES = os.path.join(here, 'world_edit_bases.json')
TILE = 16
KINDS = ('npcs', 'warps', 'triggers', 'bg_events')


def stem(constant, prefix):
    return constant[len(prefix):].lower()


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def canon(v):
    return json.dumps(v, sort_keys=True, separators=(',', ':'))


def event_key(kind, v):
    """An event's fields as edits match it: a warp's lock (grid.unk0a) is the lock edits' own."""
    if kind == 'warps' and isinstance(v, dict) and isinstance(v.get('grid'), dict):
        v = dict(v, grid=dict(v['grid'], unk0a=0))
    return canon(v)


class Files:
    """The JSON files the edits change, written once at the end."""

    def __init__(self):
        self.data = {}

    def get(self, path):
        if path not in self.data:
            self.data[path] = load(path)
        return self.data[path]

    def matrix(self, name):
        return self.get(os.path.join(RES, 'matrices', stem(name, 'MAP_MATRIX_') + '.json'))

    def events(self, zone):
        return self.get(os.path.join(RES, 'events', stem(zone, 'ZONE_') + '.json'))

    def save(self):
        for path, data in self.data.items():
            if os.path.basename(os.path.dirname(path)) == 'matrices':
                text = write_matrix(data)
            else:
                text = json.dumps(data, indent=4, ensure_ascii=False) + '\n'
            with open(path, 'w', encoding='utf-8', newline='\n') as f:
                f.write(text)


def write_matrix(m):
    def rows(grid):
        return ',\n'.join('        [ ' + ', '.join(json.dumps(c) for c in row) + ' ]' for row in grid)
    out = '{\n    "$schema": "%s",\n    "maps": [\n%s\n    ]' % (m.get('$schema', 'map_matrix.schema.json'), rows(m['maps']))
    if m.get('zones') is not None:
        out += ',\n    "zones": [\n%s\n    ]' % rows(m['zones'])
    return out + '\n}\n'


# ---- Events ----------------------------------------------------------------------------------------------------------

def apply_event(files, op, notes):
    data = files.events(op['zone'])
    items = data.setdefault(op['kind'], [])
    kind = op['kind']
    if op['action'] == 'add':
        if any(event_key(kind, o) == event_key(kind, op['value']) for o in items):
            return
        items.append(op['value'])
        return
    key = event_key(kind, op['match'])
    at = next((i for i, o in enumerate(items) if event_key(kind, o) == key), None)
    if at is None:
        if op['action'] == 'set' and any(event_key(kind, o) == event_key(kind, op['value']) for o in items):
            return
        if op['action'] == 'delete':
            return
        notes.append('skipped: %s of a %s in %s that is no longer there: %s' % (op['action'], op['kind'], op['zone'],
                                                                             key[:160]))
        return
    if op['action'] == 'set':
        items[at] = op['value']
    else:
        del items[at]


# ---- Chunks ----------------------------------------------------------------------------------------------------------

def zone_area(zone):
    path = os.path.join(RES, 'zones', stem(zone, 'ZONE_') + '.json')
    return load(path)['area'] if os.path.exists(path) else None


def area_data(area):
    path = os.path.join(RES, 'areas', stem(area, 'AREA_') + '.json')
    return load(path) if os.path.exists(path) else None


def season_sets(area):
    sets = []
    for suffix in ('', '_SUMMER', '_AUTUMN', '_WINTER'):
        a = area_data(area + suffix)
        if a and a.get('texture_set') and a['texture_set'] not in sets:
            sets.append(a['texture_set'])
    return sets


def cell_zone(files, matrix_name, x, z):
    m = files.matrix(matrix_name)
    if m.get('zones'):
        return m['zones'][z][x]
    for name in os.listdir(os.path.join(RES, 'zones')):
        if name.endswith('.json') and not name.endswith('schema.json'):
            h = load(os.path.join(RES, 'zones', name))
            if h.get('matrix') == matrix_name:
                return 'ZONE_' + name[:-5].upper()
    return None


class Model:
    """A chunk's geometry as polygons by material, its props and its terrain, read from a model's folder."""

    def __init__(self, constant):
        self.constant = constant
        self.folder = os.path.join(MODELS, stem(constant, 'MAP_MODEL_'))
        self.doc, binary = bc.read_glb(os.path.join(self.folder, 'model.glb'))
        mesh = [n for n in self.doc['nodes'] if 'mesh' in n][0]
        self.mesh_name = mesh['name']
        self.materials = []   # [name, material json, uri]
        self.polys = {}       # material index -> [polygon]
        for prim in self.doc['meshes'][mesh['mesh']]['primitives']:
            att = prim['attributes']
            positions = bc.accessor(self.doc, binary, att['POSITION'])
            uvs = bc.accessor(self.doc, binary, att['TEXCOORD_0'])
            colors = bc.accessor(self.doc, binary, att['COLOR_0'])
            normals = (bc.accessor(self.doc, binary, att['NORMAL']) if 'NORMAL' in att
                       else [(0.0, 1.0, 0.0)] * len(positions))
            idx = [i[0] for i in bc.accessor(self.doc, binary, prim['indices'])]
            old = self.doc['materials'][prim['material']]
            binding = old.get('pbrMetallicRoughness', {}).get('baseColorTexture')
            uri = (self.doc['images'][self.doc['textures'][binding['index']]['source']]['uri']
                   if binding else 'none.png')
            m = self.material(old, uri)
            verts = [tuple(float(c) for c in positions[i]) + tuple(float(c) for c in uvs[i])
                     + tuple(float(c) for c in colors[i][:3]) + tuple(float(c) for c in normals[i])
                     for i in range(len(positions))]
            self.polys.setdefault(m, []).extend([verts[i] for i in idx[k:k + 3]] for k in range(0, len(idx), 3))
        self.props = [{k: n[k] for k in ('name', 'translation', 'rotation', 'scale') if k in n}
                      for n in self.doc['nodes'] if n.get('name', '').startswith('bw2_prop_')]
        self.terrain = list(csv.DictReader(open(os.path.join(self.folder, 'terrain_0.csv'), newline='')))
        splits = os.path.join(self.folder, 'terrain_0_splits.csv')
        self.splits = list(csv.DictReader(open(splits, newline=''))) if os.path.exists(splits) else []
        self.data = load(os.path.join(self.folder, 'data.json'))

    def material(self, material, uri):
        for i, (name, _, _) in enumerate(self.materials):
            if name == material['name']:
                return i
        self.materials.append([material['name'], material, uri])
        return len(self.materials) - 1

    def at(self, x, z):
        return next(r for r in self.terrain if int(r['x']) == x and int(r['z']) == z)


def units(rect):
    return [v * TILE - 256 for v in rect]


def cut(model, op):
    x0, z0, x1, z1 = units(op['rect'])
    for m, polys in model.polys.items():
        model.polys[m] = [part for p in polys for part in bz.outside(p, x0, z0, x1, z1)]
    model.props = [p for p in model.props
                   if not (x0 - 8 < p['translation'][0] < x1 + 8 and z0 - 8 < p['translation'][2] < z1 + 8)]
    ground = op.get('ground')
    if ground:
        m = next((i for i, (name, _, _) in enumerate(model.materials) if name == ground), None)
        if m is not None:
            y = float(op.get('groundY') or 0)
            corners = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
            verts = [c + (c[0] / 32, c[2] / 32, 254.0, 254.0, 254.0, 0.0, 1.0, 0.0) for c in corners]
            model.polys.setdefault(m, []).extend([[verts[0], verts[2], verts[1]], [verts[0], verts[3], verts[2]]])
    # Each tile as the walkable ground tile nearest it
    tx0, tz0, tx1, tz1 = op['rect']
    walkable = [r for r in model.terrain if not int(r['tile_type']) & bz.BLOCKED_TILE and r['shape'] == '0'
                and not (tx0 <= int(r['x']) < tx1 and tz0 <= int(r['z']) < tz1)]
    if walkable:
        for x in range(tx0, tx1):
            for z in range(tz0, tz1):
                near = min(walkable, key=lambda r: (abs(int(r['x']) - x) + abs(int(r['z']) - z)))
                model.at(x, z).update({k: near[k] for k in ('shape', 'slope', 'offset', 'tile_type')})


def inside(poly, x0, z0, x1, z1):
    p = bz.clip_half(poly, 0, x0, False)
    if p:
        p = bz.clip_half(p, 0, x1, True)
    if p:
        p = bz.clip_half(p, 2, z0, False)
    if p:
        p = bz.clip_half(p, 2, z1, True)
    return p if p and bz.area(p) > 1e-3 else None


def stamp(model, op, sources):
    src = sources.setdefault(op['from'], Model(op['from']))
    sx0, sz0, sx1, sz1 = units(op['rect'])
    dx = (op['to'][0] - op['rect'][0]) * TILE
    dz = (op['to'][1] - op['rect'][1]) * TILE
    x0, z0, x1, z1 = sx0 + dx, sz0 + dz, sx1 + dx, sz1 + dz
    for m, polys in model.polys.items():
        model.polys[m] = [part for p in polys for part in bz.outside(p, x0, z0, x1, z1)]
    for sm, polys in src.polys.items():
        name, material, uri = src.materials[sm]
        moved = []
        for p in polys:
            q = inside(p, sx0, sz0, sx1, sz1)
            if q:
                moved.append([(v[0] + dx, v[1], v[2] + dz) + tuple(v[3:]) for v in q])
        if moved:
            model.polys.setdefault(model.material(material, uri), []).extend(moved)
    if op.get('props'):
        model.props = [p for p in model.props
                       if not (x0 <= p['translation'][0] < x1 and z0 <= p['translation'][2] < z1)]
        for p in src.props:
            x, y, z = p['translation']
            if sx0 <= x < sx1 and sz0 <= z < sz1:
                model.props.append(dict(p, translation=[x + dx, y, z + dz]))
    rx0, rz0, rx1, rz1 = op['rect']
    for x in range(rx0, rx1):
        for z in range(rz0, rz1):
            tx, tz = op['to'][0] + x - rx0, op['to'][1] + z - rz0
            if not (0 <= tx < 32 and 0 <= tz < 32):
                continue
            row = dict(src.at(x, z))
            if row['shape'] != '0':
                split = dict(src.splits[int(row['offset'])])
                split['index'] = str(len(model.splits))
                model.splits.append(split)
                row['offset'] = split['index']
            model.at(tx, tz).update({k: row[k] for k in ('shape', 'slope', 'offset', 'tile_type', 'diagonal')})


def tiles(model, op):
    for xz, v in op['set'].items():
        x, z = (int(n) for n in xz.split(','))
        if 'tile_type' in v:
            model.at(x, z)['tile_type'] = str(int(v['tile_type']))


def write_model(model, constant, texture_set, template):
    folder = os.path.join(MODELS, stem(constant, 'MAP_MODEL_'))
    os.makedirs(folder, exist_ok=True)
    w = bc.Writer(model.mesh_name)
    written = {}
    for m, polys in sorted(model.polys.items()):
        tris = [(p[0], p[j], p[j + 1]) for p in polys for j in range(1, len(p) - 1)]
        if not tris:
            continue
        name, material, uri = model.materials[m]
        if name not in written:
            written[name] = w.material(material, uri)
        for start in range(0, len(tris), 20000):
            part = tris[start:start + 20000]
            vs = [v for t in part for v in t]
            w.primitive(written[name], [v[0:3] for v in vs], [v[3:5] for v in vs],
                        [tuple(min(255, max(0, round(c))) for c in v[5:8]) for v in vs], [v[8:11] for v in vs],
                        [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(part))])
    for p in model.props:
        w.doc['nodes'].append(dict(p))
        w.doc['scenes'][0]['nodes'].append(len(w.doc['nodes']) - 1)
    w.save(os.path.join(folder, 'model.glb'))
    with open(os.path.join(folder, 'data.json'), 'w', newline='\n') as f:
        f.write(json.dumps({'$schema': '../map_model.schema.json', 'texture_set': texture_set, 'written': True,
                            'template': template}, indent=4) + '\n')
    bc.write_csv(os.path.join(folder, 'terrain_0.csv'), model.terrain)
    with open(os.path.join(folder, 'terrain_0_splits.csv'), 'w', newline='\n') as f:
        out = csv.DictWriter(f, fieldnames=['index', 'unused', 'slope0', 'slope1', 'offset0', 'offset1'],
                             lineterminator='\n')
        out.writeheader()
        out.writerows(model.splits)
    # Any other terrain layer, as the base has it
    for name in os.listdir(model.folder):
        if re.match(r'terrain_[1-9]', name):
            with open(os.path.join(model.folder, name), 'rb') as a, open(os.path.join(folder, name), 'wb') as b:
                b.write(a.read())
    bz.register('generated/map_models.txt', constant)
    return [img['uri'] for img in w.doc['images']]


def add_imports(texture_sets, uris):
    need = {}
    for uri in uris:
        parts = uri.split('/')
        if len(parts) >= 2 and parts[-1].endswith('.png'):
            need.setdefault(parts[-1][:-4], 'MAP_TEXTURE_SET_' + parts[-2].upper())
    for texture_set in texture_sets:
        folder = os.path.join(TEXTURES, stem(texture_set, 'MAP_TEXTURE_SET_'))
        if not os.path.isdir(folder):
            continue
        path = os.path.join(folder, 'imports.json')
        data = load(path) if os.path.exists(path) else {'$schema': '../texture_imports.schema.json', 'textures': []}
        have = {f[:-4] for f in os.listdir(folder) if f.endswith('.png')} | {t['texture'] for t in data['textures']}
        added = [{'texture': t, 'from': s} for t, s in sorted(need.items())
                 if t not in have and s != texture_set]
        if added:
            data['textures'] += added
            with open(path, 'w', newline='\n') as f:
                f.write(json.dumps(data, indent=4) + '\n')


# ---- Layered edits (geometry.js's eraseLayers, copyLayers, propOp) ---------------------------------------------------

LAYERS = ('ground', 'props', 'collision', 'class')
FLAGS_MASK = 0xffff0000
PROP_NAME = re.compile(r'bw2_prop_(\d+)_id_(\d+)')


def split_rect(r):
    """A rectangle of a matrix's tiles as its parts in each chunk: (cx, cz, global part, local part)."""
    parts = []
    cz = r[1] // 32
    while cz * 32 < r[3]:
        cx = r[0] // 32
        while cx * 32 < r[2]:
            x0, z0 = max(r[0], cx * 32), max(r[1], cz * 32)
            x1, z1 = min(r[2], cx * 32 + 32), min(r[3], cz * 32 + 32)
            if x0 < x1 and z0 < z1:
                parts.append((cx, cz, [x0, z0, x1, z1], [x0 - cx * 32, z0 - cz * 32, x1 - cx * 32, z1 - cz * 32]))
            cx += 1
        cz += 1
    return parts


def in_rect(x, z, r):
    return r[0] <= x < r[2] and r[1] <= z < r[3]


def nearest_walkable(model, rect):
    walkable = [r for r in model.terrain if not int(r['tile_type']) & bz.BLOCKED_TILE and r['shape'] == '0'
                and not in_rect(int(r['x']), int(r['z']), rect)]

    def near(x, z):
        best, best_d = None, 1e9
        for r in walkable:
            d = abs(int(r['x']) - x) + abs(int(r['z']) - z)
            if d < best_d:
                best, best_d = r, d
        return best
    return near


def ground_quad(model, material, x0, z0, x1, z1, y):
    m = next((i for i, (name, _, _) in enumerate(model.materials) if name == material), None)
    if m is None:
        return
    corners = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    verts = [c + (c[0] / 32, c[2] / 32, 254.0, 254.0, 254.0, 0.0, 1.0, 0.0) for c in corners]
    model.polys.setdefault(m, []).extend([[verts[0], verts[2], verts[1]], [verts[0], verts[3], verts[2]]])


def erase(model, rect, op):
    layers = op.get('layers') or LAYERS
    x0, z0, x1, z1 = units(rect)
    if 'ground' in layers:
        for m, polys in model.polys.items():
            model.polys[m] = [part for p in polys for part in bz.outside(p, x0, z0, x1, z1)]
        if op.get('ground'):
            ground_quad(model, op['ground'], x0, z0, x1, z1, float(op.get('groundY') or 0))
    if 'props' in layers:
        model.props = [p for p in model.props
                       if not (x0 <= p['translation'][0] < x1 and z0 <= p['translation'][2] < z1)]
    if not {'ground', 'collision', 'class'} & set(layers):
        return
    near = nearest_walkable(model, rect)
    for x in range(rect[0], rect[2]):
        for z in range(rect[1], rect[3]):
            cell = model.at(x, z)
            n = near(x, z)
            t = int(cell['tile_type'])
            if 'ground' in layers and n:
                cell.update({k: n[k] for k in ('shape', 'slope', 'offset', 'diagonal')})
            if 'collision' in layers and 'class' in layers:
                if n:
                    t = int(n['tile_type'])
            elif 'collision' in layers:
                t &= ~bz.BLOCKED_TILE
            elif 'class' in layers and n:
                t = (t & FLAGS_MASK) | (int(n['tile_type']) & 0xffff)
            cell['tile_type'] = str(t & 0xffffffff)


def copy_piece(model, src, rect, to, layers):
    """copyLayers for one rectangle of a source chunk (already a copy) to tile `to` of this one."""
    sx0, sz0, sx1, sz1 = units(rect)
    dx, dz = (to[0] - rect[0]) * TILE, (to[1] - rect[1]) * TILE
    x0, z0, x1, z1 = sx0 + dx, sz0 + dz, sx1 + dx, sz1 + dz
    if 'ground' in layers:
        for m, polys in model.polys.items():
            model.polys[m] = [part for p in polys for part in bz.outside(p, x0, z0, x1, z1)]
        for sm, polys in sorted(src.polys.items()):
            name, material, uri = src.materials[sm]
            moved = []
            for p in polys:
                q = inside(p, sx0, sz0, sx1, sz1)
                if q:
                    moved.append([(v[0] + dx, v[1], v[2] + dz) + tuple(v[3:]) for v in q])
            if moved:
                model.polys.setdefault(model.material(material, uri), []).extend(moved)
    if 'props' in layers:
        model.props = [p for p in model.props
                       if not (x0 <= p['translation'][0] < x1 and z0 <= p['translation'][2] < z1)]
        for p in src.props:
            x, y, z = p['translation']
            if sx0 <= x < sx1 and sz0 <= z < sz1:
                model.props.append(dict(p, translation=[x + dx, y, z + dz]))
    for x in range(rect[0], rect[2]):
        for z in range(rect[1], rect[3]):
            tx, tz = to[0] + x - rect[0], to[1] + z - rect[1]
            if not (0 <= tx < 32 and 0 <= tz < 32):
                continue
            s = src.at(x, z)
            d = model.at(tx, tz)
            t = int(d['tile_type'])
            if 'ground' in layers:
                d.update({k: s[k] for k in ('shape', 'slope', 'offset', 'diagonal')})
                if s['shape'] != '0' and int(s['offset']) < len(src.splits):
                    split = dict(src.splits[int(s['offset'])])
                    split['index'] = str(len(model.splits))
                    model.splits.append(split)
                    d['offset'] = split['index']
            if 'collision' in layers:
                t = (t & 0xffff) | (int(s['tile_type']) & FLAGS_MASK)
            if 'class' in layers:
                t = (t & FLAGS_MASK) | (int(s['tile_type']) & 0xffff)
            d['tile_type'] = str(t & 0xffffffff)


def round_to(v, n):
    return math.floor(v * n + 0.5) / n


def prop_key(res_id, translation, rotation):
    return (res_id, tuple(round_to(v, 1000) for v in translation), tuple(round_to(v, 10000) for v in rotation))


def node_key(p):
    return prop_key(int(PROP_NAME.match(p['name']).group(2)), p.get('translation', [0, 0, 0]),
                    p.get('rotation', [0, 0, 0, 1]))


def prop(model, op):
    at = None
    if op.get('match'):
        key = prop_key(op['match']['resId'], op['match']['translation'], op['match']['rotation'])
        at = next((i for i, p in enumerate(model.props) if node_key(p) == key), None)
    value = op.get('value')
    node = value and {'name': 'bw2_prop_0000_id_%05d' % value['resId'], 'translation': list(value['translation']),
                      'rotation': list(value['rotation']), 'scale': list(value.get('scale') or [1, 1, 1])}
    if op['action'] == 'add':
        model.props.append(node)
    elif at is not None and op['action'] == 'set':
        model.props[at] = node
    elif at is not None and op['action'] == 'delete':
        del model.props[at]


# ---- Locks -------------------------------------------------------------------------------------------------------

LOCKS = os.path.join(here, 'world_locks.json')
efu_h = open(os.path.join(root, 'include', 'efu.h')).read()
LOCK_COUNT = int(re.search(r'#define EFU_LOCK_COUNT (\d+)', efu_h).group(1))
LOCK_SCRIPT = 11000 + int(re.search(r'#define EFU_SCRIPT_LOCK_FIRST \(EFU_SCRIPT_FIRST \+ (\d+)\)', efu_h).group(1))


def is_lock_sign(bg):
    return LOCK_SCRIPT <= bg.get('script', 0) < LOCK_SCRIPT + LOCK_COUNT


def strip_locks(files, zones):
    """Takes the locks off the zones' warps and their signs away, as a run before this one left them."""
    for zone in zones:
        if not os.path.exists(os.path.join(RES, 'events', stem(zone, 'ZONE_') + '.json')):
            continue
        e = files.events(zone)
        for w in e.get('warps', []):
            if isinstance(w.get('grid'), dict) and w['grid'].get('unk0a'):
                w['grid']['unk0a'] = 0
        e['bg_events'] = [b for b in e.get('bg_events', []) if not is_lock_sign(b)]


def apply_locks(files, locks, notes):
    registry = load(LOCKS)['locks'] if os.path.exists(LOCKS) else []
    number = {(r['zone'], r['x'], r['z']): i for i, r in enumerate(registry)}
    for r in registry:
        r['unused'] = True
    for (zone, x, z), lock in locks.items():
        if not lock.get('locked', True):
            continue
        e = files.events(zone)
        warp = next((w for w in e.get('warps', []) if w['grid']['x'] == x and w['grid']['z'] == z), None)
        if warp is None:
            notes.append('skipped: a lock on %s at %d, %d, where there is no warp' % (zone, x, z))
            continue
        i = number.get((zone, x, z))
        if i is None:
            i = number[(zone, x, z)] = len(registry)
            registry.append({})
        if i >= LOCK_COUNT:
            sys.exit('more than EFU_LOCK_COUNT (%d) locks: raise it in include/efu.h' % LOCK_COUNT)
        registry[i] = {'zone': zone, 'x': x, 'z': z, 'item': lock.get('item') or None,
                       'consume': bool(lock.get('consume')), 'relock': bool(lock.get('relock'))}
        warp['grid']['unk0a'] = i + 1
        e.setdefault('bg_events', []).append({'script': LOCK_SCRIPT + i, 'condition': 0, 'direction': 4,
                                              'grid': {'x': x // 16, 'y': z // 16, 'z': warp['grid']['y']}})
    with open(LOCKS, 'w', newline='\n') as f:
        f.write('{\n"locks": [\n' + ',\n'.join(json.dumps(r) for r in registry) + '\n]\n}\n')
    return registry


# ---- The run -----------------------------------------------------------------------------------------------------

def edit_constant(matrix_name, x, z):
    return 'MAP_MODEL_EFU_EDIT_%s_%d_%d' % (matrix_name[len('MAP_MATRIX_'):].removeprefix('EFU_'), x, z)


def main():
    if not os.path.exists(EDITS):
        print('no world_edits.json: nothing to apply')
        return
    ops = load(EDITS).get('ops', [])
    bases = load(BASES) if os.path.exists(BASES) else {}
    files = Files()
    notes = []
    states = {}     # (matrix, x, z) -> Model, as the edits so far leave it
    dirty = set()   # the chunks whose models are written
    base_of = {}    # (matrix, x, z) -> the model it starts from

    def model_at(matrix_name, x, z):
        cell = (matrix_name, x, z)
        if cell not in states:
            current = files.matrix(matrix_name)['maps'][z][x]
            key = '%s,%d,%d' % cell
            if current == edit_constant(*cell):
                current = bases.get(key)
                if not current:
                    sys.exit('%s: no base model recorded for %s' % (key, edit_constant(*cell)))
            base_of[cell] = current
            states[cell] = Model(current)
        return states[cell]

    # Locks come off first, so that the events match as the editor shows them
    registry = load(LOCKS)['locks'] if os.path.exists(LOCKS) else []
    strip_locks(files, sorted({r['zone'] for r in registry} | {op['zone'] for op in ops if op['op'] == 'lock'}))
    locks = {}
    sources = {}
    for op in ops:
        kind = op['op']
        if kind == 'event':
            apply_event(files, op, notes)
        elif kind == 'lock':
            locks[(op['zone'], op['x'], op['z'])] = op
        elif kind == 'matrix':
            m = files.matrix(op['matrix'])
            cell = (op['matrix'], op['x'], op['z'])
            if op.get('model'):
                m['maps'][op['z']][op['x']] = op['model']
                states.pop(cell, None)
                dirty.discard(cell)
                base_of.pop(cell, None)
                bases.pop('%s,%d,%d' % cell, None)
            if op.get('zone') and m.get('zones'):
                m['zones'][op['z']][op['x']] = op['zone']
        elif kind in ('cut', 'stamp', 'tiles', 'prop'):
            cell = (op['matrix'], op['x'], op['z'])
            model = model_at(*cell)
            if kind == 'stamp':
                # Older files: a stamp copies its source as it was before any edit
                src = op['from']
                for key, base in bases.items():
                    if edit_constant(key.split(',')[0], *map(int, key.split(',')[1:])) == src:
                        src = base
                stamp(model, dict(op, **{'from': src}), sources)
            else:
                {'cut': cut, 'tiles': tiles, 'prop': prop}[kind](model, op)
            dirty.add(cell)
        elif kind == 'erase':
            for cx, cz, _, local in split_rect(op['rect']):
                m = files.matrix(op['matrix'])
                if not (0 <= cz < len(m['maps']) and 0 <= cx < len(m['maps'][cz]) and m['maps'][cz][cx]):
                    continue
                erase(model_at(op['matrix'], cx, cz), local, op)
                dirty.add((op['matrix'], cx, cz))
        elif kind == 'copy':
            layers = op.get('layers') or LAYERS
            src_m = files.matrix(op['from']['matrix'])
            r = op['from']['rect']
            snaps = {}
            for cx, cz, _, _ in split_rect(r):
                if 0 <= cz < len(src_m['maps']) and 0 <= cx < len(src_m['maps'][cz]) and src_m['maps'][cz][cx]:
                    snaps[(cx, cz)] = copy.deepcopy(model_at(op['from']['matrix'], cx, cz))
            dst_m = files.matrix(op['matrix'])
            for to in op['to']:
                for cx, cz, part, local in split_rect(r):
                    src = snaps.get((cx, cz))
                    if not src:
                        continue
                    gx, gz = to[0] + part[0] - r[0], to[1] + part[1] - r[1]
                    w, h = part[2] - part[0], part[3] - part[1]
                    for dcx, dcz, dpart, dlocal in split_rect([gx, gz, gx + w, gz + h]):
                        if not (0 <= dcz < len(dst_m['maps']) and 0 <= dcx < len(dst_m['maps'][dcz])
                                and dst_m['maps'][dcz][dcx]):
                            continue
                        ox, oz = dpart[0] - gx, dpart[1] - gz
                        srect = [local[0] + ox, local[1] + oz, local[0] + ox + dpart[2] - dpart[0],
                                 local[1] + oz + dpart[3] - dpart[1]]
                        copy_piece(model_at(op['matrix'], dcx, dcz), src, srect, dlocal[:2], layers)
                        dirty.add((op['matrix'], dcx, dcz))
        else:
            sys.exit('unknown edit %r' % kind)
    for cell in sorted(dirty):
        matrix_name, x, z = cell
        m = files.matrix(matrix_name)
        key = '%s,%d,%d' % cell
        constant = edit_constant(*cell)
        model = states[cell]
        bases[key] = base_of[cell]
        for i, p in enumerate(model.props):
            p['name'] = 'bw2_prop_%04d_id_%s' % (i, PROP_NAME.match(p['name']).group(2))
        zone = cell_zone(files, matrix_name, x, z)
        area = zone_area(zone) if zone else None
        sets = season_sets(area) if area else []
        texture_set = model.data.get('texture_set') or (sets[0] if sets else None)
        if not texture_set:
            sys.exit('%s: no texture set for the edited chunk (zone %s)' % (key, zone))
        template = model.data.get('template') or base_of[cell]
        uris = write_model(model, constant, texture_set, template)
        add_imports(sets or [texture_set], uris)
        m['maps'][z][x] = constant
    # Chunks edited before whose edits are gone go back to their base
    for key, base in list(bases.items()):
        matrix_name, x, z = key.split(',')
        cell = (matrix_name, int(x), int(z))
        if cell in dirty:
            continue
        m = files.matrix(matrix_name)
        if m['maps'][cell[2]][cell[1]] == edit_constant(*cell):
            m['maps'][cell[2]][cell[1]] = base
        del bases[key]
    apply_locks(files, locks, notes)
    files.save()
    with open(BASES, 'w', newline='\n') as f:
        f.write(json.dumps(bases, indent=4, sort_keys=True) + '\n')
    for n in notes:
        print(n)
    print('applied %d edits: %d chunks rebuilt, %d locks' % (len(ops), len(dirty),
                                                             sum(1 for v in locks.values() if v.get('locked', True))))


if __name__ == '__main__':
    main()
