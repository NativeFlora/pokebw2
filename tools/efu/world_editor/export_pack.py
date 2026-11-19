#!/usr/bin/env python3
"""Escape from Unova: export the world editor with the maps it edits.

    python3 tools/efu/world_editor/export_pack.py [OUT_DIR] [--matrix MAP_MATRIX_X ...] [--no-overworld]

Writes OUT_DIR (default build/world_editor): index.html and editor.js (web/, built by web/build.sh), and pack/, the
data as classic scripts so the editor runs from a plain folder (file://) in Chrome or Edge, with nothing to install:

- pack/index.js: the matrices, every zone's header and events, the areas, the constant lists the editor offers, and
  tools/efu/world_edits.json, so the editor opens on the edits already made;
- pack/models/<model>.js: a map model's GLB and terrain, loaded when a matrix shows it;
- pack/textures/<n>.js and pack/props/<bundle>.js: the textures the models name and the field props they place;
- pack/actors.js: the first frame of each NPC model's sprite.

The maps exported are the hack's matrices (MAP_MATRIX_EFU_*), the matrices of every zone their warps lead to, and,
unless --no-overworld, the overworld's chunks as sources for the stamp tool. The editor saves world_edits.json, which
apply_world_edits.py applies to res/.
"""
import argparse
import base64
import csv
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'data'))
from gen_constants import load as load_constants  # noqa: E402

RES = ROOT / 'res' / 'field'
MODELS = RES / 'maps' / 'models'
EDITS = ROOT / 'tools' / 'efu' / 'world_edits.json'
BASES = ROOT / 'tools' / 'efu' / 'world_edit_bases.json'


def stem(constant, prefix):
    return constant[len(prefix):].lower()


def read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def glb_doc(data):
    n = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20 + n])


def b64(data):
    return base64.b64encode(data).decode('ascii')


def js(call, *args):
    return 'EFU.%s(%s);\n' % (call, ', '.join(json.dumps(a, separators=(',', ':')) for a in args))


def terrain(folder):
    layers = []
    for n in range(4):
        path = folder / ('terrain_%d.csv' % n)
        if not path.exists():
            break
        rows = list(csv.DictReader(open(path, newline='')))
        if 'shape' not in rows[0]:
            break  # RD chunks store planes, not table indices: shown without terrain
        width = max(int(r['x']) for r in rows) + 1
        height = max(int(r['z']) for r in rows) + 1
        cells = [None] * (width * height)
        for r in rows:
            cells[int(r['z']) * width + int(r['x'])] = [int(r[k]) for k in
                                                         ('shape', 'slope', 'offset', 'tile_type', 'diagonal')]
        splits_path = folder / ('terrain_%d_splits.csv' % n)
        splits = [[int(r[k]) for k in ('slope0', 'slope1', 'offset0', 'offset1')]
                  for r in csv.DictReader(open(splits_path, newline=''))] if splits_path.exists() else []
        layers.append({'width': width, 'height': height, 'cells': cells, 'splits': splits})
    return layers


def resolve(base, uri):
    return os.path.normpath(os.path.join(base, uri)).replace(os.sep, '/')


def heights():
    """The terrain's height tables, from field_map_chunk_height.c, so the editor can place markers on the ground."""
    s = (ROOT / 'src/ov036/field_map_chunk_height.c').read_text()

    def table(name):
        i = s.index(name + '[] = {')
        return [int(v, 0) for v in re.findall(r'-?0x[0-9a-fA-F]+|-?\d+', s[i + len(name) + 6:s.index('};', i)])]
    return {'slopes': table('MAP_HEIGHT_SLOPE_TABLE'), 'offsets': table('MAP_HEIGHT_OFFSET_TABLE')}


def efu_script_names():
    names = {}
    for m in re.finditer(r'#define (EFU_SCRIPT_\w+) \(EFU_SCRIPT_FIRST \+ (\d+)\)', (ROOT / 'include/efu.h').read_text()):
        names[11000 + int(m.group(2))] = m.group(1)
    return names


def tile_classes():
    """The tile classes' names, from include/field/field_map.h, for the class brush."""
    s = (ROOT / 'include/field/field_map.h').read_text()
    return {int(v, 16): n[len('TILE_CLASS_'):] for n, v in re.findall(r'(TILE_CLASS_\w+) = (0x[0-9a-f]+)', s)}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('out', nargs='?', default=str(ROOT / 'build' / 'world_editor'))
    ap.add_argument('--matrix', action='append', default=[], help='also export this matrix')
    ap.add_argument('--no-overworld', action='store_true', help="leave out the overworld's chunks")
    ap.add_argument('--no-apply', action='store_true', help="don't apply world_edits.json to res/ first")
    args = ap.parse_args()
    if not args.no_apply:
        # The pack shows res/ with the edits saved so far, which the editor adds its new edits to
        subprocess.run([sys.executable, str(ROOT / 'tools' / 'efu' / 'apply_world_edits.py')], check=True,
                       cwd=str(ROOT / 'tools' / 'efu'))
    out = Path(args.out)
    pack = out / 'pack'
    if pack.exists():
        shutil.rmtree(pack)
    for d in ('models', 'textures', 'props'):
        (pack / d).mkdir(parents=True)

    bases = read_json(BASES) if BASES.exists() else {}
    matrix_names = list(load_constants('map_matrices'))
    zone_names = list(load_constants('zones'))
    model_names = list(load_constants('map_models'))

    zones = {}
    for z in zone_names:
        path = RES / 'zones' / (stem(z, 'ZONE_') + '.json')
        if not path.exists() or z in zones:
            continue
        ev = RES / 'events' / (stem(z, 'ZONE_') + '.json')
        zones[z] = {'header': read_json(path), 'events': read_json(ev) if ev.exists() else None}

    # The matrices: the hack's, then those its zones' warps lead to, then those zones' warps, and so on
    wanted = [m for m in matrix_names if m.startswith('MAP_MATRIX_EFU_')] + args.matrix
    seen = set()
    queue = list(wanted)
    matrices = {}
    while queue:
        m = queue.pop(0)
        if m in seen:
            continue
        seen.add(m)
        path = RES / 'matrices' / (stem(m, 'MAP_MATRIX_') + '.json')
        if not path.exists():
            continue
        data = read_json(path)
        matrices[m] = {'maps': data['maps'], 'zones': data.get('zones')}
        if m in ('MAP_MATRIX_OVERWORLD', 'MAP_MATRIX_OVERWORLD_2'):
            continue
        in_matrix = {z for row in (data.get('zones') or []) for z in row} | \
            {z for z, v in zones.items() if v['header'].get('matrix') == m}
        for z in sorted(in_matrix):
            ev = zones.get(z, {}).get('events')
            for w in (ev or {}).get('warps', []):
                dest = zones.get(w['zone']) if isinstance(w['zone'], str) else None
                if dest and dest['header'].get('matrix') not in seen:
                    queue.append(dest['header']['matrix'])
    if not args.no_overworld:
        data = read_json(RES / 'matrices' / 'overworld_2.json')
        matrices['MAP_MATRIX_OVERWORLD_2'] = {'maps': data['maps'], 'zones': data.get('zones'), 'source_only': True}

    areas = {}
    for a in load_constants('areas'):
        path = RES / 'areas' / (stem(a, 'AREA_') + '.json')
        if path.exists():
            d = read_json(path)
            areas[a] = {k: d.get(k) for k in ('texture_set', 'prop_bundle', 'exterior')}

    # The models the matrices name, with their textures and props
    used_models = sorted({c for m in matrices.values() for row in m['maps'] for c in row if c})
    texture_keys = {}   # key -> file
    prop_bundles = {}   # (exterior?, bundle folder) -> res_ids
    models = {}
    for c in used_models:
        folder = MODELS / stem(c, 'MAP_MODEL_')
        if not (folder / 'model.glb').exists():
            continue
        glb = (folder / 'model.glb').read_bytes()
        doc = glb_doc(glb)
        base = 'map/models/' + folder.name
        for image in doc.get('images', []):
            if 'uri' in image:
                key = resolve(base, image['uri'])
                texture_keys[key] = (MODELS / folder.name / image['uri']).resolve()
        data = read_json(folder / 'data.json')
        (pack / 'models' / (folder.name + '.js')).write_text(
            js('model', c, {'glb': b64(glb), 'terrain': terrain(folder), 'data': data}))
        models[c] = {'folder': folder.name, 'size': len(glb),
                     'props': sorted({int(m.group(2)) for n in doc['nodes']
                                      for m in [re.match(r'bw2_prop_(\d+)_id_(\d+)', n.get('name', ''))] if m})}

    # Which prop bundles to export: each matrix's zones' areas'
    for name, m in matrices.items():
        mz = {z for row in (m['zones'] or []) for z in row} | {z for z, v in zones.items()
                                                                 if v['header'].get('matrix') == name}
        for z in mz:
            area = areas.get(zones.get(z, {}).get('header', {}).get('area'))
            if area and area.get('prop_bundle'):
                kind = 'exterior' if area['exterior'] else 'interior'
                prefix = 'FIELD_PROPS_%s_' % kind.upper()
                if area['prop_bundle'].startswith(prefix):
                    prop_bundles.setdefault((kind, stem(area['prop_bundle'], prefix)), area['prop_bundle'])
    used_props = {r for m in models.values() for r in m['props']}
    props = {}
    for (kind, bundle), constant in sorted(prop_bundles.items()):
        root = RES / 'props' / kind / 'models' / bundle
        if not root.exists():
            continue
        entries = {}
        for d in sorted(root.iterdir()):
            if not (d / 'model.glb').exists():
                continue
            res_id = read_json(d / 'data.json')['res_id']
            if res_id not in used_props:
                continue
            glb = (d / 'model.glb').read_bytes()
            doc = glb_doc(glb)
            base = 'prop/%s/models/%s/%s' % (kind, bundle, d.name)
            for image in doc.get('images', []):
                if 'uri' in image:
                    texture_keys[resolve(base, image['uri'])] = (d / image['uri']).resolve()
            entries[res_id] = {'name': d.name, 'glb': b64(glb), 'base': base}
        (pack / 'props' / (constant + '.js')).write_text(js('props', constant, entries))
        props[constant] = True

    # Textures, in files of about 4 MB
    chunks, current, size = [], {}, 0
    for key, path in sorted(texture_keys.items()):
        if not path.exists():
            continue
        data = path.read_bytes()
        current[key] = 'data:image/png;base64,' + b64(data)
        size += len(data)
        if size > 3 << 20:
            chunks.append(current)
            current, size = {}, 0
    if current:
        chunks.append(current)
    texture_files = {}
    for i, c in enumerate(chunks):
        (pack / 'textures' / ('%d.js' % i)).write_text(js('textures', c))
        for key in c:
            texture_files[key] = i

    # NPC sprites: the first square frame of each actor's sheet
    used_codes = set()
    for v in zones.values():
        for n in (v['events'] or {}).get('npcs', []):
            used_codes.add(n['model'])
    obj_codes = load_constants('obj_codes')
    sprites = {}
    for code in sorted(used_codes, key=str):
        value = obj_codes.get(code, code) if isinstance(code, str) else code
        png = RES / 'actors' / str(value) / 'sprite.png'
        if png.exists():
            sprites[str(code)] = 'data:image/png;base64,' + b64(png.read_bytes())
    (pack / 'actors.js').write_text(js('sprites', sprites))

    index = {
        'matrices': matrices,
        'zones': zones,
        'areas': areas,
        'models': models,
        'props': props,
        'textures': texture_files,
        'heights': heights(),
        'constants': {
            'zones': zone_names,
            'map_models': model_names,
            'obj_codes': list(obj_codes),
            'move_codes': list(load_constants('move_codes')),
            'actor_event_types': list(load_constants('actor_event_types')),
            'tile_classes': {str(k): v for k, v in tile_classes().items()},
            'scripts': {str(k): v for k, v in efu_script_names().items()},
        },
        'edits': read_json(EDITS) if EDITS.exists() else None,
        # Each edited chunk's model's base, which stamps copy from (apply_world_edits.py)
        'bases': {'MAP_MODEL_EFU_EDIT_%s_%s_%s' % (k.split(',')[0][len('MAP_MATRIX_'):].removeprefix('EFU_'),
                                                    *k.split(',')[1:]): v for k, v in bases.items()},
    }
    (pack / 'index.js').write_text(js('index', index))
    for src in (HERE / 'web' / 'index.html', HERE / 'web' / 'editor.js', HERE / 'README.md'):
        shutil.copy(src, out / src.name)
    total = sum(p.stat().st_size for p in pack.rglob('*') if p.is_file())
    print('%s: %d matrices, %d models, %d textures, %d prop bundles, %.1f MB' %
          (out, len(matrices), len(models), len(texture_keys), len(props), total / 1e6))


if __name__ == '__main__':
    main()
