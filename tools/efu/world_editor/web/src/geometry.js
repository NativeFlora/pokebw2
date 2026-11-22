// A map chunk's geometry as the editor and apply_world_edits.py see it: triangles by material, in the chunk's own
// coordinates (x and z from -256 to 256, 16 units a tile), and the cut and stamp operations, done the same way in
// both (Sutherland-Hodgman against the rectangle's sides, as build_zone.py cuts paths).

export const TILE = 16;
export const HALF = 256;

const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
const ARRAYS = { 5120: Int8Array, 5121: Uint8Array, 5122: Int16Array, 5123: Uint16Array, 5125: Uint32Array, 5126: Float32Array };
const NORMALIZE = { 5120: 127, 5121: 255, 5122: 32767, 5123: 65535 };

export function parseGlb(buffer) {
    const view = new DataView(buffer);
    const jsonLength = view.getUint32(12, true);
    const doc = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, 20, jsonLength)));
    const binOffset = 20 + jsonLength;
    const binLength = view.getUint32(binOffset, true);
    return { doc, bin: buffer.slice(binOffset + 8, binOffset + 8 + binLength) };
}

function accessor(doc, bin, index) {
    const a = doc.accessors[index];
    const bv = doc.bufferViews[a.bufferView];
    const n = COMPONENTS[a.type];
    const Type = ARRAYS[a.componentType];
    const size = Type.BYTES_PER_ELEMENT;
    const stride = bv.byteStride || size * n;
    const start = (bv.byteOffset || 0) + (a.byteOffset || 0);
    const dv = new DataView(bin);
    const out = [];
    const get = {
        5120: (o) => dv.getInt8(o), 5121: (o) => dv.getUint8(o), 5122: (o) => dv.getInt16(o, true),
        5123: (o) => dv.getUint16(o, true), 5125: (o) => dv.getUint32(o, true), 5126: (o) => dv.getFloat32(o, true),
    }[a.componentType];
    for (let i = 0; i < a.count; i++) {
        const v = [];
        for (let k = 0; k < n; k++) v.push(get(start + i * stride + k * size));
        out.push(v);
    }
    return { values: out, normalized: !!a.normalized, componentType: a.componentType };
}

// The chunk's materials (name, image uri, alpha mode, wrap) and triangles: each vertex is
// [x, y, z, u, v, r, g, b] with the colour from 0 to 255, as the GLB stores it
export function chunkGeometry(doc, bin) {
    const materials = doc.materials.map((m) => {
        const binding = m.pbrMetallicRoughness && m.pbrMetallicRoughness.baseColorTexture;
        let uri = null, sampler = null;
        if (binding && doc.textures[binding.index]) {
            const t = doc.textures[binding.index];
            uri = doc.images[t.source].uri;
            sampler = t.sampler !== undefined && doc.samplers ? doc.samplers[t.sampler] : null;
        }
        return { name: m.name, uri, alphaMode: m.alphaMode || 'OPAQUE', doubleSided: !!m.doubleSided, sampler, raw: m };
    });
    const prims = [];
    const meshNode = doc.nodes.find((n) => n.mesh !== undefined);
    if (meshNode) {
        for (const prim of doc.meshes[meshNode.mesh].primitives) {
            const att = prim.attributes;
            const pos = accessor(doc, bin, att.POSITION).values;
            const uv = att.TEXCOORD_0 !== undefined ? accessor(doc, bin, att.TEXCOORD_0).values : pos.map(() => [0, 0]);
            let col = pos.map(() => [255, 255, 255]);
            if (att.COLOR_0 !== undefined) {
                const c = accessor(doc, bin, att.COLOR_0);
                const scale = c.componentType === 5126 ? 255 : (c.normalized ? 255 / NORMALIZE[c.componentType] : 1);
                col = c.values.map((v) => [v[0] * scale, v[1] * scale, v[2] * scale]);
            }
            const idx = prim.indices !== undefined ? accessor(doc, bin, prim.indices).values.map((v) => v[0]) : pos.map((_, i) => i);
            const tris = [];
            for (let k = 0; k + 2 < idx.length; k += 3) {
                tris.push([0, 1, 2].map((j) => {
                    const i = idx[k + j];
                    return [pos[i][0], pos[i][1], pos[i][2], uv[i][0], uv[i][1], col[i][0], col[i][1], col[i][2]];
                }));
            }
            prims.push({ material: prim.material, tris });
        }
    }
    const props = [];
    for (const n of doc.nodes) {
        const m = /^bw2_prop_(\d+)_id_(\d+)/.exec(n.name || '');
        if (m) props.push({ name: n.name, resId: parseInt(m[2], 10), translation: n.translation || [0, 0, 0], rotation: n.rotation || [0, 0, 0, 1], scale: n.scale || [1, 1, 1] });
    }
    return { materials, prims, props };
}

function clipHalf(poly, axis, value, keepBelow) {
    const out = [];
    for (let i = 0; i < poly.length; i++) {
        const a = poly[i];
        const b = poly[(i + 1) % poly.length];
        const aIn = keepBelow ? a[axis] <= value : a[axis] >= value;
        const bIn = keepBelow ? b[axis] <= value : b[axis] >= value;
        if (aIn) out.push(a);
        if (aIn !== bIn) {
            const t = (value - a[axis]) / (b[axis] - a[axis]);
            out.push(a.map((x, k) => x + (b[k] - x) * t));
        }
    }
    return out.length >= 3 ? out : [];
}

function area(p) {
    const total = [0, 0, 0];
    for (let i = 1; i < p.length - 1; i++) {
        const a = [0, 1, 2].map((k) => p[i][k] - p[0][k]);
        const b = [0, 1, 2].map((k) => p[i + 1][k] - p[0][k]);
        total[0] += a[1] * b[2] - a[2] * b[1];
        total[1] += a[2] * b[0] - a[0] * b[2];
        total[2] += a[0] * b[1] - a[1] * b[0];
    }
    return Math.hypot(...total) / 2;
}

// The parts of a polygon outside the column x0 < x < x1, z0 < z < z1 (build_zone.py's outside())
export function outside(poly, x0, z0, x1, z1) {
    const xs = poly.map((v) => v[0]);
    const zs = poly.map((v) => v[2]);
    if (Math.max(...xs) <= x0 || Math.min(...xs) >= x1 || Math.max(...zs) <= z0 || Math.min(...zs) >= z1) return [poly];
    const parts = [clipHalf(poly, 0, x0, true), clipHalf(poly, 0, x1, false)];
    const middle = clipHalf(clipHalf(poly, 0, x0, false), 0, x1, true);
    if (middle.length) parts.push(clipHalf(middle, 2, z0, true), clipHalf(middle, 2, z1, false));
    return parts.filter((p) => p.length && area(p) > 1e-3);
}

// The part of a polygon inside the column
export function inside(poly, x0, z0, x1, z1) {
    let p = clipHalf(poly, 0, x0, false);
    if (p.length) p = clipHalf(p, 0, x1, true);
    if (p.length) p = clipHalf(p, 2, z0, false);
    if (p.length) p = clipHalf(p, 2, z1, true);
    return p.length && area(p) > 1e-3 ? p : null;
}

function fan(polys) {
    const tris = [];
    for (const p of polys) for (let j = 1; j < p.length - 1; j++) tris.push([p[0], p[j], p[j + 1]]);
    return tris;
}

// A tile rectangle [x0, z0, x1, z1] (ends exclusive) in chunk units
export function unitsRect(rect) {
    return rect.map((v) => v * TILE - HALF);
}

export function cutGeometry(geo, rect, groundMaterial, groundY) {
    const [x0, z0, x1, z1] = unitsRect(rect);
    for (const prim of geo.prims) {
        prim.tris = fan(prim.tris.flatMap((t) => outside(t, x0, z0, x1, z1)));
    }
    geo.props = geo.props.filter((p) => !(x0 - 8 < p.translation[0] && p.translation[0] < x1 + 8 && z0 - 8 < p.translation[2] && p.translation[2] < z1 + 8));
    if (groundMaterial !== null && groundMaterial !== undefined) {
        let m = geo.materials.findIndex((mm) => mm.name === groundMaterial);
        if (m >= 0) {
            const y = groundY || 0;
            const c = [[x0, y, z0], [x1, y, z0], [x1, y, z1], [x0, y, z1]].map(([x, yy, z]) => [x, yy, z, x / 32, z / 32, 254, 254, 254]);
            let prim = geo.prims.find((p) => p.material === m);
            if (!prim) geo.prims.push(prim = { material: m, tris: [] });
            prim.tris.push([c[0], c[2], c[1]], [c[0], c[3], c[2]]);
        }
    }
}

// Copies a rectangle of another chunk's geometry over this one's, moved to start at tile `to`
export function stampGeometry(geo, src, rect, to, withProps) {
    const [sx0, sz0, sx1, sz1] = unitsRect(rect);
    const dx = (to[0] - rect[0]) * TILE;
    const dz = (to[1] - rect[1]) * TILE;
    const [x0, z0, x1, z1] = [sx0 + dx, sz0 + dz, sx1 + dx, sz1 + dz];
    for (const prim of geo.prims) prim.tris = fan(prim.tris.flatMap((t) => outside(t, x0, z0, x1, z1)));
    for (const sprim of src.prims) {
        const smat = src.materials[sprim.material];
        let m = geo.materials.findIndex((mm) => mm.name === smat.name);
        if (m < 0) {
            geo.materials.push({ ...smat });
            m = geo.materials.length - 1;
        }
        const polys = sprim.tris.map((t) => inside(t, sx0, sz0, sx1, sz1)).filter(Boolean)
            .map((p) => p.map((v) => [v[0] + dx, v[1], v[2] + dz, ...v.slice(3)]));
        if (!polys.length) continue;
        let prim = geo.prims.find((p) => p.material === m);
        if (!prim) geo.prims.push(prim = { material: m, tris: [] });
        prim.tris.push(...fan(polys));
    }
    if (withProps) {
        geo.props = geo.props.filter((p) => !(x0 <= p.translation[0] && p.translation[0] < x1 && z0 <= p.translation[2] && p.translation[2] < z1));
        for (const p of src.props) {
            const [x, y, z] = p.translation;
            if (sx0 <= x && x < sx1 && sz0 <= z && z < sz1) geo.props.push({ ...p, translation: [x + dx, y, z + dz] });
        }
    }
}

export function cloneGeometry(geo) {
    return {
        materials: geo.materials.map((m) => ({ ...m })),
        prims: geo.prims.map((p) => ({ material: p.material, tris: p.tris.slice() })),
        props: geo.props.map((p) => ({ ...p })),
    };
}

// Terrain: cells [shape, slope, offset, tile_type, diagonal], 32 by 32
export const BLOCKED = 0x10000;

export function cloneTerrain(t) {
    return t ? { width: t.width, height: t.height, cells: t.cells.map((c) => c.slice()), splits: t.splits.map((s) => s.slice()) } : null;
}

export function cutTerrain(t, rect) {
    if (!t) return;
    const [x0, z0, x1, z1] = rect;
    const walkable = [];
    t.cells.forEach((c, i) => {
        const x = i % t.width, z = Math.floor(i / t.width);
        const inRect = x0 <= x && x < x1 && z0 <= z && z < z1;
        if (!inRect && !(c[3] & BLOCKED) && c[0] === 0) walkable.push([x, z, c]);
    });
    if (!walkable.length) return;
    for (let x = x0; x < x1; x++) {
        for (let z = z0; z < z1; z++) {
            let best = null, bestD = 1e9;
            for (const w of walkable) {
                const d = Math.abs(w[0] - x) + Math.abs(w[1] - z);
                if (d < bestD) { bestD = d; best = w[2]; }
            }
            const cell = t.cells[z * t.width + x];
            cell[0] = best[0]; cell[1] = best[1]; cell[2] = best[2]; cell[3] = best[3];
        }
    }
}

export function stampTerrain(t, src, rect, to) {
    if (!t || !src) return;
    const [x0, z0, x1, z1] = rect;
    for (let x = x0; x < x1; x++) {
        for (let z = z0; z < z1; z++) {
            const tx = to[0] + x - x0, tz = to[1] + z - z0;
            if (tx < 0 || tz < 0 || tx >= t.width || tz >= t.height) continue;
            const s = src.cells[z * src.width + x].slice();
            if (s[0] !== 0) {
                // A split tile names a row of its own layer's splits: copy the row over
                t.splits.push(src.splits[s[2]].slice());
                s[2] = t.splits.length - 1;
            }
            t.cells[tz * t.width + tx] = s;
        }
    }
}

// The walkable ground's height near a rectangle, for the ground a cut lays: the flat tiles' height around it
export function groundHeight(t, rect, tables) {
    if (!t || !tables) return 0;
    const [x0, z0, x1, z1] = rect;
    const hs = [];
    for (let x = x0 - 1; x <= x1; x++) {
        for (let z = z0 - 1; z <= z1; z++) {
            if (x < 0 || z < 0 || x >= t.width || z >= t.height) continue;
            if (x0 <= x && x < x1 && z0 <= z && z < z1) continue;
            const c = t.cells[z * t.width + x];
            if (c[0] !== 0 || (c[3] & BLOCKED)) continue;
            const ny = tables.slopes[c[1] * 3 + 1];
            if (!ny) continue;
            hs.push(-tables.offsets[c[2]] / ny);
        }
    }
    if (!hs.length) return 0;
    hs.sort((a, b) => a - b);
    return hs[Math.floor(hs.length / 2)];
}

// ---- Layered edits ----------------------------------------------------------------------------------------------
// Layers: ground (the geometry and the terrain's heights), props, collision (the tile flags), class (the tile class).
// Events are the editor's own operations. apply_world_edits.py does the same.

export const LAYERS = ['ground', 'props', 'collision', 'class'];
const FLAGS_MASK = 0xffff0000;

function nearestWalkable(t, rect) {
    const [x0, z0, x1, z1] = rect;
    const walkable = [];
    t.cells.forEach((c, i) => {
        const x = i % t.width, z = Math.floor(i / t.width);
        if (!(x0 <= x && x < x1 && z0 <= z && z < z1) && !(c[3] & BLOCKED) && c[0] === 0) walkable.push([x, z, c]);
    });
    return (x, z) => {
        let best = null, bestD = 1e9;
        for (const w of walkable) {
            const d = Math.abs(w[0] - x) + Math.abs(w[1] - z);
            if (d < bestD) { bestD = d; best = w[2]; }
        }
        return best;
    };
}

export function eraseLayers(st, op) {
    const layers = op.layers || LAYERS;
    const has = (l) => layers.includes(l);
    const [x0, z0, x1, z1] = unitsRect(op.rect);
    if (has('ground')) {
        for (const prim of st.geo.prims) prim.tris = fan(prim.tris.flatMap((t) => outside(t, x0, z0, x1, z1)));
        const m = op.ground ? st.geo.materials.findIndex((mm) => mm.name === op.ground) : -1;
        if (m >= 0) {
            const y = op.groundY || 0;
            const c = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]].map(([x, z]) => [x, y, z, x / 32, z / 32, 254, 254, 254]);
            let prim = st.geo.prims.find((p) => p.material === m);
            if (!prim) st.geo.prims.push(prim = { material: m, tris: [] });
            prim.tris.push([c[0], c[2], c[1]], [c[0], c[3], c[2]]);
        }
    }
    if (has('props')) {
        st.geo.props = st.geo.props.filter((p) => !(x0 <= p.translation[0] && p.translation[0] < x1 && z0 <= p.translation[2] && p.translation[2] < z1));
    }
    const t = st.terrain;
    if (!t || !(has('ground') || has('collision') || has('class'))) return;
    const near = nearestWalkable(t, op.rect);
    for (let x = op.rect[0]; x < op.rect[2]; x++) {
        for (let z = op.rect[1]; z < op.rect[3]; z++) {
            const cell = t.cells[z * t.width + x];
            if (!cell) continue;
            const n = near(x, z);
            if (has('ground') && n) { cell[0] = n[0]; cell[1] = n[1]; cell[2] = n[2]; cell[4] = n[4]; }
            if (has('collision') && has('class') && n) cell[3] = n[3];
            else if (has('collision')) cell[3] = (cell[3] & ~BLOCKED) >>> 0;
            else if (has('class') && n) cell[3] = ((cell[3] & FLAGS_MASK) | (n[3] & 0xffff)) >>> 0;
        }
    }
}

// Copies a rectangle of a source chunk's state onto this one at each of `tos` (tile positions), on the given layers.
// The source is read before any of it is written, so a chunk can copy from itself
export function copyLayers(st, src, op) {
    const layers = op.layers || LAYERS;
    const has = (l) => layers.includes(l);
    const rect = op.rect;
    const [sx0, sz0, sx1, sz1] = unitsRect(rect);
    const srcGeo = src === st ? cloneGeometry(src.geo) : src.geo;
    const srcTerrain = src === st ? cloneTerrain(src.terrain) : src.terrain;
    const pieces = [];
    if (has('ground')) {
        for (const sprim of srcGeo.prims) {
            const polys = sprim.tris.map((t) => inside(t, sx0, sz0, sx1, sz1)).filter(Boolean);
            if (polys.length) pieces.push([srcGeo.materials[sprim.material], polys]);
        }
    }
    for (const to of op.tos) {
        const dx = (to[0] - rect[0]) * TILE, dz = (to[1] - rect[1]) * TILE;
        const [x0, z0, x1, z1] = [sx0 + dx, sz0 + dz, sx1 + dx, sz1 + dz];
        if (has('ground')) {
            for (const prim of st.geo.prims) prim.tris = fan(prim.tris.flatMap((t) => outside(t, x0, z0, x1, z1)));
            for (const [mat, polys] of pieces) {
                let m = st.geo.materials.findIndex((mm) => mm.name === mat.name);
                if (m < 0) { st.geo.materials.push({ ...mat }); m = st.geo.materials.length - 1; }
                let prim = st.geo.prims.find((p) => p.material === m);
                if (!prim) st.geo.prims.push(prim = { material: m, tris: [] });
                prim.tris.push(...fan(polys.map((p) => p.map((v) => [v[0] + dx, v[1], v[2] + dz, ...v.slice(3)]))));
            }
        }
        if (has('props')) {
            st.geo.props = st.geo.props.filter((p) => !(x0 <= p.translation[0] && p.translation[0] < x1 && z0 <= p.translation[2] && p.translation[2] < z1));
            for (const p of srcGeo.props) {
                const [x, y, z] = p.translation;
                if (sx0 <= x && x < sx1 && sz0 <= z && z < sz1) st.geo.props.push({ ...p, uid: undefined, translation: [x + dx, y, z + dz] });
            }
        }
        const t = st.terrain;
        if (!t || !srcTerrain) continue;
        for (let x = rect[0]; x < rect[2]; x++) {
            for (let z = rect[1]; z < rect[3]; z++) {
                const tx = to[0] + x - rect[0], tz = to[1] + z - rect[1];
                if (tx < 0 || tz < 0 || tx >= t.width || tz >= t.height) continue;
                const s = srcTerrain.cells[z * srcTerrain.width + x];
                const d = t.cells[tz * t.width + tx];
                if (has('ground')) {
                    d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[4] = s[4];
                    if (s[0] !== 0 && srcTerrain.splits[s[2]]) {
                        t.splits.push(srcTerrain.splits[s[2]].slice());
                        d[2] = t.splits.length - 1;
                    }
                }
                if (has('collision')) d[3] = ((d[3] & 0xffff) | (s[3] & FLAGS_MASK)) >>> 0;
                if (has('class')) d[3] = ((d[3] & FLAGS_MASK) | (s[3] & 0xffff)) >>> 0;
            }
        }
    }
}

export function propKey(p) {
    return JSON.stringify([p.resId, p.translation.map((v) => Math.round(v * 1000) / 1000), p.rotation.map((v) => Math.round(v * 10000) / 10000)]);
}

export function propOp(st, op) {
    const i = op.match ? st.geo.props.findIndex((p) => propKey(p) === propKey(op.match)) : -1;
    const value = op.value ? { resId: op.value.resId, translation: op.value.translation.slice(), rotation: op.value.rotation.slice(), scale: (op.value.scale || [1, 1, 1]).slice(), uid: op._uid } : null;
    if (op.action === 'add') st.geo.props.push(value);
    else if (op.action === 'set' && i >= 0) st.geo.props[i] = { ...value, uid: st.geo.props[i].uid };
    else if (op.action === 'delete' && i >= 0) st.geo.props.splice(i, 1);
}

export function tilesOp(st, op) {
    const t = st.terrain;
    if (!t) return;
    for (const [xz, v] of Object.entries(op.set)) {
        const [x, z] = xz.split(',').map(Number);
        const c = t.cells[z * t.width + x];
        if (c && v.tile_type !== undefined) c[3] = v.tile_type >>> 0;
    }
}
