"""Escape from Unova: every warp of the hack's zones (the base, the exploration zone and what their warps lead into),
checked against its map's collision: the warp's tiles and the free tiles next to them, which must be in one walkable
area with the zone's other warps, in a chunk the matrix gives the zone."""
import json, csv, os, sys
from collections import deque
R = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'res/field/')
START = ['ZONE_NACRENE_CITY_8', 'ZONE_NACRENE_CITY', 'ZONE_ROUTE_3', 'ZONE_ROUTE_2']
EFU_MATRICES = {'efu_home', 'efu_nacrene', 'efu_zone_1', 'efu_zone_2'}

def jload(p):
    return json.load(open(p)) if os.path.exists(p) else None

tcache = {}
def tiles(model):
    if model not in tcache:
        d = R + 'maps/models/' + model[10:].lower()
        layers = [{(int(r['x']), int(r['z'])): int(r['tile_type']) for r in csv.DictReader(open(d + '/terrain_%d.csv' % n))}
                  for n in (0, 1) if os.path.exists(d + '/terrain_%d.csv' % n)]
        # A tile is free when either layer lets the player through (bridges are on the second)
        tcache[model] = {k: min(l[k] & 0x10000 for l in layers) for k in layers[0]} if layers else None
    return tcache[model]

def zone_info(zone):
    z = jload(R + 'zones/' + zone[5:].lower() + '.json')
    ev = jload(R + 'events/' + zone[5:].lower() + '.json')
    if not z or not ev: return None
    mname = z['matrix'][len('MAP_MATRIX_'):].lower()
    m = jload(R + 'matrices/' + mname + '.json')
    return z, ev, mname, m

# The zones: the starts, then whatever their warps lead into, staying within EFU matrices plus one step out
zones, q = {}, deque((s, 0) for s in START)
while q:
    zone, d = q.popleft()
    if zone in zones: continue
    info = zone_info(zone)
    if not info: zones[zone] = None; continue
    zones[zone] = info
    inside = info[2] in EFU_MATRICES
    for w in info[1].get('warps', []):
        if inside or d < 2:
            q.append((w['zone'], d if inside else d + 1))

def blocked(m, x, z):
    if x < 0 or z < 0 or z // 32 >= len(m['maps']) or x // 32 >= len(m['maps'][0]): return True
    model = m['maps'][z // 32][x // 32]
    if not model or 'OUTTREE' in model or 'OUTSEA' in model: return True
    t = tiles(model)
    if t is None: return True
    return bool(t[(x % 32, z % 32)])

def owner(m, x, z):
    zs = m.get('zones')
    return zs[z // 32][x // 32] if zs else None

problems = 0
for zone, info in zones.items():
    if not info: continue
    z, ev, mname, m = info
    warps = ev.get('warps', [])
    if not warps: continue
    # Each warp's tiles and the free tiles around them
    rects, starts = [], []
    for i, w in enumerate(warps):
        g = w['grid']
        x0, z0 = g['x'] // 16, g['z'] // 16
        rect = [(x0 + dx, z0 + dz) for dx in range(g['width']) for dz in range(g['height'])]
        near = {(x + ax, zz + az) for x, zz in rect for ax, az in ((1, 0), (-1, 0), (0, 1), (0, -1))} - set(rect)
        free_near = [p for p in near if not blocked(m, *p)]
        free_on = [p for p in rect if not blocked(m, *p)]
        rects.append((i, w, rect, free_on, free_near))
    # Walkable areas: flood fill from each warp's free tiles
    comp = {}
    def fill(p, cid):
        dq = deque([p]); comp[p] = cid
        while dq:
            x, zz = dq.popleft()
            for ax, az in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + ax, zz + az)
                if n not in comp and not blocked(m, *n):
                    comp[n] = cid; dq.append(n)
    cid = 0
    wcomp = []
    for i, w, rect, on, near in rects:
        cs = set()
        for p in on + near:
            if p not in comp:
                cid += 1; fill(p, cid)
            cs.add(comp[p])
        wcomp.append(cs)
    sizes = {}
    for c in comp.values(): sizes[c] = sizes.get(c, 0) + 1
    main = max(sizes, key=sizes.get) if sizes else None
    for (i, w, rect, on, near), cs in zip(rects, wcomp):
        # A warp moved to the map's corner is one the hack shut (build_base.py's closed doors)
        if rect[0] == (0, 0):
            continue
        issues = []
        own = {owner(m, *p) for p in rect}
        if m.get('zones') and own != {zone}: issues.append('chunk belongs to %s' % sorted(map(str, own)))
        if not on and not near: issues.append('walled in: no free tile on or next to it')
        elif main not in cs and len(sizes) > 1:
            issues.append('cut off: its walkable area has %d tiles, the main one %d' % (max(sizes[c] for c in cs), sizes[main]))
        if issues:
            problems += 1
            print('%-28s warp %d -> %s %d at %s (%dx%d): %s' % (zone[5:], i, w['zone'][5:], w['warp'], rect[0],
                  w['grid']['width'], w['grid']['height'], '; '.join(issues)))
print('%d zones checked, %d warps with problems' % (sum(1 for v in zones.values() if v), problems))
