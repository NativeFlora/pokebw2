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
- {"op": "event", "zone", "kind", "action": "add" | "set" | "delete", "match"?, "value"?}: a zone's NPC, warp,
  trigger or background event, found by all of its fields (match). A set or delete whose match isn't there is taken as
  done already and skipped (with a note, so that a change by build_raid.py to the same event shows).

A chunk with edits gets its own model, efu_edit_<matrix less EFU_>_<x>_<z> (MAP_MODEL_EFU_EDIT_*), rebuilt each run from its base
(the model the matrix had there before; recorded in world_edit_bases.json for runs after the first), written whole
like build_zone.py's copies, with its area's texture sets importing any texture its geometry names that they lack.
"""
import csv
import json
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
    if op['action'] == 'add':
        if any(canon(o) == canon(op['value']) for o in items):
            return
        items.append(op['value'])
        return
    key = canon(op['match'])
    at = next((i for i, o in enumerate(items) if canon(o) == key), None)
    if at is None:
        if op['action'] == 'set' and any(canon(o) == canon(op['value']) for o in items):
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


def main():
    if not os.path.exists(EDITS):
        print('no world_edits.json: nothing to apply')
        return
    ops = load(EDITS).get('ops', [])
    bases = load(BASES) if os.path.exists(BASES) else {}
    files = Files()
    notes = []
    cell_ops = {}
    for op in ops:
        kind = op['op']
        if kind == 'event':
            apply_event(files, op, notes)
        elif kind == 'matrix':
            m = files.matrix(op['matrix'])
            if op.get('model'):
                m['maps'][op['z']][op['x']] = op['model']
                cell_ops.pop((op['matrix'], op['x'], op['z']), None)
                bases.pop('%s,%d,%d' % (op['matrix'], op['x'], op['z']), None)
            if op.get('zone') and m.get('zones'):
                m['zones'][op['z']][op['x']] = op['zone']
        elif kind in ('cut', 'stamp', 'tiles'):
            cell_ops.setdefault((op['matrix'], op['x'], op['z']), []).append(op)
        else:
            sys.exit('unknown edit %r' % kind)
    # A stamp copies its source as it is before any edit (the editor copies an edited chunk's base)
    edited = {'MAP_MODEL_EFU_EDIT_%s_%s_%s' % (k.split(',')[0][len('MAP_MATRIX_'):].removeprefix('EFU_'),
                                              *k.split(',')[1:]): v for k, v in bases.items()}
    for cops in cell_ops.values():
        for op in cops:
            if op['op'] == 'stamp' and op['from'] in edited:
                op['from'] = edited[op['from']]
    sources = {}
    for (matrix_name, x, z), cops in cell_ops.items():
        m = files.matrix(matrix_name)
        key = '%s,%d,%d' % (matrix_name, x, z)
        constant = 'MAP_MODEL_EFU_EDIT_%s_%d_%d' % (matrix_name[len('MAP_MATRIX_'):].removeprefix('EFU_'), x, z)
        current = m['maps'][z][x]
        base = bases.get(key) if current == constant else current
        if not base:
            sys.exit('%s: no base model recorded for %s' % (key, constant))
        bases[key] = base
        model = Model(base)
        for op in cops:
            if op['op'] == 'stamp':
                stamp(model, op, sources)
            else:
                (cut if op['op'] == 'cut' else tiles)(model, op)
        zone = cell_zone(files, matrix_name, x, z)
        area = zone_area(zone) if zone else None
        sets = season_sets(area) if area else []
        texture_set = model.data.get('texture_set') or (sets[0] if sets else None)
        if not texture_set:
            sys.exit('%s: no texture set for the edited chunk (zone %s)' % (key, zone))
        template = model.data.get('template') or base
        uris = write_model(model, constant, texture_set, template)
        add_imports(sets or [texture_set], uris)
        m['maps'][z][x] = constant
    # Chunks edited before whose edits are gone go back to their base
    for key, base in list(bases.items()):
        matrix_name, x, z = key.split(',')
        x, z = int(x), int(z)
        if (matrix_name, x, z) in cell_ops:
            continue
        m = files.matrix(matrix_name)
        if m['maps'][z][x].startswith('MAP_MODEL_EFU_EDIT_'):
            m['maps'][z][x] = base
        del bases[key]
    files.save()
    with open(BASES, 'w', newline='\n') as f:
        f.write(json.dumps(bases, indent=4, sort_keys=True) + '\n')
    for n in notes:
        print(n)
    print('applied %d edits: %d chunks rebuilt' % (len(ops), len(cell_ops)))


if __name__ == '__main__':
    main()
