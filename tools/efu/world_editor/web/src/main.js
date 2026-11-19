// Escape from Unova's world editor: a map matrix seen from above, its chunks' models and props, their collision and
// tile classes, the zones' events, and the edits made to them, which are saved as world_edits.json for
// apply_world_edits.py. Edits are a list of operations; everything shown is the pack's maps with them applied.

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import * as pack from './pack.js';
import * as G from './geometry.js';

THREE.ColorManagement.enabled = false;

const CHUNK = 512;
const KINDS = ['npcs', 'warps', 'triggers', 'bg_events'];
const KIND_LABEL = { npcs: 'NPC', warps: 'Warp', triggers: 'Trigger', bg_events: 'Sign / BG event' };
const KIND_COLOR = { npcs: '#ffd166', warps: '#c77dff', triggers: '#ffef5a', bg_events: '#4cc9f0' };
const FLAGS = [[0x1, 'Collision'], [0x2, 'Water'], [0x4, 'Encounters'], [0x8, '0x08'], [0x20, '0x20'], [0x40, 'Reflect'], [0x80, '0x80'], [0x100, '0x100']];
const TOOLS = [
    ['select', 'Select', 'V'], ['block', 'Collision', 'B'], ['class', 'Tile class', 'C'],
    ['cut', 'Clear', 'X'], ['stamp', 'Stamp', 'S'], ['matrix', 'Chunk', 'M'],
    ['npcs', '+ NPC', 'N'], ['warps', '+ Warp', 'W'], ['triggers', '+ Trigger', 'T'],
    ['bg_events', '+ Sign', 'G'],
];
const STORAGE = 'efu-world-editor-ops';

const $ = (id) => document.getElementById(id);
const S = {
    idx: null, matrixName: null, ops: [], baseOps: [], undo: [], redo: [], tool: 'select',
    selection: null, hover: null, clipboard: null, classBrush: 4, ground: 'grass01ax',
    view: { x: 0, z: 0, scale: 0.5 }, drag: null, version: 0,
};

// ---- Edits ---------------------------------------------------------------------------------------------------

function clean(obj) {
    return JSON.parse(JSON.stringify(obj, (k, v) => (k === '_uid' ? undefined : v)));
}

function canon(v) {
    if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
    if (v && typeof v === 'object') return '{' + Object.keys(v).filter((k) => k !== '_uid').sort().map((k) => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
    return JSON.stringify(v);
}

function sameCell(a, b) {
    return a.matrix === b.matrix && a.x === b.x && a.z === b.z;
}

// Folds edits of the same thing together, so that applying the list twice changes nothing more
function compact(ops) {
    const out = [];
    for (const op of ops.map(clean)) {
        if (op.op === 'tiles') {
            const last = out[out.length - 1];
            if (last && last.op === 'tiles' && sameCell(last, op)) {
                out[out.length - 1] = { ...last, set: { ...last.set, ...op.set } };
                continue;
            }
        }
        if (op.op === 'event' && op.action !== 'add') {
            const key = canon(op.match);
            let j = -1;
            for (let i = out.length - 1; i >= 0; i--) {
                const o = out[i];
                if (o.op === 'event' && o.zone === op.zone && o.kind === op.kind && o.action !== 'delete' && canon(o.value) === key) { j = i; break; }
            }
            if (j >= 0) {
                const prev = out[j];
                if (op.action === 'set') {
                    if (prev.action === 'set' && canon(prev.match) === canon(op.value)) out.splice(j, 1);
                    else out[j] = { ...prev, value: op.value };
                } else if (prev.action === 'add') {
                    out.splice(j, 1);
                } else {
                    out[j] = { op: 'event', zone: op.zone, kind: op.kind, action: 'delete', match: prev.match };
                }
                continue;
            }
            if (op.action === 'set' && canon(op.match) === canon(op.value)) continue;
        }
        out.push(op);
    }
    return out;
}

function commit(mutate) {
    S.undo.push(S.ops.slice());
    if (S.undo.length > 300) S.undo.shift();
    S.redo = [];
    mutate();
    changed();
}

function changed() {
    S.version++;
    try { localStorage.setItem(STORAGE, JSON.stringify({ base: canon(S.baseOps), ops: S.ops.map(clean) })); } catch (e) { /* storage is a convenience */ }
    refreshAll();
}

function undo() {
    if (!S.undo.length) return;
    S.redo.push(S.ops);
    S.ops = S.undo.pop();
    changed();
}

function redo() {
    if (!S.redo.length) return;
    S.undo.push(S.ops);
    S.ops = S.redo.pop();
    changed();
}

let uidCounter = 0;
function newUid() {
    return 'n' + (++uidCounter) + '_' + Date.now().toString(36);
}

// ---- Derived state: matrices, events and chunks with the edits applied ---------------------------------------

const derived = { version: -1, matrices: {}, events: {} };

function syncDerived() {
    if (derived.version === S.version) return;
    derived.version = S.version;
    derived.matrices = {};
    derived.events = {};
}

function matrix(name) {
    syncDerived();
    if (!derived.matrices[name]) {
        const m = S.idx.matrices[name];
        const maps = m.maps.map((r) => r.slice());
        const zones = m.zones ? m.zones.map((r) => r.slice()) : null;
        for (const op of S.ops) {
            if (op.op !== 'matrix' || op.matrix !== name) continue;
            if (op.model) maps[op.z][op.x] = op.model;
            if (op.zone && zones) zones[op.z][op.x] = op.zone;
        }
        derived.matrices[name] = { maps, zones, sourceOnly: !!m.source_only };
    }
    return derived.matrices[name];
}

function zoneEvents(zone) {
    syncDerived();
    if (!derived.events[zone]) {
        const z = S.idx.zones[zone];
        const ev = {};
        for (const k of KINDS) {
            ev[k] = ((z && z.events && z.events[k]) || []).map((o, i) => ({ ...JSON.parse(JSON.stringify(o)), _uid: k + ':' + i }));
        }
        for (const op of S.ops) {
            if (op.op !== 'event' || op.zone !== zone) continue;
            const list = ev[op.kind];
            const i = list.findIndex((o) => o._uid === op._uid);
            if (op.action === 'add') list.push({ ...JSON.parse(JSON.stringify(op.value)), _uid: op._uid });
            else if (op.action === 'set' && i >= 0) list[i] = { ...JSON.parse(JSON.stringify(op.value)), _uid: op._uid };
            else if (op.action === 'delete' && i >= 0) list.splice(i, 1);
        }
        derived.events[zone] = ev;
    }
    return derived.events[zone];
}

function cellZone(name, cx, cz) {
    const m = matrix(name);
    if (m.zones && m.zones[cz] && m.zones[cz][cx]) return m.zones[cz][cx];
    return zonesOfMatrix(name)[0] || null;
}

function zonesOfMatrix(name) {
    const m = matrix(name);
    const set = new Set();
    if (m.zones && !m.sourceOnly) for (const r of m.zones) for (const z of r) if (z) set.add(z);
    if (!m.sourceOnly) for (const [z, v] of Object.entries(S.idx.zones)) if (v.header.matrix === name) set.add(z);
    return [...set].filter((z) => S.idx.zones[z]);
}

function areaOf(zone) {
    const z = S.idx.zones[zone];
    return z ? S.idx.areas[z.header.area] : null;
}

// The operations on one chunk's model and terrain since its model last changed
function cellOps(name, cx, cz) {
    let ops = [];
    for (const op of S.ops) {
        if (op.matrix !== name || op.x !== cx || op.z !== cz) continue;
        if (op.op === 'matrix' && op.model) ops = [];
        else if (op.op === 'cut' || op.op === 'stamp' || op.op === 'tiles') ops.push(op);
    }
    return ops;
}

// ---- Models ---------------------------------------------------------------------------------------------------

const modelCache = {};   // name -> Promise<{geo, terrain, data}>

function baseModel(name) {
    if (!modelCache[name]) {
        modelCache[name] = pack.loadModel(name).then(async (data) => {
            if (!data) return null;
            const { doc, bin } = G.parseGlb(pack.b64ToBuffer(data.glb));
            const geo = G.chunkGeometry(doc, bin);
            await pack.loadTextures(geo.materials.filter((m) => m.uri).map((m) => textureKey(m.uri)));
            return { geo, terrain: data.terrain[0] || null, layers: data.terrain, data: data.data };
        });
    }
    return modelCache[name];
}

function textureKey(uri) {
    return pack.normalize('map/models/_/' + uri);
}

const textureCache = {};
function threeTexture(key, sampler) {
    const id = key + '|' + (sampler ? sampler.wrapS + ',' + sampler.wrapT : '');
    if (!textureCache[id]) {
        const url = pack.texture(key);
        if (!url) return null;
        const tex = new THREE.Texture();
        const img = new Image();
        img.onload = () => { tex.image = img; tex.needsUpdate = true; requestRender(); };
        img.src = url;
        const wrap = (w) => (w === 33648 ? THREE.MirroredRepeatWrapping : w === 33071 ? THREE.ClampToEdgeWrapping : THREE.RepeatWrapping);
        tex.wrapS = wrap(sampler && sampler.wrapS);
        tex.wrapT = wrap(sampler && sampler.wrapT);
        tex.magFilter = THREE.NearestFilter;
        tex.minFilter = THREE.NearestFilter;
        tex.generateMipmaps = false;
        tex.flipY = false;
        textureCache[id] = tex;
    }
    return textureCache[id];
}

const materialCache = {};
function threeMaterial(m) {
    const id = m.name + '|' + m.uri + '|' + m.alphaMode;
    if (!materialCache[id]) {
        const map = m.uri ? threeTexture(textureKey(m.uri), m.sampler) : null;
        materialCache[id] = new THREE.MeshBasicMaterial({
            map, vertexColors: true, side: THREE.DoubleSide,
            alphaTest: m.alphaMode === 'OPAQUE' ? 0 : 0.5, transparent: m.alphaMode === 'BLEND',
            color: map ? 0xffffff : 0x8a8f99,
        });
    }
    return materialCache[id];
}

function geometryGroup(geo) {
    const group = new THREE.Group();
    for (const prim of geo.prims) {
        if (!prim.tris.length) continue;
        const n = prim.tris.length * 3;
        const pos = new Float32Array(n * 3), uv = new Float32Array(n * 2), col = new Float32Array(n * 3);
        let i = 0;
        for (const t of prim.tris) {
            for (const v of t) {
                pos.set([v[0], v[1], v[2]], i * 3);
                uv.set([v[3], v[4]], i * 2);
                col.set([v[5] / 255, v[6] / 255, v[7] / 255], i * 3);
                i++;
            }
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
        g.setAttribute('color', new THREE.BufferAttribute(col, 3));
        g.computeBoundingSphere();
        const mesh = new THREE.Mesh(g, threeMaterial(geo.materials[prim.material]));
        if (geo.materials[prim.material].alphaMode === 'BLEND') mesh.renderOrder = 1;
        group.add(mesh);
    }
    return group;
}

// Props: each bundle's models parsed once by three's loader, placed where the chunk's nodes say
const propCache = {};
const gltf = new GLTFLoader();
gltf.manager.setURLModifier((url) => pack.texture(pack.normalize(url)) || url);

function propModel(bundle, resId) {
    const id = bundle + ':' + resId;
    if (!propCache[id]) {
        propCache[id] = pack.loadProps(bundle).then(async (b) => {
            const entry = b && b[resId];
            if (!entry) return null;
            const buffer = pack.b64ToBuffer(entry.glb);
            const { doc } = G.parseGlb(buffer);
            await pack.loadTextures((doc.images || []).filter((im) => im.uri).map((im) => pack.normalize(entry.base + '/' + im.uri)));
            return new Promise((resolve) => {
                gltf.parse(buffer, entry.base + '/', (g) => {
                    g.scene.traverse((o) => {
                        if (o.material) {
                            for (const mat of [].concat(o.material)) {
                                if (mat.map) { mat.map.magFilter = THREE.NearestFilter; mat.map.colorSpace = THREE.NoColorSpace; }
                                mat.side = THREE.DoubleSide;
                                if (mat.transparent || mat.alphaTest) mat.alphaTest = 0.5;
                            }
                        }
                    });
                    resolve(g.scene);
                }, () => resolve(null));
            });
        });
    }
    return propCache[id];
}

// ---- Chunks of the shown matrix ---------------------------------------------------------------------------------

const cells = {};   // "cx,cz" -> {model, geoKey, terrainKey, geo, terrain, group, overlay, building}

async function buildCell(cx, cz) {
    const key = cx + ',' + cz;
    const m = matrix(S.matrixName);
    const model = m.maps[cz][cx];
    const ops = cellOps(S.matrixName, cx, cz);
    const geoOps = ops.filter((o) => o.op !== 'tiles');
    const geoKey = model + JSON.stringify(geoOps.map(clean));
    const terrainKey = model + JSON.stringify(ops.map(clean));
    let cell = cells[key];
    if (cell && cell.geoKey === geoKey && cell.terrainKey === terrainKey) return cell;
    const token = Symbol('build');
    cell = cells[key] = cells[key] || { cx, cz };
    cell.token = token;
    const base = await baseModel(model);
    if (cell.token !== token) return cell;
    cell.model = model;
    cell.missing = !base;
    // Stamp sources
    const sources = {};
    for (const op of ops) if (op.op === 'stamp' && !sources[op.from]) sources[op.from] = await baseModel(op.from);
    for (const src of Object.values(sources)) if (src) await pack.loadTextures(src.geo.materials.filter((mm) => mm.uri).map((mm) => textureKey(mm.uri)));
    if (cell.token !== token) return cell;
    const geoChanged = cell.geoKey !== geoKey;
    let geo = base ? G.cloneGeometry(base.geo) : { materials: [], prims: [], props: [] };
    let terrain = base ? G.cloneTerrain(base.terrain) : null;
    for (const op of ops) {
        if (op.op === 'cut') {
            if (geoChanged) G.cutGeometry(geo, op.rect, op.ground, op.groundY);
            G.cutTerrain(terrain, op.rect);
        } else if (op.op === 'stamp') {
            const src = sources[op.from];
            if (!src) continue;
            if (geoChanged) G.stampGeometry(geo, src.geo, op.rect, op.to, op.props);
            G.stampTerrain(terrain, src.terrain, op.rect, op.to);
        } else if (op.op === 'tiles' && terrain) {
            for (const [xz, v] of Object.entries(op.set)) {
                const [x, z] = xz.split(',').map(Number);
                const c = terrain.cells[z * terrain.width + x];
                if (c && v.tile_type !== undefined) c[3] = v.tile_type;
            }
        }
    }
    cell.terrain = terrain;
    cell.terrainKey = terrainKey;
    cell.overlay = null;
    if (geoChanged) {
        cell.geo = geo;
        cell.geoKey = geoKey;
        if (cell.group) scene.remove(cell.group);
        cell.group = geometryGroup(geo);
        cell.group.position.set(cx * CHUNK + CHUNK / 2, 0, cz * CHUNK + CHUNK / 2);
        cell.propGroup = new THREE.Group();
        cell.group.add(cell.propGroup);
        cell.propGroup.visible = $('showProps').checked;
        scene.add(cell.group);
        placeProps(cell);
    }
    requestRender();
    return cell;
}

async function placeProps(cell) {
    const zone = cellZone(S.matrixName, cell.cx, cell.cz);
    const area = areaOf(zone);
    const bundle = area && area.prop_bundle;
    if (!bundle) return;
    const group = cell.propGroup;
    for (const p of cell.geo.props) {
        const scn = await propModel(bundle, p.resId);
        if (!scn || cell.propGroup !== group) continue;
        const o = SkeletonUtils.clone(scn);
        o.position.set(...p.translation);
        o.quaternion.set(...p.rotation);
        o.scale.set(...p.scale);
        group.add(o);
        requestRender();
    }
}

function clearCells() {
    for (const c of Object.values(cells)) if (c.group) scene.remove(c.group);
    for (const k of Object.keys(cells)) delete cells[k];
}

function refreshCells() {
    if (!S.matrixName) return;
    const m = matrix(S.matrixName);
    const jobs = [];
    for (let cz = 0; cz < m.maps.length; cz++) {
        for (let cx = 0; cx < m.maps[cz].length; cx++) {
            if (m.maps[cz][cx]) jobs.push(buildCell(cx, cz));
        }
    }
    return Promise.all(jobs);
}

// ---- Rendering -----------------------------------------------------------------------------------------------------

const glCanvas = $('gl');
const ov = $('ov');
const ctx = ov.getContext('2d');
const renderer = new THREE.WebGLRenderer({ canvas: glCanvas, antialias: false });
renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
renderer.setClearColor(0x0d0f13);
const scene = new THREE.Scene();
scene.add(new THREE.AmbientLight(0xffffff, 3));
const ortho = new THREE.OrthographicCamera(-1, 1, 1, -1, -10000, 10000);
const persp = new THREE.PerspectiveCamera(45, 1, 4, 40000);
let orbit = null;
let renderQueued = false;

function is3d() {
    return $('show3d').checked;
}

function resize() {
    const r = $('main').getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    renderer.setPixelRatio(dpr);
    renderer.setSize(r.width, r.height, false);
    ov.width = r.width * dpr;
    ov.height = r.height * dpr;
    ov.style.width = r.width + 'px';
    ov.style.height = r.height + 'px';
    requestRender();
}

function requestRender() {
    if (renderQueued) return;
    renderQueued = true;
    requestAnimationFrame(() => { renderQueued = false; render(); });
}

function size() {
    return { w: ov.clientWidth, h: ov.clientHeight };
}

function render() {
    const { w, h } = size();
    if (is3d()) {
        persp.aspect = w / h;
        persp.updateProjectionMatrix();
        renderer.render(scene, persp);
    } else {
        const s = S.view.scale;
        ortho.left = -w / 2 / s; ortho.right = w / 2 / s; ortho.top = h / 2 / s; ortho.bottom = -h / 2 / s;
        ortho.position.set(S.view.x, 5000, S.view.z);
        ortho.up.set(0, 0, -1);
        ortho.lookAt(S.view.x, 0, S.view.z);
        ortho.updateProjectionMatrix();
        renderer.render(scene, ortho);
    }
    drawOverlay();
}

// World units to screen pixels (CSS), in the top-down view; in 3D, through the perspective camera
function toScreen(x, z, y = 0) {
    const { w, h } = size();
    if (is3d()) {
        const v = new THREE.Vector3(x, y, z).project(persp);
        if (v.z > 1) return null;
        return [(v.x + 1) / 2 * w, (1 - v.y) / 2 * h];
    }
    return [(x - S.view.x) * S.view.scale + w / 2, (z - S.view.z) * S.view.scale + h / 2];
}

function toWorld(px, py) {
    const { w, h } = size();
    return [(px - w / 2) / S.view.scale + S.view.x, (py - h / 2) / S.view.scale + S.view.z];
}

function tileAt(px, py) {
    if (is3d()) return null;
    const [x, z] = toWorld(px, py);
    return [Math.floor(x / G.TILE), Math.floor(z / G.TILE)];
}

function classColor(cls) {
    if (cls === 0) return null;
    if ((cls >= 0x04 && cls <= 0x09) || cls === 0x21 || cls === 0x22 || cls === 0x24) return 'rgba(60,220,90,0.55)';
    if ((cls >= 0x14 && cls <= 0x17) || (cls >= 0x3d && cls <= 0x44) || (cls >= 0x94 && cls <= 0x97)) return 'rgba(60,140,255,0.55)';
    if (cls >= 0x72 && cls <= 0x75) return 'rgba(255,150,40,0.7)';
    if (cls >= 0x51 && cls <= 0x58) return 'rgba(255,80,200,0.55)';
    if ((cls >= 0x0a && cls <= 0x0c) || cls === 0x19 || cls === 0x23) return 'rgba(230,200,120,0.5)';
    if (cls >= 0xd0) return 'rgba(0,230,230,0.6)';
    return 'rgba(200,200,200,0.45)';
}

function cellOverlay(cell, mode) {
    if (!cell.terrain) return null;
    if (cell.overlay && cell.overlayMode === mode) return cell.overlay;
    const t = cell.terrain;
    const c = document.createElement('canvas');
    c.width = t.width * 4;
    c.height = t.height * 4;
    const g = c.getContext('2d');
    for (let z = 0; z < t.height; z++) {
        for (let x = 0; x < t.width; x++) {
            const cellv = t.cells[z * t.width + x];
            const type = cellv[3];
            const cls = type & 0xffff;
            let color = null;
            if (mode === 'collision') color = (type & G.BLOCKED) ? 'rgba(255,40,40,0.3)' : null;
            else if (mode === 'class') color = classColor(cls);
            if (color) { g.fillStyle = color; g.fillRect(x * 4, z * 4, 4, 4); }
            if (mode === 'class' && cls >= 0x72 && cls <= 0x75) {
                g.fillStyle = '#fff';
                const d = { 0x72: [3, 1.5], 0x73: [0, 1.5], 0x74: [1.5, 0], 0x75: [1.5, 3] }[cls];
                g.fillRect(x * 4 + d[0], z * 4 + d[1], 1, 1);
            }
            if (mode === 'collision' && (type & 0x40000)) { g.fillStyle = 'rgba(60,220,90,0.35)'; g.fillRect(x * 4, z * 4, 4, 4); }
        }
    }
    cell.overlay = c;
    cell.overlayMode = mode;
    return c;
}

function eventRect(kind, o) {
    const g = o.grid;
    if (!g) return null;
    if (kind === 'npcs') return [g.x, g.z, 1, 1];
    if (kind === 'warps') return [Math.floor(g.x / 16), Math.floor(g.z / 16), Math.max(1, g.width), Math.max(1, g.height)];
    if (kind === 'triggers') return [g.x, g.z, Math.max(1, g.width), Math.max(1, g.height)];
    if (kind === 'bg_events') return [g.x, g.y, 1, 1];
    return null;
}

function eventHeight(kind, o) {
    const g = o.grid;
    if (kind === 'npcs') return g.y / 4096;
    if (kind === 'warps' || kind === 'triggers') return g.y;
    if (kind === 'bg_events') return g.z;
    return 0;
}

function allEvents() {
    const out = [];
    for (const zone of zonesOfMatrix(S.matrixName)) {
        const ev = zoneEvents(zone);
        for (const kind of KINDS) {
            ev[kind].forEach((o, i) => {
                const r = eventRect(kind, o);
                const fest = kind === 'bg_events' && o.condition >= 3;
                if (r && (!fest || $('showFest').checked)) out.push({ zone, kind, o, i, r, fest });
            });
        }
    }
    return out;
}

const spriteImages = {};
function spriteImage(code) {
    if (!(code in spriteImages)) {
        const url = pack.sprite(code);
        spriteImages[code] = null;
        if (url) {
            const img = new Image();
            img.onload = () => { spriteImages[code] = img; requestRender(); };
            img.src = url;
        }
    }
    return spriteImages[code];
}

function drawOverlay() {
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const { w, h } = size();
    ctx.clearRect(0, 0, w, h);
    if (!S.matrixName) return;
    const m = matrix(S.matrixName);
    const s = S.view.scale;
    const mode = $('overlay').value;
    if (!is3d()) {
        ctx.imageSmoothingEnabled = false;
        for (const cell of Object.values(cells)) {
            const [x0, y0] = toScreen(cell.cx * CHUNK, cell.cz * CHUNK);
            const size = CHUNK * s;
            if (x0 > w || y0 > h || x0 + size < 0 || y0 + size < 0) continue;
            if (mode !== 'none') {
                const c = cellOverlay(cell, mode);
                if (c) ctx.drawImage(c, x0, y0, size, size);
            }
            if (cell.missing) {
                ctx.fillStyle = 'rgba(120,120,140,0.25)';
                ctx.fillRect(x0, y0, size, size);
            }
        }
        if ($('showGrid').checked) {
            const tilePx = G.TILE * s;
            if (tilePx >= 6) {
                ctx.strokeStyle = 'rgba(255,255,255,0.08)';
                ctx.lineWidth = 1;
                ctx.beginPath();
                const [wx0, wz0] = toWorld(0, 0);
                const [wx1, wz1] = toWorld(w, h);
                for (let x = Math.floor(wx0 / 16) * 16; x <= wx1; x += 16) { const [sx] = toScreen(x, 0); ctx.moveTo(Math.round(sx) + 0.5, 0); ctx.lineTo(Math.round(sx) + 0.5, h); }
                for (let z = Math.floor(wz0 / 16) * 16; z <= wz1; z += 16) { const [, sy] = toScreen(0, z); ctx.moveTo(0, Math.round(sy) + 0.5); ctx.lineTo(w, Math.round(sy) + 0.5); }
                ctx.stroke();
            }
            ctx.strokeStyle = 'rgba(255,255,255,0.35)';
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let cz = 0; cz <= m.maps.length; cz++) { const a = toScreen(0, cz * CHUNK), b = toScreen(m.maps[0].length * CHUNK, cz * CHUNK); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
            for (let cx = 0; cx <= m.maps[0].length; cx++) { const a = toScreen(cx * CHUNK, 0), b = toScreen(cx * CHUNK, m.maps.length * CHUNK); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
            ctx.stroke();
        }
    }
    if ($('showEvents').checked) {
        ctx.font = '11px system-ui, sans-serif';
        for (const e of allEvents()) {
            const [tx, tz, tw, th] = e.r;
            const y = eventHeight(e.kind, e.o);
            const a = toScreen(tx * 16, tz * 16, y);
            const b = toScreen((tx + tw) * 16, (tz + th) * 16, y);
            if (!a || !b) continue;
            const sel = S.selection && S.selection.type === 'event' && S.selection.zone === e.zone && S.selection.uid === e.o._uid;
            const color = KIND_COLOR[e.kind];
            const bw = Math.max(6, b[0] - a[0]), bh = Math.max(6, b[1] - a[1]);
            if (e.kind === 'npcs') {
                const img = spriteImage(e.o.model);
                if (img && bw >= 12) {
                    const fw = Math.min(img.width, img.height);
                    const dh = bw * 1.6;
                    ctx.drawImage(img, 0, 0, fw, fw, a[0] - bw * 0.3, a[1] + bh - dh, bw * 1.6, dh);
                }
                ctx.strokeStyle = color;
                ctx.lineWidth = sel ? 3 : 1.5;
                ctx.beginPath();
                ctx.arc(a[0] + bw / 2, a[1] + bh / 2, Math.max(3, bw / 2.4), 0, Math.PI * 2);
                ctx.stroke();
            } else {
                ctx.globalAlpha = e.fest ? 0.35 : 1;
                ctx.fillStyle = color + (e.kind === 'triggers' ? '33' : '55');
                ctx.fillRect(a[0], a[1], bw, bh);
                ctx.strokeStyle = color;
                ctx.lineWidth = sel ? 3 : 1.5;
                ctx.strokeRect(a[0] + 0.5, a[1] + 0.5, bw - 1, bh - 1);
                ctx.globalAlpha = 1;
            }
            const hovered = S.hover && S.hover[0] >= tx && S.hover[0] < tx + tw && S.hover[1] >= tz && S.hover[1] < tz + th;
            if ((S.view.scale * 16 >= 30 && !e.fest) || sel || hovered) {
                const label = eventLabel(e);
                ctx.fillStyle = 'rgba(0,0,0,0.65)';
                const tw2 = ctx.measureText(label).width;
                ctx.fillRect(a[0], a[1] - 14, tw2 + 6, 13);
                ctx.fillStyle = color;
                ctx.fillText(label, a[0] + 3, a[1] - 4);
            }
        }
    }
    if (is3d()) return;
    // Selection, hover and tool previews
    if (S.selection && S.selection.type === 'tile') drawTileRect(S.selection.gx, S.selection.gz, 1, 1, '#ffffff', 2);
    if (S.selection && S.selection.type === 'cell') {
        const a = toScreen(S.selection.cx * CHUNK, S.selection.cz * CHUNK);
        ctx.strokeStyle = '#5aa9ff'; ctx.lineWidth = 3;
        ctx.strokeRect(a[0], a[1], CHUNK * s, CHUNK * s);
    }
    if (S.drag && S.drag.rect) {
        const r = normRect(S.drag.rect);
        drawTileRect(r[0], r[1], r[2] - r[0], r[3] - r[1], S.tool === 'stamp' ? '#6bd88f' : '#ff6b6b', 2);
    }
    if (S.tool === 'stamp' && S.clipboard && S.hover && !S.drag) {
        const [x0, z0, x1, z1] = S.clipboard.rect;
        drawTileRect(S.hover[0], S.hover[1], x1 - x0, z1 - z0, '#6bd88f', 2, true);
    }
    if (S.clipboard && S.clipboard.matrix === S.matrixName) {
        const [x0, z0, x1, z1] = S.clipboard.rect;
        drawTileRect(S.clipboard.cx * 32 + x0, S.clipboard.cz * 32 + z0, x1 - x0, z1 - z0, '#6bd88f', 1);
    }
    if (S.hover && S.tool !== 'stamp') drawTileRect(S.hover[0], S.hover[1], 1, 1, 'rgba(255,255,255,0.7)', 1);
}

function drawTileRect(gx, gz, tw, th, color, width, dashed) {
    const a = toScreen(gx * 16, gz * 16);
    const b = toScreen((gx + tw) * 16, (gz + th) * 16);
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.setLineDash(dashed ? [6, 4] : []);
    ctx.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
    ctx.setLineDash([]);
}

function scriptName(n) {
    return S.idx.constants.scripts[String(n)] || String(n);
}

function eventLabel(e) {
    const o = e.o;
    if (e.kind === 'npcs') return `#${o.id} ${String(o.model).replace('OBJ_CODE_', '')} · ${scriptName(o.script)}`;
    if (e.kind === 'warps') return `→ ${String(o.zone).replace('ZONE_', '')} #${o.warp}  (warp ${e.i})`;
    if (e.kind === 'triggers') return `trigger ${scriptName(o.script)}`;
    if (o.condition === 2) return 'hidden item';
    if (o.condition >= 3) return 'festival spot';
    return `sign ${scriptName(o.script)}`;
}

function normRect(r) {
    return [Math.min(r[0], r[2]), Math.min(r[1], r[3]), Math.max(r[0], r[2]) + 1, Math.max(r[1], r[3]) + 1];
}

// ---- Tiles ---------------------------------------------------------------------------------------------------------

function tileInfo(gx, gz) {
    const cx = Math.floor(gx / 32), cz = Math.floor(gz / 32);
    const cell = cells[cx + ',' + cz];
    if (!cell || !cell.terrain) return { cx, cz, x: gx - cx * 32, z: gz - cz * 32, cell };
    const x = gx - cx * 32, z = gz - cz * 32;
    return { cx, cz, x, z, cell, values: cell.terrain.cells[z * cell.terrain.width + x] };
}

function heightAt(gx, gz) {
    const t = tileInfo(gx, gz);
    if (!t.values) return 0;
    const [shape, slope, offset] = t.values;
    const tables = S.idx.heights;
    let sl = slope, of = offset;
    if (shape !== 0) {
        const sp = t.cell.terrain.splits[offset];
        if (!sp) return 0;
        sl = sp[0]; of = sp[2];
    }
    const nx = tables.slopes[sl * 3], ny = tables.slopes[sl * 3 + 1], nz = tables.slopes[sl * 3 + 2];
    if (!ny) return 0;
    const lx = t.x * 16 + 8 - 256, lz = t.z * 16 + 8 - 256;
    return Math.round(-(tables.offsets[of] + nx * lx + nz * lz) / ny);
}

// Sets tiles' types in a stroke: one tiles operation for each chunk the stroke touches
function setTileType(gx, gz, fn) {
    const t = tileInfo(gx, gz);
    if (!t.values || matrix(S.matrixName).sourceOnly) return;
    const before = t.values[3];
    const after = fn(before);
    if (after === before) return;
    const key = t.cx + ',' + t.cz;
    let op = S.drag && S.drag.strokeOps && S.drag.strokeOps[key];
    if (!op) {
        op = { op: 'tiles', matrix: S.matrixName, x: t.cx, z: t.cz, set: {} };
        S.ops.push(op);
        if (S.drag) S.drag.strokeOps[key] = op;
    }
    op.set[t.x + ',' + t.z] = { tile_type: after };
    t.values[3] = after;
    t.cell.overlay = null;
    t.cell.terrainKey = t.cell.model + JSON.stringify(cellOps(S.matrixName, t.cx, t.cz).map(clean));
    S.version++;
    requestRender();
}

// ---- Events --------------------------------------------------------------------------------------------------------

function findEvent(zone, uid) {
    for (const kind of KINDS) {
        const o = zoneEvents(zone)[kind].find((e) => e._uid === uid);
        if (o) return { kind, o, i: zoneEvents(zone)[kind].indexOf(o) };
    }
    return null;
}

function setEvent(zone, kind, uid, value) {
    const cur = findEvent(zone, uid);
    if (!cur) return;
    commit(() => {
        S.ops.push({ op: 'event', zone, kind, action: 'set', _uid: uid, match: clean(cur.o), value: clean(value) });
    });
}

function movedEvent(kind, o, gx, gz) {
    const v = JSON.parse(JSON.stringify(o));
    const g = v.grid;
    const snap = $('snapHeight').checked;
    const hgt = snap ? heightAt(gx, gz) : null;
    if (kind === 'npcs') { g.x = gx; g.z = gz; if (snap) g.y = hgt * 4096; }
    if (kind === 'warps') { g.x = gx * 16 + (g.x & 15); g.z = gz * 16 + (g.z & 15); if (snap) g.y = Math.max(0, hgt); }
    if (kind === 'triggers') { g.x = gx; g.z = gz; if (snap) g.y = hgt; }
    if (kind === 'bg_events') { g.x = gx; g.y = gz; if (snap) g.z = hgt; }
    return v;
}

function newEvent(kind, zone, gx, gz) {
    const ev = zoneEvents(zone);
    const h = heightAt(gx, gz);
    if (kind === 'npcs') {
        const id = Math.max(-1, ...ev.npcs.map((n) => n.id)) + 1;
        return { id, model: 'OBJ_CODE_110', movement: 'MOVE_CODE_NONE', type: 'ACTOR_EVENT_TYPE_NONE', flag: 0, script: 0, direction: 'DIR_DOWN', params: [0, 0, 0], area: { width: 0, height: 0 }, grid: { x: gx, z: gz, y: h * 4096 } };
    }
    if (kind === 'warps') return { zone, warp: 0, unk4: 1, transition: 4, grid: { x: gx * 16 + 8, y: Math.max(0, h), z: gz * 16 + 8, width: 1, height: 1, unk0a: 0 } };
    if (kind === 'triggers') return { script: 0, var: 'EVENT_WORK_0x41ac', value: 1, type: 0, grid: { x: gx, z: gz, width: 1, height: 1, y: h }, unk14: 0 };
    return { script: 0, condition: 0, direction: 4, grid: { x: gx, y: gz, z: h } };
}

function eventAt(px, py) {
    if (!$('showEvents').checked) return null;
    let best = null;
    for (const e of allEvents()) {
        const [tx, tz, tw, th] = e.r;
        const y = eventHeight(e.kind, e.o);
        const a = toScreen(tx * 16, tz * 16, y), b = toScreen((tx + tw) * 16, (tz + th) * 16, y);
        if (!a || !b) continue;
        const pad = 3;
        if (px >= a[0] - pad && px <= Math.max(b[0], a[0] + 6) + pad && py >= a[1] - pad && py <= Math.max(b[1], a[1] + 6) + pad) {
            const area = (b[0] - a[0]) * (b[1] - a[1]);
            if (!best || area < best.area || (e.kind === 'npcs' && best.e.kind !== 'npcs')) best = { e, area };
        }
    }
    return best && best.e;
}

// ---- Input ---------------------------------------------------------------------------------------------------------

function setTool(t) {
    S.tool = t;
    for (const b of document.querySelectorAll('#tools button')) b.classList.toggle('on', b.dataset.tool === t);
    const opts = $('toolOptions');
    opts.innerHTML = '';
    const hint = (txt) => { const d = document.createElement('div'); d.className = 'hint'; d.innerHTML = txt; opts.appendChild(d); };
    if (t === 'select') hint('Click an event to edit it, drag it to move it. Click a tile to see and set its type. Right-drag or Space+drag pans, the wheel zooms.');
    if (t === 'block') hint('Drag to block tiles. Shift+drag to clear them.');
    if (t === 'class') {
        const sel = document.createElement('select');
        for (const [v, n] of Object.entries(S.idx.constants.tile_classes)) {
            const o = document.createElement('option');
            o.value = v; o.textContent = `${n} (0x${(+v).toString(16)})`;
            if (+v === S.classBrush) o.selected = true;
            sel.appendChild(o);
        }
        sel.onchange = () => { S.classBrush = +sel.value; };
        opts.appendChild(sel);
        hint('Drag to paint the class. Alt+click picks a tile\'s class.');
    }
    if (t === 'cut') {
        const inp = document.createElement('input');
        inp.type = 'text'; inp.value = S.ground; inp.placeholder = 'ground material (blank: none)';
        inp.onchange = () => { S.ground = inp.value.trim(); };
        const row = document.createElement('div'); row.className = 'row';
        const l = document.createElement('label'); l.textContent = 'Lay ground';
        row.append(l, inp); opts.appendChild(row);
        hint('Drag a rectangle: everything on it goes (trees, rocks, props), the ground material is laid flat at the height around it, and its tiles copy the nearest walkable tile.');
    }
    if (t === 'stamp') hint(S.clipboard ? `Copied ${S.clipboard.rect[2] - S.clipboard.rect[0]}×${S.clipboard.rect[3] - S.clipboard.rect[1]} tiles of ${S.clipboard.model.replace('MAP_MODEL_', '')}. Click to place it; drag to copy another area; Esc to drop it.` : 'Drag a rectangle inside one chunk to copy it (geometry, props and tiles), on this map or another, then click where its top left goes (it can land across chunks). Shift+drag copies another. The overworld map has every route to copy from.');
    if (t === 'matrix') hint('Click a chunk to set which map model it shows and its zone.');
    if (KINDS.includes(t)) hint(`Click a tile to add a ${KIND_LABEL[t]} to the zone there.`);
    requestRender();
}

let spaceDown = false;

function onDown(ev) {
    ov.setPointerCapture(ev.pointerId);
    const px = ev.offsetX, py = ev.offsetY;
    if (is3d()) return;
    if (ev.button === 1 || ev.button === 2 || spaceDown) {
        S.drag = { pan: true, px, py, vx: S.view.x, vz: S.view.z };
        return;
    }
    const tile = tileAt(px, py);
    const sourceOnly = matrix(S.matrixName).sourceOnly;
    if (S.tool === 'select') {
        const e = eventAt(px, py);
        if (e) {
            select({ type: 'event', zone: e.zone, uid: e.o._uid });
            if (!sourceOnly) S.drag = { event: e, start: tile, moved: false };
            return;
        }
        select({ type: 'tile', gx: tile[0], gz: tile[1] });
        return;
    }
    if (sourceOnly && S.tool !== 'stamp') { toast('The overworld is here to copy from: pick one of the hack\'s maps to edit.'); return; }
    if (S.tool === 'block' || S.tool === 'class') {
        if (S.tool === 'class' && ev.altKey) {
            const t = tileInfo(tile[0], tile[1]);
            if (t.values) { S.classBrush = t.values[3] & 0xffff; setTool('class'); }
            return;
        }
        S.undo.push(S.ops.slice());
        S.redo = [];
        S.drag = { paint: true, strokeOps: {}, clear: ev.shiftKey };
        paintAt(tile);
        return;
    }
    if (S.tool === 'cut' || (S.tool === 'stamp' && (!S.clipboard || ev.shiftKey))) {
        S.drag = { rect: [tile[0], tile[1], tile[0], tile[1]] };
        return;
    }
    if (S.tool === 'stamp' && S.clipboard) {
        placeStamp(tile);
        return;
    }
    if (S.tool === 'matrix') {
        const m = matrix(S.matrixName);
        const cx = Math.floor(tile[0] / 32), cz = Math.floor(tile[1] / 32);
        if (m.maps[cz] && m.maps[cz][cx] !== undefined) select({ type: 'cell', cx, cz });
        return;
    }
    if (KINDS.includes(S.tool)) {
        const zone = cellZone(S.matrixName, Math.floor(tile[0] / 32), Math.floor(tile[1] / 32));
        if (!zone) { toast('No zone here.'); return; }
        const uid = newUid();
        const value = newEvent(S.tool, zone, tile[0], tile[1]);
        commit(() => S.ops.push({ op: 'event', zone, kind: S.tool, action: 'add', _uid: uid, value }));
        select({ type: 'event', zone, uid });
        setTool('select');
    }
}

function paintAt(tile) {
    if (S.tool === 'block') setTileType(tile[0], tile[1], (v) => (S.drag.clear ? v & ~G.BLOCKED : v | G.BLOCKED));
    else setTileType(tile[0], tile[1], (v) => (v & ~0xffff) | S.classBrush);
}

function onMove(ev) {
    const px = ev.offsetX, py = ev.offsetY;
    if (is3d()) return;
    const tile = tileAt(px, py);
    S.hover = tile;
    status(tile);
    const d = S.drag;
    if (d && d.pan) {
        S.view.x = d.vx - (px - d.px) / S.view.scale;
        S.view.z = d.vz - (py - d.py) / S.view.scale;
    } else if (d && d.paint) {
        paintAt(tile);
    } else if (d && d.rect) {
        d.rect[2] = tile[0]; d.rect[3] = tile[1];
    } else if (d && d.event) {
        if (tile[0] !== d.start[0] || tile[1] !== d.start[1]) d.moved = true;
        d.to = tile;
    }
    requestRender();
}

function onUp() {
    const d = S.drag;
    S.drag = null;
    if (!d) return;
    if (d.paint) { changed(); return; }
    if (d.event && d.moved && d.to) {
        const e = d.event;
        const dx = d.to[0] - d.start[0], dz = d.to[1] - d.start[1];
        const r = eventRect(e.kind, e.o);
        setEvent(e.zone, e.kind, e.o._uid, movedEvent(e.kind, e.o, r[0] + dx, r[1] + dz));
        return;
    }
    if (d.rect) {
        const r = normRect(d.rect);
        if (S.tool === 'cut') {
            const ops = [];
            let missing = false;
            for (const part of splitRect(r)) {
                const cell = cells[part.cx + ',' + part.cz];
                if (!cell || !cell.geo) continue;
                const groundY = G.groundHeight(cell.terrain, part.local, S.idx.heights);
                const ground = S.ground && cell.geo.materials.some((m) => m.name === S.ground) ? S.ground : null;
                if (S.ground && !ground) missing = true;
                ops.push({ op: 'cut', matrix: S.matrixName, x: part.cx, z: part.cz, rect: part.local, ground, groundY });
            }
            if (missing) toast(`A chunk here has no ${S.ground} material: cleared there without laying ground.`);
            if (ops.length) commit(() => S.ops.push(...ops));
        } else {
            const cx = Math.floor(r[0] / 32), cz = Math.floor(r[1] / 32);
            if (Math.floor((r[2] - 1) / 32) !== cx || Math.floor((r[3] - 1) / 32) !== cz) { toast('Copy from inside one chunk (the grid\'s bright lines).'); requestRender(); return; }
            const cell = cells[cx + ',' + cz];
            if (!cell) return;
            const base = (S.idx.bases || {})[cell.model];
            if (base) toast('This chunk has edits: the stamp copies it as it was before them.');
            S.clipboard = { matrix: S.matrixName, cx, cz, model: base || cell.model, rect: [r[0] - cx * 32, r[1] - cz * 32, r[2] - cx * 32, r[3] - cz * 32], zone: cellZone(S.matrixName, cx, cz) };
            setTool('stamp');
        }
    }
    requestRender();
}

// A rectangle of the matrix's tiles [x0, z0, x1, z1) as the parts in each chunk, in the chunk's own tiles
function splitRect(r) {
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

// Places the copied rectangle with its top left at a tile: one stamp for each chunk it lands on
function placeStamp(tile) {
    const c = S.clipboard;
    const w = c.rect[2] - c.rect[0], h = c.rect[3] - c.rect[1];
    const m = matrix(S.matrixName);
    const srcBundle = (areaOf(c.zone) || {}).prop_bundle;
    const ops = [];
    let noProps = false;
    for (const part of splitRect([tile[0], tile[1], tile[0] + w, tile[1] + h])) {
        if (!m.maps[part.cz] || !m.maps[part.cz][part.cx]) continue;
        const dx = part.global[0] - tile[0], dz = part.global[1] - tile[1];
        const rect = [c.rect[0] + dx, c.rect[1] + dz, c.rect[0] + dx + part.local[2] - part.local[0], c.rect[1] + dz + part.local[3] - part.local[1]];
        const dstBundle = (areaOf(cellZone(S.matrixName, part.cx, part.cz)) || {}).prop_bundle;
        const props = !!srcBundle && srcBundle === dstBundle;
        if (!props) noProps = true;
        ops.push({ op: 'stamp', matrix: S.matrixName, x: part.cx, z: part.cz, from: c.model, rect, to: [part.local[0], part.local[1]], props });
    }
    if (noProps) toast('The two places use different prop sets: copied without props.');
    if (ops.length) commit(() => S.ops.push(...ops));
}

function onWheel(ev) {
    if (is3d()) return;
    ev.preventDefault();
    const [wx, wz] = toWorld(ev.offsetX, ev.offsetY);
    const f = Math.exp(-ev.deltaY * 0.0015);
    S.view.scale = Math.min(8, Math.max(0.02, S.view.scale * f));
    const [nx, nz] = toWorld(ev.offsetX, ev.offsetY);
    S.view.x += wx - nx;
    S.view.z += wz - nz;
    requestRender();
}

function status(tile) {
    if (!tile) { $('status').textContent = ''; return; }
    const t = tileInfo(tile[0], tile[1]);
    let s = `tile ${tile[0]}, ${tile[1]}  ·  chunk ${t.cx}, ${t.cz} (${t.x}, ${t.z})`;
    if (t.cell) s += `  ·  ${String(t.cell.model).replace('MAP_MODEL_', '')}  ·  ${cellZone(S.matrixName, t.cx, t.cz) || ''}`;
    if (t.values) {
        const type = t.values[3];
        const cls = type & 0xffff;
        s += `  ·  ${S.idx.constants.tile_classes[cls] || '0x' + cls.toString(16)}${type & G.BLOCKED ? ', blocked' : ''}  ·  height ${heightAt(tile[0], tile[1])}`;
    }
    $('status').textContent = s;
}

function toast(msg) {
    const t = $('toast');
    t.textContent = msg;
    t.style.display = 'block';
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { t.style.display = 'none'; }, 3500);
}

// ---- Inspector ---------------------------------------------------------------------------------------------------

function select(sel) {
    S.selection = sel;
    inspector();
    requestRender();
}

function el(tag, attrs = {}, ...children) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
        if (k.startsWith('on')) e[k] = v; else if (k === 'class') e.className = v; else e.setAttribute(k, v);
    }
    for (const c of children) e.append(c);
    return e;
}

const LISTS = { model: 'obj_codes', movement: 'move_codes', type: 'actor_event_types', zone: 'zones' };
const DIRS = ['DIR_UP', 'DIR_DOWN', 'DIR_LEFT', 'DIR_RIGHT'];

function datalist(id, values) {
    if (!$(id)) {
        const d = el('datalist', { id });
        for (const v of values) d.appendChild(el('option', { value: v }));
        document.body.appendChild(d);
    }
    return id;
}

// A form for an event: every field, nested ones under their parent's name
function eventForm(value, onApply) {
    const box = el('div');
    const inputs = [];
    const walk = (obj, path) => {
        for (const [k, v] of Object.entries(obj)) {
            if (k === '_uid') continue;
            const p = path.concat(k);
            if (v && typeof v === 'object') { walk(v, p); continue; }
            const inp = el('input', { type: 'text', value: String(v) });
            const list = LISTS[k] && path.length === 0 ? datalist('dl-' + k, S.idx.constants[LISTS[k]]) : k === 'direction' && typeof v === 'string' ? datalist('dl-dir', DIRS) : null;
            if (list) inp.setAttribute('list', list);
            inputs.push([p, inp, typeof v]);
            const label = el('label', { title: p.join('.') }, p.join('.'));
            box.appendChild(el('div', { class: 'row' }, label, inp));
        }
    };
    walk(value, []);
    const apply = el('button', { onclick: () => {
        const v = JSON.parse(JSON.stringify(value));
        for (const [p, inp] of inputs) {
            let o = v;
            for (const k of p.slice(0, -1)) o = o[k];
            const raw = inp.value.trim();
            o[p[p.length - 1]] = /^-?\d+$/.test(raw) ? parseInt(raw, 10) : /^0x[0-9a-f]+$/i.test(raw) && p[p.length - 1] !== 'flag' ? parseInt(raw, 16) : raw;
        }
        onApply(v);
    } }, 'Apply');
    box.appendChild(el('div', { class: 'btns' }, apply));
    return box;
}

function inspector() {
    const box = $('inspector');
    box.innerHTML = '';
    const sel = S.selection;
    const sourceOnly = S.matrixName && matrix(S.matrixName).sourceOnly;
    if (!sel) { box.appendChild(el('div', { class: 'hint' }, 'Click a tile, an event or (Chunk tool) a chunk.')); return; }
    if (sel.type === 'event') {
        const found = findEvent(sel.zone, sel.uid);
        if (!found) { box.appendChild(el('div', { class: 'hint' }, 'Gone.')); return; }
        const { kind, o, i } = found;
        box.appendChild(el('div', {}, el('b', {}, `${KIND_LABEL[kind]} ${i}`), ` of ${sel.zone.replace('ZONE_', '')}`));
        if (o.script !== undefined) box.appendChild(el('div', { class: 'hint' }, `Script ${o.script}${S.idx.constants.scripts[String(o.script)] ? ' = ' + scriptName(o.script) : ''}`));
        if (kind === 'warps') {
            const dest = S.idx.zones[o.zone];
            const go = el('button', { onclick: () => goToWarp(o.zone, o.warp) }, `Go to ${String(o.zone).replace('ZONE_', '')} warp ${o.warp}`);
            box.appendChild(el('div', { class: 'btns' }, go));
            if (!dest) box.appendChild(el('div', { class: 'warn' }, 'That zone is not in the pack.'));
            box.appendChild(el('div', { class: 'hint' }, 'Warps are counted by their place in the list: other zones\' warps lead here by number.'));
        }
        if (sourceOnly) { box.appendChild(el('pre', { class: 'hint' }, JSON.stringify(clean(o), null, 1))); return; }
        box.appendChild(eventForm(clean(o), (v) => setEvent(sel.zone, kind, sel.uid, v)));
        const btns = el('div', { class: 'btns' });
        btns.appendChild(el('button', { onclick: () => {
            const uid = newUid();
            const v = clean(o);
            const r = eventRect(kind, v);
            const moved = movedEvent(kind, v, r[0] + 1, r[1]);
            if (kind === 'npcs') moved.id = Math.max(...zoneEvents(sel.zone).npcs.map((n) => n.id)) + 1;
            commit(() => S.ops.push({ op: 'event', zone: sel.zone, kind, action: 'add', _uid: uid, value: moved }));
            select({ type: 'event', zone: sel.zone, uid });
        } }, 'Duplicate'));
        btns.appendChild(el('button', { class: 'danger', onclick: () => {
            const list = zoneEvents(sel.zone)[kind];
            if (kind === 'warps' && i < list.length - 1 && !confirm('Deleting this warp renumbers the warps after it, which other zones\' warps may lead to. Delete anyway?')) return;
            commit(() => S.ops.push({ op: 'event', zone: sel.zone, kind, action: 'delete', _uid: sel.uid, match: clean(o) }));
            select(null);
        } }, 'Delete'));
        box.appendChild(btns);
        return;
    }
    if (sel.type === 'tile') {
        const t = tileInfo(sel.gx, sel.gz);
        box.appendChild(el('div', {}, el('b', {}, `Tile ${sel.gx}, ${sel.gz}`), ` · chunk ${t.cx}, ${t.cz} at ${t.x}, ${t.z}`));
        if (!t.values) { box.appendChild(el('div', { class: 'hint' }, 'No terrain here.')); return; }
        const [shape, slope, offset, type, diag] = t.values;
        const cls = type & 0xffff;
        box.appendChild(el('div', { class: 'hint' }, `type 0x${type.toString(16)} · shape ${shape} · slope ${slope} · offset ${offset} · diagonal ${diag} · height ${heightAt(sel.gx, sel.gz)}`));
        if (sourceOnly) return;
        const clsSel = el('select');
        const classes = S.idx.constants.tile_classes;
        if (!classes[cls]) clsSel.appendChild(el('option', { value: cls }, `0x${cls.toString(16)}`));
        for (const [v, n] of Object.entries(classes)) {
            const o = el('option', { value: v }, `${n} (0x${(+v).toString(16)})`);
            if (+v === cls) o.selected = true;
            clsSel.appendChild(o);
        }
        clsSel.value = String(cls);
        box.appendChild(el('div', { class: 'row' }, el('label', {}, 'Class'), clsSel));
        const checks = el('div', { class: 'checks' });
        const flagInputs = FLAGS.map(([bit, name]) => {
            const c = el('input', { type: 'checkbox' });
            c.checked = !!((type >>> 16) & bit);
            checks.appendChild(el('label', {}, c, name));
            return [bit, c];
        });
        box.appendChild(checks);
        box.appendChild(el('div', { class: 'btns' }, el('button', { onclick: () => {
            let flags = (type >>> 16) & ~FLAGS.reduce((a, [b]) => a | b, 0);
            for (const [bit, c] of flagInputs) if (c.checked) flags |= bit;
            const nt = ((flags << 16) | +clsSel.value) >>> 0;
            commit(() => { S.drag = null; setTileType(sel.gx, sel.gz, () => nt); });
            inspector();
        } }, 'Apply')));
        return;
    }
    if (sel.type === 'cell') {
        const m = matrix(S.matrixName);
        const model = m.maps[sel.cz][sel.cx];
        const zone = m.zones ? m.zones[sel.cz][sel.cx] : cellZone(S.matrixName, sel.cx, sel.cz);
        box.appendChild(el('div', {}, el('b', {}, `Chunk ${sel.cx}, ${sel.cz}`)));
        const mi = el('input', { type: 'text', value: model, list: datalist('dl-models', Object.keys(S.idx.models)) });
        box.appendChild(el('div', { class: 'row' }, el('label', {}, 'Map model'), mi));
        let zi = null;
        if (m.zones) {
            zi = el('input', { type: 'text', value: zone, list: datalist('dl-zone', S.idx.constants.zones) });
            box.appendChild(el('div', { class: 'row' }, el('label', {}, 'Zone'), zi));
        }
        const pending = cellOps(S.matrixName, sel.cx, sel.cz).length;
        if (pending) box.appendChild(el('div', { class: 'warn' }, `${pending} edit(s) on this chunk are dropped if its model changes.`));
        box.appendChild(el('div', { class: 'hint' }, 'Only models in the pack can be shown; the list has them all. OVERWORLD_2_MAP_OUTTREE is the blocked forest.'));
        if (sourceOnly) return;
        box.appendChild(el('div', { class: 'btns' }, el('button', { onclick: () => {
            const op = { op: 'matrix', matrix: S.matrixName, x: sel.cx, z: sel.cz };
            if (mi.value.trim() && mi.value.trim() !== model) op.model = mi.value.trim();
            if (zi && zi.value.trim() && zi.value.trim() !== zone) op.zone = zi.value.trim();
            if (!op.model && !op.zone) return;
            if (op.model && !S.idx.models[op.model]) { toast(op.model + ' is not in the pack.'); return; }
            commit(() => S.ops.push(op));
            inspector();
        } }, 'Apply')));
    }
}

async function goToWarp(zone, warp) {
    const z = S.idx.zones[zone];
    if (!z) { toast(zone + ' is not in the pack.'); return; }
    const m = z.header.matrix;
    if (!S.idx.matrices[m]) { toast(m + ' is not in the pack.'); return; }
    await showMatrix(m, false);
    const list = zoneEvents(zone).warps;
    const w = list[warp];
    if (w) {
        const r = eventRect('warps', w);
        S.view.x = r[0] * 16 + 8; S.view.z = r[1] * 16 + 8;
        S.view.scale = Math.max(S.view.scale, 1.5);
        select({ type: 'event', zone, uid: w._uid });
    }
    requestRender();
}

// ---- Maps ----------------------------------------------------------------------------------------------------------

async function showMatrix(name, fit = true) {
    if (S.matrixName === name && !fit) return;
    S.matrixName = name;
    $('mapSelect').value = name;
    S.selection = null;
    clearCells();
    inspector();
    const m = matrix(name);
    if (fit) {
        // Fit the chunks that aren't the forest filler
        let x0 = 1e9, z0 = 1e9, x1 = -1e9, z1 = -1e9;
        m.maps.forEach((row, cz) => row.forEach((c, cx) => {
            if (c && (!c.endsWith('OUTTREE') || m.maps.length * row.length <= 4)) {
                x0 = Math.min(x0, cx); z0 = Math.min(z0, cz); x1 = Math.max(x1, cx + 1); z1 = Math.max(z1, cz + 1);
            }
        }));
        if (x0 > x1) { x0 = 0; z0 = 0; x1 = m.maps[0].length; z1 = m.maps.length; }
        const { w, h } = size();
        S.view.x = (x0 + x1) / 2 * CHUNK;
        S.view.z = (z0 + z1) / 2 * CHUNK;
        S.view.scale = Math.min(w / ((x1 - x0) * CHUNK + 64), h / ((z1 - z0) * CHUNK + 64));
    }
    $('loading').style.display = 'flex';
    $('loading').textContent = 'Loading ' + name.replace('MAP_MATRIX_', '') + '…';
    await refreshCells();
    $('loading').style.display = 'none';
    requestRender();
}

function refreshAll() {
    refreshCells();
    inspector();
    summary();
    requestRender();
}

function describe(op) {
    const cell = op.matrix ? `${op.matrix.replace('MAP_MATRIX_', '')} ${op.x},${op.z}` : '';
    if (op.op === 'event') return `${op.action} ${KIND_LABEL[op.kind]} in ${op.zone.replace('ZONE_', '')}`;
    if (op.op === 'tiles') return `${Object.keys(op.set).length} tile(s) in ${cell}`;
    if (op.op === 'cut') return `clear ${op.rect.join(',')} in ${cell}`;
    if (op.op === 'stamp') return `stamp ${op.from.replace('MAP_MODEL_', '')} ${op.rect.join(',')} → ${cell} at ${op.to.join(',')}`;
    if (op.op === 'matrix') return `chunk ${cell}: ${op.model || ''} ${op.zone || ''}`;
    return op.op;
}

function summary() {
    const box = $('changes');
    box.innerHTML = '';
    const ops = compact(S.ops);
    box.appendChild(el('div', {}, `${S.baseOps.length} saved before, ${ops.length} new since.`));
    const list = el('div');
    for (const op of ops.slice(-12)) list.appendChild(el('div', { class: 'hint' }, '· ' + describe(op)));
    box.appendChild(list);
    $('undoBtn').disabled = !S.undo.length;
    $('redoBtn').disabled = !S.redo.length;
}

// ---- Saving --------------------------------------------------------------------------------------------------------

let fileHandle = null;

function output() {
    const ops = compact([...S.baseOps, ...S.ops]);
    return '{\n"version": 1,\n"ops": [\n' + ops.map((o) => JSON.stringify(o)).join(',\n') + '\n]\n}\n';
}

async function save() {
    const text = output();
    if (window.showSaveFilePicker) {
        try {
            if (!fileHandle) fileHandle = await window.showSaveFilePicker({ suggestedName: 'world_edits.json', types: [{ description: 'World edits', accept: { 'application/json': ['.json'] } }] });
            const w = await fileHandle.createWritable();
            await w.write(text);
            await w.close();
            toast('Saved ' + fileHandle.name);
            return;
        } catch (e) {
            if (e.name === 'AbortError') return;
        }
    }
    const a = el('a', { href: URL.createObjectURL(new Blob([text], { type: 'application/json' })), download: 'world_edits.json' });
    document.body.appendChild(a);
    a.click();
    a.remove();
    toast('Downloaded world_edits.json');
}

function openEdits(text) {
    let data;
    try { data = JSON.parse(text); } catch (e) { toast('Not JSON.'); return; }
    const ops = data.ops || [];
    const base = S.baseOps.map(canon);
    const prefix = base.every((b, i) => ops[i] && canon(ops[i]) === b);
    if (!prefix && !confirm('This file doesn\'t start with the edits this pack was made with. Show all of its edits as new?')) return;
    commit(() => adopt(ops.slice(prefix ? base.length : 0)));
}

// Event operations from a file name their thing by its fields: give each the uid of the event it matches, in order,
// so that an edit of an event added earlier finds it
function adopt(ops) {
    S.ops = [];
    for (const op of ops) {
        let o = op;
        if (op.op === 'event') {
            if (op.action === 'add') o = { ...op, _uid: newUid() };
            else {
                derived.version = -1;
                const key = canon(op.match);
                const found = zoneEvents(op.zone)[op.kind].find((e) => canon(e) === key);
                o = { ...op, _uid: found ? found._uid : newUid() };
            }
        }
        S.ops.push(o);
    }
    derived.version = -1;
    return S.ops;
}

// ---- Boot ----------------------------------------------------------------------------------------------------------

function setup3d(on) {
    if (on) {
        if (!orbit) orbit = new OrbitControls(persp, ov);
        orbit.enabled = true;
        persp.position.set(S.view.x, 700, S.view.z + 700);
        orbit.target.set(S.view.x, 0, S.view.z);
        orbit.update();
        orbit.addEventListener('change', requestRender);
    } else if (orbit) {
        orbit.enabled = false;
    }
    requestRender();
}

async function boot() {
    const idx = await pack.loadIndex().catch(() => null);
    if (!idx) { $('loading').textContent = 'No pack/ folder next to index.html: run export_pack.py.'; return; }
    S.idx = idx;
    S.baseOps = (idx.edits && idx.edits.ops) || [];
    const sel = $('mapSelect');
    const names = Object.keys(idx.matrices).sort((a, b) => (b.startsWith('MAP_MATRIX_EFU') - a.startsWith('MAP_MATRIX_EFU')) || a.localeCompare(b));
    for (const n of names) {
        const zs = zonesOfMatrixRaw(idx, n);
        const label = n.replace('MAP_MATRIX_', '') + (idx.matrices[n].source_only ? ' (copy from)' : zs.length ? ' — ' + zs.slice(0, 3).map((z) => z.replace('ZONE_', '')).join(', ') + (zs.length > 3 ? '…' : '') : '');
        sel.appendChild(el('option', { value: n }, label));
    }
    sel.onchange = () => showMatrix(sel.value);
    const tools = $('tools');
    for (const [t, label, key] of TOOLS) tools.appendChild(el('button', { 'data-tool': t, onclick: () => setTool(t) }, label, el('kbd', {}, key)));
    $('legend').innerHTML = Object.entries(KIND_COLOR).map(([k, c]) => `<span><i style="background:${c}"></i>${KIND_LABEL[k]}</span>`).join('');
    for (const id of ['overlay', 'showEvents', 'showGrid', 'snapHeight', 'showFest']) $(id).onchange = () => requestRender();
    $('showProps').onchange = () => { for (const c of Object.values(cells)) if (c.propGroup) c.propGroup.visible = $('showProps').checked; requestRender(); };
    $('show3d').onchange = () => setup3d($('show3d').checked);
    $('saveBtn').onclick = save;
    $('openBtn').onclick = () => $('openFile').click();
    $('openFile').onchange = async () => { const f = $('openFile').files[0]; if (f) openEdits(await f.text()); $('openFile').value = ''; };
    $('undoBtn').onclick = undo;
    $('redoBtn').onclick = redo;
    ov.addEventListener('pointerdown', onDown);
    ov.addEventListener('pointermove', onMove);
    ov.addEventListener('pointerup', onUp);
    ov.addEventListener('pointerleave', () => { S.hover = null; requestRender(); });
    ov.addEventListener('wheel', onWheel, { passive: false });
    ov.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('resize', resize);
    window.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
        if (e.code === 'Space') { spaceDown = true; e.preventDefault(); return; }
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); return; }
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') { e.preventDefault(); redo(); return; }
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); return; }
        if (e.key === 'Escape') { S.clipboard = null; S.drag = null; if (S.tool === 'stamp') setTool('stamp'); requestRender(); return; }
        if (e.key === 'Delete' && S.selection && S.selection.type === 'event') { const b = [...document.querySelectorAll('#inspector button.danger')][0]; if (b) b.click(); return; }
        const t = TOOLS.find(([, , k]) => k.toLowerCase() === e.key.toLowerCase());
        if (t && !e.ctrlKey && !e.metaKey) setTool(t[0]);
    });
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') spaceDown = false; });
    resize();
    setTool('select');
    // Work not yet saved from the last session in this browser
    try {
        const saved = JSON.parse(localStorage.getItem(STORAGE) || 'null');
        if (saved && saved.ops && saved.ops.length && saved.base === canon(S.baseOps) && confirm(`Restore ${saved.ops.length} unsaved edit(s) from last time?`)) {
            adopt(saved.ops);
        }
    } catch (e) { /* storage is a convenience */ }
    summary();
    await showMatrix(names.includes('MAP_MATRIX_EFU_ZONE_1') ? 'MAP_MATRIX_EFU_ZONE_1' : names[0]);
    window.__efu = { S, cells, matrix, zoneEvents, output, compact, requestRender, showMatrix, commit, adopt, changed, refreshCells };
}

function zonesOfMatrixRaw(idx, name) {
    const m = idx.matrices[name];
    const set = new Set();
    if (m.zones && !m.source_only) for (const r of m.zones) for (const z of r) set.add(z);
    if (!m.source_only) for (const [z, v] of Object.entries(idx.zones)) if (v.header.matrix === name) set.add(z);
    return [...set].filter(Boolean);
}

boot();
