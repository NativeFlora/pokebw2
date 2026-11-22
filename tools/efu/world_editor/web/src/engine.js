// The world as the edits leave it: the pack's matrices, zones' events and chunks, with the operations replayed on them
// in order, the way apply_world_edits.py replays them. The pack is already the result of the edits saved before
// (S.baseOps), so only the operations made since are replayed here.

import * as pack from './pack.js';
import * as G from './geometry.js';

export const KINDS = ['npcs', 'warps', 'triggers', 'bg_events'];
export const CELL_OPS = ['tiles', 'erase', 'copy', 'prop', 'cut', 'stamp'];

export function clean(obj) {
    return JSON.parse(JSON.stringify(obj, (k, v) => (k === '_uid' || k === 'uid' ? undefined : v)));
}

export function canon(v) {
    if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
    if (v && typeof v === 'object') return '{' + Object.keys(v).filter((k) => k !== '_uid' && k !== 'uid' && v[k] !== undefined).sort().map((k) => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
    return JSON.stringify(v);
}

let uidCounter = 0;
export function newUid() {
    return 'n' + (++uidCounter) + '_' + Date.now().toString(36);
}

// ---- Models -------------------------------------------------------------------------------------------------------

const baseModels = {};   // name -> {geo, terrain} or null, once loaded
const loading = {};

export function textureKey(uri) {
    return pack.normalize('map/models/_/' + uri);
}

export function loadModel(name) {
    if (!name) return Promise.resolve(null);
    if (!loading[name]) {
        loading[name] = pack.loadModel(name).then(async (data) => {
            if (!data) { baseModels[name] = null; return null; }
            const { doc, bin } = G.parseGlb(pack.b64ToBuffer(data.glb));
            const geo = G.chunkGeometry(doc, bin);
            await pack.loadTextures(geo.materials.filter((m) => m.uri).map((m) => textureKey(m.uri)));
            baseModels[name] = { geo, terrain: data.terrain[0] || null, geoVer: 0, propVer: 0, terVer: 0, base: true, model: name };
            return baseModels[name];
        }).catch(() => { baseModels[name] = null; return null; });
    }
    return loading[name];
}

// ---- The world ----------------------------------------------------------------------------------------------------

export const world = { idx: null, baseOps: [], matrices: {}, events: {}, states: {}, locks: {}, gen: 0 };

export function init(idx, baseOps) {
    world.idx = idx;
    world.baseOps = baseOps;
    reset();
}

function reset() {
    world.matrices = {};
    world.events = {};
    world.states = {};
    world.locks = {};
    for (const op of world.baseOps) if (op.op === 'lock') world.locks[lockKey(op.zone, op.x, op.z)] = op;
    world.gen++;
}

export function lockKey(zone, x, z) {
    return zone + '|' + x + '|' + z;
}

export function lockAt(zone, x, z) {
    const l = world.locks[lockKey(zone, x, z)];
    return l && l.locked !== false ? l : null;
}

export function matrix(name) {
    if (!world.matrices[name]) {
        const m = world.idx.matrices[name];
        world.matrices[name] = { maps: m.maps.map((r) => r.slice()), zones: m.zones ? m.zones.map((r) => r.slice()) : null, sourceOnly: !!m.source_only };
    }
    return world.matrices[name];
}

export function cellModel(name, cx, cz) {
    const m = matrix(name);
    return (m.maps[cz] && m.maps[cz][cx]) || null;
}

export function zoneEvents(zone) {
    if (!world.events[zone]) {
        const z = world.idx.zones[zone];
        const ev = {};
        for (const k of KINDS) ev[k] = ((z && z.events && z.events[k]) || []).map((o, i) => ({ ...JSON.parse(JSON.stringify(o)), _uid: zone + ':' + k + ':' + i }));
        world.events[zone] = ev;
    }
    return world.events[zone];
}

function key(name, cx, cz) {
    return name + '|' + cx + '|' + cz;
}

// A chunk as shown: its edited state, or its model as the pack has it
export function view(name, cx, cz) {
    return world.states[key(name, cx, cz)] || baseModels[cellModel(name, cx, cz)] || null;
}

export function state(name, cx, cz) {
    const k = key(name, cx, cz);
    if (!world.states[k]) {
        const model = cellModel(name, cx, cz);
        const base = model && baseModels[model];
        if (!base) return null;
        world.states[k] = { model, geo: G.cloneGeometry(base.geo), terrain: G.cloneTerrain(base.terrain), geoVer: 1, propVer: 1, terVer: 1 };
    }
    return world.states[k];
}

function bump(st, layers) {
    if (layers.includes('ground')) { st.geoVer++; st.terVer++; }
    if (layers.includes('props')) st.propVer++;
    if (layers.includes('collision') || layers.includes('class')) st.terVer++;
}

// A rectangle of the matrix's tiles [x0, z0, x1, z1) as the parts in each chunk, in the chunk's own tiles
export function splitRect(r) {
    const parts = [];
    for (let cz = Math.floor(r[1] / 32); cz * 32 < r[3]; cz++) {
        for (let cx = Math.floor(r[0] / 32); cx * 32 < r[2]; cx++) {
            const x0 = Math.max(r[0], cx * 32), z0 = Math.max(r[1], cz * 32);
            const x1 = Math.min(r[2], cx * 32 + 32), z1 = Math.min(r[3], cz * 32 + 32);
            if (x0 < x1 && z0 < z1) parts.push({ cx, cz, global: [x0, z0, x1, z1], local: [x0 - cx * 32, z0 - cz * 32, x1 - cx * 32, z1 - cz * 32] });
        }
    }
    return parts;
}

// Copies of the chunks under a rectangle, which a copy reads before it writes anything
export function snapshot(name, r) {
    const snaps = {};
    for (const p of splitRect(r)) {
        const v = view(name, p.cx, p.cz);
        if (v) snaps[p.cx + ',' + p.cz] = { geo: G.cloneGeometry(v.geo), terrain: G.cloneTerrain(v.terrain) };
    }
    return snaps;
}

function applyCopy(op, snaps) {
    const layers = op.layers || G.LAYERS;
    const r = op.from.rect;
    snaps = snaps || snapshot(op.from.matrix, r);
    for (const to of op.to) {
        for (const part of splitRect(r)) {
            const src = snaps[part.cx + ',' + part.cz];
            if (!src) continue;
            const gx = to[0] + part.global[0] - r[0], gz = to[1] + part.global[1] - r[1];
            const w = part.global[2] - part.global[0], h = part.global[3] - part.global[1];
            for (const d of splitRect([gx, gz, gx + w, gz + h])) {
                const st = cellModel(op.matrix, d.cx, d.cz) && state(op.matrix, d.cx, d.cz);
                if (!st) continue;
                const ox = d.global[0] - gx, oz = d.global[1] - gz;
                const srect = [part.local[0] + ox, part.local[1] + oz, part.local[0] + ox + d.local[2] - d.local[0], part.local[1] + oz + d.local[3] - d.local[1]];
                G.copyLayers(st, src, { layers, rect: srect, tos: [[d.local[0], d.local[1]]] });
                bump(st, layers);
            }
        }
    }
}

function applyEvent(op) {
    const list = zoneEvents(op.zone)[op.kind];
    const i = list.findIndex((o) => o._uid === op._uid);
    if (op.action === 'add') list.push({ ...JSON.parse(JSON.stringify(op.value)), _uid: op._uid });
    else if (op.action === 'set' && i >= 0) list[i] = { ...JSON.parse(JSON.stringify(op.value)), _uid: op._uid };
    else if (op.action === 'delete' && i >= 0) list.splice(i, 1);
}

// Applies one operation; `snaps` lets a brush stroke's copies read the source as the stroke found it
export function applyOp(op, snaps) {
    switch (op.op) {
    case 'matrix': {
        const m = matrix(op.matrix);
        if (op.model) { m.maps[op.z][op.x] = op.model; delete world.states[key(op.matrix, op.x, op.z)]; }
        if (op.zone && m.zones) m.zones[op.z][op.x] = op.zone;
        break;
    }
    case 'event': applyEvent(op); break;
    case 'lock': world.locks[lockKey(op.zone, op.x, op.z)] = op; break;
    case 'tiles': { const st = state(op.matrix, op.x, op.z); if (st) { G.tilesOp(st, op); st.terVer++; } break; }
    case 'prop': { const st = state(op.matrix, op.x, op.z); if (st) { G.propOp(st, op); st.propVer++; } break; }
    case 'erase': {
        const layers = op.layers || G.LAYERS;
        for (const p of splitRect(op.rect)) {
            const st = cellModel(op.matrix, p.cx, p.cz) && state(op.matrix, p.cx, p.cz);
            if (!st) continue;
            G.eraseLayers(st, { ...op, rect: p.local, layers });
            bump(st, layers);
        }
        break;
    }
    case 'copy': applyCopy(op, snaps); break;
    default: break;   // cut and stamp: only in files saved before, already in the pack
    }
    world.gen++;
}

export function replay(ops) {
    reset();
    for (const op of ops) applyOp(op);
}

// The models the operations may touch, loaded before they are applied
export function preload(ops) {
    const names = new Set();
    const cell = (m, cx, cz) => { const n = cellModel(m, cx, cz); if (n) names.add(n); };
    for (const op of ops) {
        if (op.op === 'matrix' && op.model) names.add(op.model);
        if (op.op === 'tiles' || op.op === 'prop') cell(op.matrix, op.x, op.z);
        if (op.op === 'erase') for (const p of splitRect(op.rect)) cell(op.matrix, p.cx, p.cz);
        if (op.op === 'copy') {
            for (const p of splitRect(op.from.rect)) cell(op.from.matrix, p.cx, p.cz);
            const w = op.from.rect[2] - op.from.rect[0], h = op.from.rect[3] - op.from.rect[1];
            for (const to of op.to) for (const p of splitRect([to[0], to[1], to[0] + w, to[1] + h])) cell(op.matrix, p.cx, p.cz);
        }
    }
    return Promise.all([...names].map(loadModel));
}

export function loadMatrix(name) {
    const m = matrix(name);
    return Promise.all([...new Set(m.maps.flat().filter(Boolean))].map(loadModel));
}
