// Escape from Unova's world editor: a map matrix seen from above, its chunks' models and props, their collision and
// tile classes, the zones' events, and the edits made to them, which are saved as world_edits.json for
// apply_world_edits.py. Edits are a list of operations (engine.js); everything shown is the pack with them applied.
// The tools work like a paint program's, on the layers ticked in the Layers list.

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import * as pack from './pack.js';
import * as G from './geometry.js';
import * as E from './engine.js';

THREE.ColorManagement.enabled = false;

const { KINDS, clean, canon, newUid, world, matrix, zoneEvents, splitRect } = E;
const CHUNK = 512;
const KIND_LABEL = { npcs: 'NPC', warps: 'Warp', triggers: 'Trigger', bg_events: 'Sign / BG event' };
const KIND_COLOR = { npcs: '#ffd166', warps: '#c77dff', triggers: '#ffef5a', bg_events: '#4cc9f0' };
const FLAGS = [[0x1, 'Collision'], [0x2, 'Water'], [0x4, 'Encounters'], [0x8, '0x08'], [0x20, '0x20'], [0x40, 'Reflect'], [0x80, '0x80'], [0x100, '0x100']];
const TOOLS = [
    ['select', 'Select', 'V'], ['marquee', 'Rectangle', 'R'], ['brush', 'Brush', 'B'],
    ['eraser', 'Eraser', 'E'], ['insert', 'Insert', 'P'], ['chunk', 'Chunk', 'K'],
];
const LAYERS = [['ground', 'Ground'], ['props', 'Props'], ['collision', 'Collision'], ['class', 'Tile class'], ['events', 'Events']];
const OBJECTS = [
    { label: 'Strength boulder', kind: 'npcs', value: { model: 'OBJ_CODE_MODEL_3', script: 10000 } },
    { label: 'Cut tree', kind: 'npcs', value: { model: 'OBJ_CODE_108', script: 10004 } },
    { label: 'Item ball', kind: 'npcs', value: { model: 'OBJ_CODE_110', script: 11008 }, hint: 'Rolls loot when taken. Give it a free event flag to stay taken.' },
    { label: 'Person', kind: 'npcs', value: { model: 'OBJ_CODE_76' } },
    { label: 'Door / warp', kind: 'warps' },
    { label: 'Sign', kind: 'bg_events' },
    { label: 'Trigger', kind: 'triggers' },
];
const ARRIVE = [[0, 'Walking out (none)'], [1, 'Up'], [2, 'Down'], [3, 'Left'], [4, 'Right']];
const STORAGE = 'efu-world-editor-ops-2';

const $ = (id) => document.getElementById(id);
const S = {
    idx: null, matrixName: null, ops: [], baseOps: [], undo: [], redo: [], tool: 'select',
    layers: new Set(['ground', 'props', 'collision', 'class', 'events']),
    selection: null, hover: null, clipboard: null, pasting: false, drag: null,
    brush: { mode: 'block', size: 1, cls: 4 }, eraser: { size: 1, ground: 'grass01ax' },
    insert: null, rot: 0, view: { x: 0, z: 0, scale: 0.5 },
};

function editLayers() {
    return G.LAYERS.filter((l) => S.layers.has(l));
}

// ---- Edits ---------------------------------------------------------------------------------------------------------

function sameCell(a, b) {
    return a.matrix === b.matrix && a.x === b.x && a.z === b.z;
}

// Folds edits of the same thing together, so that the file says each change once
function compact(ops) {
    const out = [];
    for (const op of ops.map(clean)) {
        if (op.op === 'tiles') {
            const last = out[out.length - 1];
            if (last && last.op === 'tiles' && sameCell(last, op)) { out[out.length - 1] = { ...last, set: { ...last.set, ...op.set } }; continue; }
        }
        if ((op.op === 'event' || op.op === 'prop') && op.action !== 'add') {
            const same = (o) => (op.op === 'event' ? o.zone === op.zone && o.kind === op.kind : sameCell(o, op));
            const k = canon(op.match);
            let j = -1;
            for (let i = out.length - 1; i >= 0; i--) {
                const o = out[i];
                if (o.op === 'erase' || o.op === 'copy') { if (op.op === 'prop' && o.matrix === op.matrix) break; continue; }
                if (o.op === op.op && same(o) && o.action !== 'delete' && canon(o.value) === k) { j = i; break; }
            }
            if (j >= 0) {
                const prev = out[j];
                if (op.action === 'set') {
                    if (prev.action === 'set' && canon(prev.match) === canon(op.value)) out.splice(j, 1);
                    else out[j] = { ...prev, value: op.value };
                } else if (prev.action === 'add') out.splice(j, 1);
                else out[j] = { ...prev, action: 'delete', value: undefined };
                if (out[j] && out[j].value === undefined) delete out[j].value;
                continue;
            }
            if (op.action === 'set' && canon(op.match) === canon(op.value)) continue;
        }
        if (op.op === 'lock') {
            // A door's last lock edit says it all, and no lock edit at all is an open door
            const j = out.findIndex((o) => o.op === 'lock' && o.zone === op.zone && o.x === op.x && o.z === op.z);
            if (j >= 0) out.splice(j, 1);
            if (op.locked === false) continue;
        }
        out.push(op);
    }
    return out;
}

// Records new operations, applied to the world, as one step to undo
async function commit(newOps) {
    if (!newOps.length) return;
    await E.preload(newOps);
    S.undo.push(S.ops.slice());
    if (S.undo.length > 300) S.undo.shift();
    S.redo = [];
    for (const op of newOps) { S.ops.push(op); E.applyOp(op); }
    changed();
}

function changed() {
    try { localStorage.setItem(STORAGE, JSON.stringify({ base: canon(S.baseOps), ops: S.ops.map(clean) })); } catch (e) { /* storage is a convenience */ }
    refreshAll();
}

function undo() {
    if (!S.undo.length) return;
    S.redo.push(S.ops);
    S.ops = S.undo.pop();
    E.replay(S.ops);
    changed();
}

function redo() {
    if (!S.redo.length) return;
    S.undo.push(S.ops);
    S.ops = S.redo.pop();
    E.replay(S.ops);
    changed();
}

// ---- Zones -------------------------------------------------------------------------------------------------------

function zonesOfMatrix(name) {
    const m = matrix(name);
    const set = new Set();
    if (m.sourceOnly) return [];
    if (m.zones) for (const r of m.zones) for (const z of r) if (z) set.add(z);
    for (const [z, v] of Object.entries(S.idx.zones)) if (v.header.matrix === name) set.add(z);
    return [...set].filter((z) => S.idx.zones[z]);
}

function cellZone(name, cx, cz) {
    const m = matrix(name);
    if (m.zones && m.zones[cz] && m.zones[cz][cx]) return m.zones[cz][cx];
    return zonesOfMatrix(name)[0] || null;
}

function areaOf(zone) {
    const z = S.idx.zones[zone];
    return z ? S.idx.areas[z.header.area] : null;
}

function bundleAt(cx, cz) {
    const a = areaOf(cellZone(S.matrixName, cx, cz));
    return a && a.prop_bundle;
}

// ---- Rendering resources ----------------------------------------------------------------------------------------

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
        const map = m.uri ? threeTexture(E.textureKey(m.uri), m.sampler) : null;
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
                pos[i * 3] = v[0]; pos[i * 3 + 1] = v[1]; pos[i * 3 + 2] = v[2];
                uv[i * 2] = v[3]; uv[i * 2 + 1] = v[4];
                col[i * 3] = v[5] / 255; col[i * 3 + 1] = v[6] / 255; col[i * 3 + 2] = v[7] / 255;
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

// Props: each bundle's models parsed once by three's loader
const propCache = {};
const propBoxes = {};
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
                    g.scene.updateMatrixWorld(true);
                    const box = new THREE.Box3().setFromObject(g.scene);
                    propBoxes[id] = box.isEmpty() ? new THREE.Box3(new THREE.Vector3(-8, 0, -8), new THREE.Vector3(8, 16, 8)) : box;
                    resolve(g.scene);
                }, () => resolve(null));
            });
        });
    }
    return propCache[id];
}

function yaw(rotation) {
    return 2 * Math.atan2(rotation[1], rotation[3]);
}

function yawQuat(a) {
    const r = (v) => Math.round(v * 1e6) / 1e6;
    return [0, r(Math.sin(a / 2)), 0, r(Math.cos(a / 2))];
}

// The tiles a prop stands on, in its chunk's own tiles [x0, z0, x1, z1), from its model's box turned as it is
function propFootprint(bundle, p) {
    const box = propBoxes[bundle + ':' + p.resId];
    let x0 = -8, x1 = 8, z0 = -8, z1 = 8;
    if (box) { x0 = box.min.x; x1 = box.max.x; z0 = box.min.z; z1 = box.max.z; }
    const a = yaw(p.rotation);
    const c = Math.cos(a), s = Math.sin(a);
    const xs = [], zs = [];
    for (const [x, z] of [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]) { xs.push(x * c + z * s); zs.push(-x * s + z * c); }
    const tx = (v) => (v + p.translation[0] + 256) / 16, tz = (v) => (v + p.translation[2] + 256) / 16;
    const fx0 = Math.floor(tx(Math.min(...xs)) + 0.25), fx1 = Math.ceil(tx(Math.max(...xs)) - 0.25);
    const fz0 = Math.floor(tz(Math.min(...zs)) + 0.25), fz1 = Math.ceil(tz(Math.max(...zs)) - 0.25);
    return [fx0, fz0, Math.max(fx0 + 1, fx1), Math.max(fz0 + 1, fz1)];
}

// ---- Chunks of the shown matrix ---------------------------------------------------------------------------------

const cells = {};   // "cx,cz" -> {cx, cz, src, geoVer, propVer, terVer, group, propGroup, overlay}

function syncCells() {
    if (!S.matrixName) return;
    const m = matrix(S.matrixName);
    const seen = new Set();
    for (let cz = 0; cz < m.maps.length; cz++) {
        for (let cx = 0; cx < m.maps[cz].length; cx++) {
            const k = cx + ',' + cz;
            const v = m.maps[cz][cx] ? E.view(S.matrixName, cx, cz) : null;
            if (!v) continue;
            seen.add(k);
            let cell = cells[k];
            if (!cell) cell = cells[k] = { cx, cz };
            if (cell.src !== v || cell.geoVer !== v.geoVer) {
                if (cell.group) scene.remove(cell.group);
                cell.group = geometryGroup(v.geo);
                cell.group.position.set(cx * CHUNK + CHUNK / 2, 0, cz * CHUNK + CHUNK / 2);
                scene.add(cell.group);
                cell.propVer = -1;
            }
            if (cell.src !== v || cell.propVer !== v.propVer) {
                if (cell.propGroup) cell.group.remove(cell.propGroup);
                cell.propGroup = new THREE.Group();
                cell.propGroup.visible = $('showProps').checked;
                cell.group.add(cell.propGroup);
                placeProps(cell, v.geo.props);
            }
            if (cell.src !== v || cell.terVer !== v.terVer) cell.overlay = null;
            cell.src = v; cell.geoVer = v.geoVer; cell.propVer = v.propVer; cell.terVer = v.terVer;
            cell.model = m.maps[cz][cx];
            cell.geo = v.geo; cell.terrain = v.terrain;
        }
    }
    for (const [k, c] of Object.entries(cells)) if (!seen.has(k)) { if (c.group) scene.remove(c.group); delete cells[k]; }
}

async function placeProps(cell, props) {
    const bundle = bundleAt(cell.cx, cell.cz);
    if (!bundle) return;
    const group = cell.propGroup;
    for (const p of props) {
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

// ---- Rendering ------------------------------------------------------------------------------------------------------

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
let ghost = null;

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
    syncCells();
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
            const type = t.cells[z * t.width + x][3];
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

// Every prop of the shown chunks, in world units
function allProps() {
    const out = [];
    for (const cell of Object.values(cells)) {
        if (!cell.geo) continue;
        cell.geo.props.forEach((p, i) => {
            out.push({ cx: cell.cx, cz: cell.cz, i, p, x: cell.cx * CHUNK + 256 + p.translation[0], z: cell.cz * CHUNK + 256 + p.translation[2], y: p.translation[1] });
        });
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

function drawLock(x, y, size) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = '#ffd166';
    ctx.strokeStyle = '#1a1a1a';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(0, -size * 0.15, size * 0.28, Math.PI, 0);
    ctx.stroke();
    ctx.fillRect(-size * 0.4, -size * 0.15, size * 0.8, size * 0.6);
    ctx.strokeRect(-size * 0.4, -size * 0.15, size * 0.8, size * 0.6);
    ctx.restore();
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
            const sz = CHUNK * s;
            if (x0 > w || y0 > h || x0 + sz < 0 || y0 + sz < 0) continue;
            if (mode !== 'none') {
                const c = cellOverlay(cell, mode);
                if (c) ctx.drawImage(c, x0, y0, sz, sz);
            }
        }
        if ($('showGrid').checked) {
            if (G.TILE * s >= 6) {
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
            ctx.beginPath();
            for (let cz = 0; cz <= m.maps.length; cz++) { const a = toScreen(0, cz * CHUNK), b = toScreen(m.maps[0].length * CHUNK, cz * CHUNK); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
            for (let cx = 0; cx <= m.maps[0].length; cx++) { const a = toScreen(cx * CHUNK, 0), b = toScreen(cx * CHUNK, m.maps.length * CHUNK); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
            ctx.stroke();
        }
        // Props: a diamond on each, to pick it
        if ($('showProps').checked && s * 16 >= 10) {
            for (const pr of allProps()) {
                const [sx, sy] = toScreen(pr.x, pr.z);
                if (sx < -10 || sy < -10 || sx > w + 10 || sy > h + 10) continue;
                const sel = S.selection && S.selection.type === 'prop' && S.selection.cx === pr.cx && S.selection.cz === pr.cz && S.selection.i === pr.i;
                const r = sel ? 6 : 4;
                ctx.fillStyle = sel ? '#ff9f1c' : 'rgba(255,159,28,0.55)';
                ctx.strokeStyle = 'rgba(0,0,0,0.7)';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(sx, sy - r); ctx.lineTo(sx + r, sy); ctx.lineTo(sx, sy + r); ctx.lineTo(sx - r, sy); ctx.closePath();
                ctx.fill(); ctx.stroke();
                if (sel) {
                    const b = bundleAt(pr.cx, pr.cz);
                    const f = propFootprint(b, pr.p);
                    drawTileRect(pr.cx * 32 + f[0], pr.cz * 32 + f[1], f[2] - f[0], f[3] - f[1], '#ff9f1c', 2, true);
                }
            }
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
            if (e.kind === 'warps' && E.lockAt(e.zone, e.o.grid.x, e.o.grid.z)) drawLock(a[0] + bw / 2, a[1] + bh / 2, Math.max(10, Math.min(22, bw * 0.8)));
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
    const sel = S.selection;
    if (sel && sel.type === 'tile') drawTileRect(sel.gx, sel.gz, 1, 1, '#ffffff', 2);
    if (sel && sel.type === 'cell') {
        const a = toScreen(sel.cx * CHUNK, sel.cz * CHUNK);
        ctx.strokeStyle = '#5aa9ff'; ctx.lineWidth = 3;
        ctx.strokeRect(a[0], a[1], CHUNK * s, CHUNK * s);
    }
    if (sel && sel.type === 'area') {
        const r = sel.rect;
        const d = S.drag && S.drag.move ? S.drag.offset : [0, 0];
        if (d[0] || d[1]) drawTileRect(r[0], r[1], r[2] - r[0], r[3] - r[1], 'rgba(255,255,255,0.35)', 1, true);
        drawTileRect(r[0] + d[0], r[1] + d[1], r[2] - r[0], r[3] - r[1], '#ffffff', 2, true, true);
    }
    if (S.drag && S.drag.rect) {
        const r = normRect(S.drag.rect);
        drawTileRect(r[0], r[1], r[2] - r[0], r[3] - r[1], '#ffffff', 1.5, true, true);
    }
    if (S.clipboard && S.clipboard.matrix === S.matrixName && !S.pasting) {
        const r = S.clipboard.rect;
        drawTileRect(r[0], r[1], r[2] - r[0], r[3] - r[1], 'rgba(107,216,143,0.6)', 1, true);
    }
    if (S.hover) {
        const t = S.hover;
        if (S.pasting && S.clipboard) {
            const r = S.clipboard.rect;
            drawTileRect(t[0], t[1], r[2] - r[0], r[3] - r[1], '#6bd88f', 2, true);
        } else if (S.tool === 'brush' || S.tool === 'eraser') {
            const b = brushRect(t);
            drawTileRect(b[0], b[1], b[2] - b[0], b[3] - b[1], S.tool === 'eraser' ? '#ff6b6b' : '#6bd88f', 1.5);
        } else if (S.tool === 'insert' && S.insert && S.insert.type === 'prop') {
            const f = ghostFootprint(t);
            if (f) drawTileRect(f[0], f[1], f[2] - f[0], f[3] - f[1], '#ff9f1c', 1.5, true);
        } else {
            drawTileRect(t[0], t[1], 1, 1, 'rgba(255,255,255,0.7)', 1);
        }
    }
}

function drawTileRect(gx, gz, tw, th, color, width, dashed, marching) {
    const a = toScreen(gx * 16, gz * 16);
    const b = toScreen((gx + tw) * 16, (gz + th) * 16);
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.setLineDash(dashed ? [6, 4] : []);
    ctx.lineDashOffset = marching ? -((performance.now() / 60) % 10) : 0;
    ctx.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
    if (marching) {
        ctx.strokeStyle = 'rgba(0,0,0,0.6)';
        ctx.lineDashOffset += 5;
        ctx.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
    }
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

function inRect(x, z, r) {
    return x >= r[0] && x < r[2] && z >= r[1] && z < r[3];
}

// ---- Tiles ----------------------------------------------------------------------------------------------------------

function tileInfo(gx, gz) {
    const cx = Math.floor(gx / 32), cz = Math.floor(gz / 32);
    const x = gx - cx * 32, z = gz - cz * 32;
    const cell = cells[cx + ',' + cz];
    if (!cell || !cell.terrain) return { cx, cz, x, z, cell };
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

function editable() {
    if (matrix(S.matrixName).sourceOnly) { toast('This map is here to copy from: pick one of the hack\'s maps to edit.'); return false; }
    return true;
}

// Sets a tile's type during a stroke: one tiles operation for each chunk the stroke touches
function strokeTile(gx, gz, fn) {
    const t = tileInfo(gx, gz);
    if (!t.values) return;
    const before = t.values[3];
    const after = fn(before) >>> 0;
    if (after === before) return;
    const k = t.cx + ',' + t.cz;
    let op = S.drag.strokeOps[k];
    if (!op) {
        op = { op: 'tiles', matrix: S.matrixName, x: t.cx, z: t.cz, set: {} };
        S.ops.push(op);
        S.drag.strokeOps[k] = op;
    }
    op.set[t.x + ',' + t.z] = { tile_type: after };
    const st = E.state(S.matrixName, t.cx, t.cz);
    G.tilesOp(st, { set: { [t.x + ',' + t.z]: { tile_type: after } } });
    st.terVer++;
}

function brushRect(t) {
    const n = S.tool === 'eraser' ? S.eraser.size : S.brush.size;
    if (S.tool === 'brush' && S.brush.mode === 'pattern' && S.clipboard) {
        const r = S.clipboard.rect;
        const w = r[2] - r[0], h = r[3] - r[1];
        if (w > 1 || h > 1) {
            const x = r[0] + Math.floor((t[0] - r[0]) / w) * w, z = r[1] + Math.floor((t[1] - r[1]) / h) * h;
            return [x, z, x + w, z + h];
        }
    }
    const o = Math.floor((n - 1) / 2);
    return [t[0] - o, t[1] - o, t[0] - o + n, t[1] - o + n];
}

// ---- Events --------------------------------------------------------------------------------------------------------

function findEvent(zone, uid) {
    for (const kind of KINDS) {
        const list = zoneEvents(zone)[kind];
        const i = list.findIndex((e) => e._uid === uid);
        if (i >= 0) return { kind, o: list[i], i };
    }
    return null;
}

function eventSetOp(zone, kind, o, value) {
    return { op: 'event', zone, kind, action: 'set', _uid: o._uid, match: clean(o), value: clean(value) };
}

function movedEvent(kind, o, gx, gz, dy = null) {
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

// The lock edits that go with a warp moved from one place to another
function lockMoveOps(zone, from, to) {
    const l = E.lockAt(zone, from.grid.x, from.grid.z);
    if (!l || (from.grid.x === to.grid.x && from.grid.z === to.grid.z)) return [];
    return [{ ...clean(l), x: to.grid.x, z: to.grid.z }, { op: 'lock', zone, x: from.grid.x, z: from.grid.z, locked: false }];
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

function propAt(px, py) {
    if (!$('showProps').checked || is3d()) return null;
    let best = null, bestD = 12;
    for (const pr of allProps()) {
        const [sx, sy] = toScreen(pr.x, pr.z);
        const d = Math.hypot(sx - px, sy - py);
        if (d < bestD) { bestD = d; best = pr; }
    }
    return best;
}

// Events whose place is in a rectangle of the shown matrix
function eventsIn(r) {
    return allEvents().filter((e) => !e.fest && inRect(e.r[0], e.r[1], r));
}

// ---- Layered operations ----------------------------------------------------------------------------------------------

function eraseOps(rect) {
    const ops = [];
    const layers = editLayers();
    if (layers.length) {
        let groundY = 0;
        const parts = splitRect(rect).filter((p) => E.view(S.matrixName, p.cx, p.cz));
        if (parts.length) groundY = Math.round(G.groundHeight(E.view(S.matrixName, parts[0].cx, parts[0].cz).terrain, parts[0].local, S.idx.heights));
        const op = { op: 'erase', matrix: S.matrixName, rect, layers };
        if (layers.includes('ground') && S.eraser.ground) { op.ground = S.eraser.ground; op.groundY = groundY; }
        ops.push(op);
    }
    if (S.layers.has('events')) {
        for (const e of eventsIn(rect)) {
            ops.push({ op: 'event', zone: e.zone, kind: e.kind, action: 'delete', _uid: e.o._uid, match: clean(e.o) });
            if (e.kind === 'warps' && E.lockAt(e.zone, e.o.grid.x, e.o.grid.z)) ops.push({ op: 'lock', zone: e.zone, x: e.o.grid.x, z: e.o.grid.z, locked: false });
        }
    }
    return ops;
}

function copyOp(fromMatrix, rect, tos) {
    const layers = editLayers();
    return layers.length ? { op: 'copy', from: { matrix: fromMatrix, rect }, matrix: S.matrixName, to: tos, layers } : null;
}

// Moving a selection: copied to its new place, then whatever of the old place it no longer covers is erased
function moveOps(rect, dx, dz) {
    const dest = [rect[0] + dx, rect[1] + dz, rect[2] + dx, rect[3] + dz];
    const ops = [];
    const layers = editLayers();
    if (layers.length) {
        ops.push(copyOp(S.matrixName, rect, [[dest[0], dest[1]]]));
        const keep = [Math.max(rect[0], dest[0]), Math.max(rect[1], dest[1]), Math.min(rect[2], dest[2]), Math.min(rect[3], dest[3])];
        const rests = [];
        if (keep[0] >= keep[2] || keep[1] >= keep[3]) rests.push(rect);
        else {
            if (rect[1] < keep[1]) rests.push([rect[0], rect[1], rect[2], keep[1]]);
            if (keep[3] < rect[3]) rests.push([rect[0], keep[3], rect[2], rect[3]]);
            if (rect[0] < keep[0]) rests.push([rect[0], keep[1], keep[0], keep[3]]);
            if (keep[2] < rect[2]) rests.push([keep[2], keep[1], rect[2], keep[3]]);
        }
        const events = S.layers.has('events');
        S.layers.delete('events');
        for (const r of rests) ops.push(...eraseOps(r));
        if (events) S.layers.add('events');
    }
    if (S.layers.has('events')) {
        for (const e of eventsIn(rect)) {
            const v = movedEvent(e.kind, e.o, e.r[0] + dx, e.r[1] + dz);
            ops.push(eventSetOp(e.zone, e.kind, e.o, v));
            if (e.kind === 'warps') ops.push(...lockMoveOps(e.zone, e.o, v));
        }
    }
    return ops;
}

function pasteOps(at) {
    const c = S.clipboard;
    const ops = [];
    const op = copyOp(c.matrix, c.rect, [at]);
    if (op) ops.push(op);
    if (S.layers.has('events') && c.events.length) {
        const nextId = {};
        for (const e of c.events) {
            const gx = at[0] + e.r[0] - c.rect[0], gz = at[1] + e.r[1] - c.rect[1];
            const zone = cellZone(S.matrixName, Math.floor(gx / 32), Math.floor(gz / 32));
            if (!zone) continue;
            const v = movedEvent(e.kind, e.o, gx, gz);
            if (e.kind === 'npcs') {
                if (nextId[zone] === undefined) nextId[zone] = Math.max(-1, ...zoneEvents(zone).npcs.map((n) => n.id)) + 1;
                v.id = nextId[zone]++;
            }
            ops.push({ op: 'event', zone, kind: e.kind, action: 'add', _uid: newUid(), value: clean(v) });
        }
    }
    return ops;
}

function copySelection(cut) {
    const sel = S.selection;
    if (!sel || sel.type !== 'area') { toast('Select a rectangle first (Rectangle tool, R).'); return; }
    S.clipboard = { matrix: S.matrixName, rect: sel.rect.slice(), events: S.layers.has('events') ? eventsIn(sel.rect).map((e) => ({ kind: e.kind, o: clean(e.o), r: e.r })) : [] };
    toast(`Copied ${sel.rect[2] - sel.rect[0]}×${sel.rect[3] - sel.rect[1]} tiles (${[...S.layers].join(', ')}). Ctrl+V to paste; the Brush's pattern mode paints with it.`);
    if (cut && editable()) commit(eraseOps(sel.rect));
    setTool(S.tool);
}

// ---- Input ---------------------------------------------------------------------------------------------------------

function setTool(t) {
    S.tool = t;
    if (t !== 'marquee') S.pasting = false;
    for (const b of document.querySelectorAll('#tools button')) b.classList.toggle('on', b.dataset.tool === t);
    const opts = $('toolOptions');
    opts.innerHTML = '';
    const hint = (txt) => opts.appendChild(el('div', { class: 'hint' }, txt));
    const sizes = (obj) => {
        const row = el('div', { class: 'btns' });
        for (const n of [1, 2, 3, 5, 8]) row.appendChild(el('button', { class: obj.size === n ? 'on' : '', onclick: () => { obj.size = n; setTool(t); } }, `${n}×${n}`));
        opts.appendChild(row);
    };
    $('palette').style.display = t === 'insert' ? 'block' : 'none';
    if (t === 'select') hint('Click an event or a prop (orange diamond) to see and edit it, drag it to move it. Click a tile to see and set its type. Right-drag or Space+drag pans, the wheel zooms.');
    if (t === 'marquee') hint('Drag to select a rectangle. Drag inside it to move it, on the ticked layers. Ctrl+C copies, Ctrl+X cuts, Ctrl+V pastes (click to place), Delete erases, Esc lets go. A selection on the overworld map copies from it.');
    if (t === 'brush') {
        const modes = [['block', 'Block'], ['unblock', 'Unblock'], ['class', 'Tile class'], ['pattern', 'Pattern']];
        const row = el('div', { class: 'btns' });
        for (const [m, label] of modes) row.appendChild(el('button', { class: S.brush.mode === m ? 'on' : '', onclick: () => { S.brush.mode = m; setTool(t); } }, label));
        opts.appendChild(row);
        if (S.brush.mode === 'class') {
            const sel = el('select');
            for (const [v, n] of Object.entries(S.idx.constants.tile_classes)) {
                const o = el('option', { value: v }, `${n} (0x${(+v).toString(16)})`);
                if (+v === S.brush.cls) o.selected = true;
                sel.appendChild(o);
            }
            sel.onchange = () => { S.brush.cls = +sel.value; };
            opts.appendChild(sel);
        }
        if (S.brush.mode !== 'pattern' || !S.clipboard || (S.clipboard.rect[2] - S.clipboard.rect[0] === 1 && S.clipboard.rect[3] - S.clipboard.rect[1] === 1)) sizes(S.brush);
        if (S.brush.mode === 'pattern') {
            const c = S.clipboard;
            hint(c ? `Paints ${c.rect[2] - c.rect[0]}×${c.rect[3] - c.rect[1]} tiles of ${c.matrix.replace('MAP_MATRIX_', '')} on the ticked layers, tiled like wallpaper. Alt+click picks one tile to paint with.` : 'Alt+click a tile to paint with it (on the ticked layers), or copy a rectangle with the Rectangle tool to paint with that.');
        } else if (S.brush.mode === 'class') hint('Paints the class. Alt+click picks a tile\'s class.');
        else hint(S.brush.mode === 'block' ? 'Paints collision on (the red overlay).' : 'Clears collision.');
    }
    if (t === 'eraser') {
        sizes(S.eraser);
        const inp = el('input', { type: 'text', value: S.eraser.ground, placeholder: 'ground material (blank: none)' });
        inp.onchange = () => { S.eraser.ground = inp.value.trim(); };
        opts.appendChild(el('div', { class: 'row' }, el('label', {}, 'Lay ground'), inp));
        hint('Drag to erase the ticked layers: ground takes the trees and cliffs away and lays this material flat; props go; collision clears; the class becomes the nearest walkable tile\'s; events go.');
    }
    if (t === 'insert') {
        hint(S.insert ? `Click to place ${S.insert.label}. Q turns it 90°.` : 'Pick something below to place it.');
        palette();
    }
    if (t === 'chunk') hint('Click a chunk to set which map model it shows and its zone.');
    requestRender();
}

let spaceDown = false;

async function onDown(ev) {
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
        const pr = propAt(px, py);
        if (pr) {
            select({ type: 'prop', cx: pr.cx, cz: pr.cz, i: pr.i, key: G.propKey(pr.p) });
            if (!sourceOnly) S.drag = { prop: pr, start: tile, moved: false };
            return;
        }
        select({ type: 'tile', gx: tile[0], gz: tile[1] });
        return;
    }
    if (S.tool === 'marquee') {
        if (S.pasting && S.clipboard) {
            if (!editable()) return;
            await commit(pasteOps(tile));
            const r = S.clipboard.rect;
            S.selection = { type: 'area', rect: [tile[0], tile[1], tile[0] + r[2] - r[0], tile[1] + r[3] - r[1]] };
            if (!ev.shiftKey) S.pasting = false;
            inspector();
            return;
        }
        const sel = S.selection;
        if (sel && sel.type === 'area' && inRect(tile[0], tile[1], sel.rect) && !sourceOnly) {
            S.drag = { move: true, start: tile, offset: [0, 0] };
            return;
        }
        S.drag = { rect: [tile[0], tile[1], tile[0], tile[1]] };
        return;
    }
    if (S.tool === 'chunk') {
        const m = matrix(S.matrixName);
        const cx = Math.floor(tile[0] / 32), cz = Math.floor(tile[1] / 32);
        if (m.maps[cz] && m.maps[cz][cx] !== undefined) select({ type: 'cell', cx, cz });
        return;
    }
    if (S.tool === 'brush' && ev.altKey) {
        const t = tileInfo(tile[0], tile[1]);
        if (S.brush.mode === 'class') { if (t.values) S.brush.cls = t.values[3] & 0xffff; }
        else {
            S.clipboard = { matrix: S.matrixName, rect: [tile[0], tile[1], tile[0] + 1, tile[1] + 1], events: [] };
            S.brush.mode = 'pattern';
        }
        setTool('brush');
        return;
    }
    if (!editable()) return;
    if (S.tool === 'brush' || S.tool === 'eraser') {
        if (S.tool === 'brush' && S.brush.mode === 'pattern' && !S.clipboard) { toast('Alt+click a tile to paint with first.'); return; }
        const need = S.tool === 'eraser' ? null : { block: 'collision', unblock: 'collision', class: 'class' }[S.brush.mode];
        if (need && !S.layers.has(need)) { toast(`The ${need === 'class' ? 'Tile class' : 'Collision'} layer is off.`); return; }
        S.undo.push(S.ops.slice());
        S.redo = [];
        S.drag = { paint: true, strokeOps: {}, done: new Set() };
        if (S.tool === 'brush' && S.brush.mode === 'pattern') {
            await E.preload([{ op: 'copy', from: { matrix: S.clipboard.matrix, rect: S.clipboard.rect }, matrix: S.matrixName, to: [] }]);
            S.drag.snaps = E.snapshot(S.clipboard.matrix, S.clipboard.rect);
        }
        paintAt(tile);
        requestRender();
        return;
    }
    if (S.tool === 'insert') {
        if (!S.insert) { toast('Pick something to place first.'); return; }
        await placeInsert(tile);
    }
}

function paintAt(tile) {
    const d = S.drag;
    const r = brushRect(tile);
    const k = r.join(',');
    if (d.done.has(k)) return;
    d.done.add(k);
    if (S.tool === 'eraser') {
        const ops = eraseOps(r);
        for (const op of ops) { S.ops.push(op); E.applyOp(op); }
        return;
    }
    if (S.brush.mode === 'pattern') {
        const c = S.clipboard;
        const w = c.rect[2] - c.rect[0], h = c.rect[3] - c.rect[1];
        const tos = [];
        for (let x = r[0]; x < r[2]; x += w) for (let z = r[1]; z < r[3]; z += h) tos.push([x, z]);
        let op = d.patternOp;
        if (!op) {
            op = d.patternOp = copyOp(c.matrix, c.rect, []);
            if (!op) return;
            S.ops.push(op);
        }
        op.to.push(...tos);
        E.applyOp({ ...op, to: tos }, d.snaps);
        return;
    }
    for (let x = r[0]; x < r[2]; x++) {
        for (let z = r[1]; z < r[3]; z++) {
            if (S.brush.mode === 'block') strokeTile(x, z, (v) => v | G.BLOCKED);
            else if (S.brush.mode === 'unblock') strokeTile(x, z, (v) => v & ~G.BLOCKED);
            else strokeTile(x, z, (v) => (v & ~0xffff) | S.brush.cls);
        }
    }
}

// Lines between pointer events, so a fast stroke leaves no gaps
function strokeTo(from, to) {
    const n = Math.max(Math.abs(to[0] - from[0]), Math.abs(to[1] - from[1]));
    for (let i = 1; i <= n; i++) paintAt([Math.round(from[0] + (to[0] - from[0]) * i / n), Math.round(from[1] + (to[1] - from[1]) * i / n)]);
}

function onMove(ev) {
    const px = ev.offsetX, py = ev.offsetY;
    if (is3d()) return;
    const tile = tileAt(px, py);
    const last = S.hover;
    S.hover = tile;
    status(tile);
    const d = S.drag;
    if (d && d.pan) {
        S.view.x = d.vx - (px - d.px) / S.view.scale;
        S.view.z = d.vz - (py - d.py) / S.view.scale;
    } else if (d && d.paint) {
        if (last) strokeTo(last, tile); else paintAt(tile);
    } else if (d && d.rect) {
        d.rect[2] = tile[0]; d.rect[3] = tile[1];
    } else if (d && d.move) {
        d.offset = [tile[0] - d.start[0], tile[1] - d.start[1]];
    } else if (d && (d.event || d.prop)) {
        if (tile[0] !== d.start[0] || tile[1] !== d.start[1]) d.moved = true;
        d.to = tile;
    }
    updateGhost(tile);
    requestRender();
}

async function onUp() {
    const d = S.drag;
    S.drag = null;
    if (!d) return;
    if (d.paint) { changed(); return; }
    if (d.event && d.moved && d.to) {
        const e = d.event;
        const cur = findEvent(e.zone, e.o._uid);
        if (!cur) return;
        const r = eventRect(e.kind, cur.o);
        const v = movedEvent(e.kind, cur.o, r[0] + d.to[0] - d.start[0], r[1] + d.to[1] - d.start[1]);
        await commit([eventSetOp(e.zone, e.kind, cur.o, v), ...(e.kind === 'warps' ? lockMoveOps(e.zone, cur.o, v) : [])]);
        return;
    }
    if (d.prop && d.moved && d.to) {
        await commit(movePropOps(d.prop, d.to[0] - d.start[0], d.to[1] - d.start[1], 0));
        return;
    }
    if (d.move) {
        const [dx, dz] = d.offset;
        if (dx || dz) {
            const r = S.selection.rect;
            await commit(moveOps(r, dx, dz));
            S.selection = { type: 'area', rect: [r[0] + dx, r[1] + dz, r[2] + dx, r[3] + dz] };
        }
        requestRender();
        return;
    }
    if (d.rect) {
        const r = normRect(d.rect);
        select({ type: 'area', rect: r });
    }
    requestRender();
}

// A prop moved by tiles and turned by quarter turns: an edit of its chunk, or out of one chunk into another
function movePropOps(pr, dx, dz, turns) {
    const p = pr.p;
    const gx = pr.x + dx * 16, gz = pr.z + dz * 16;
    const cx = Math.floor(gx / CHUNK), cz = Math.floor(gz / CHUNK);
    const m = matrix(S.matrixName);
    if (!m.maps[cz] || !m.maps[cz][cx]) { toast('No chunk there.'); return []; }
    let y = p.translation[1];
    if ($('snapHeight').checked && (dx || dz)) {
        const t0 = [Math.floor(pr.x / 16), Math.floor(pr.z / 16)];
        y += heightAt(t0[0] + dx, t0[1] + dz) - heightAt(t0[0], t0[1]);
    }
    const value = { resId: p.resId, translation: [gx - cx * CHUNK - 256, y, gz - cz * CHUNK - 256], rotation: turns ? yawQuat(yaw(p.rotation) + turns * Math.PI / 2) : p.rotation.slice(), scale: p.scale.slice() };
    const match = { resId: p.resId, translation: p.translation.slice(), rotation: p.rotation.slice(), scale: p.scale.slice() };
    if (cx === pr.cx && cz === pr.cz) return [{ op: 'prop', matrix: S.matrixName, x: cx, z: cz, action: 'set', match, value }];
    if (bundleAt(cx, cz) !== bundleAt(pr.cx, pr.cz)) { toast('That chunk uses another prop set.'); return []; }
    return [{ op: 'prop', matrix: S.matrixName, x: pr.cx, z: pr.cz, action: 'delete', match },
        { op: 'prop', matrix: S.matrixName, x: cx, z: cz, action: 'add', value }];
}

function blockTilesOps(cx, cz, f) {
    const ops = [];
    for (const part of splitRect([cx * 32 + f[0], cz * 32 + f[1], cx * 32 + f[2], cz * 32 + f[3]])) {
        const v = E.view(S.matrixName, part.cx, part.cz);
        if (!v || !v.terrain) continue;
        const set = {};
        for (let x = part.local[0]; x < part.local[2]; x++) {
            for (let z = part.local[1]; z < part.local[3]; z++) set[x + ',' + z] = { tile_type: (v.terrain.cells[z * 32 + x][3] | G.BLOCKED) >>> 0 };
        }
        ops.push({ op: 'tiles', matrix: S.matrixName, x: part.cx, z: part.cz, set });
    }
    return ops;
}

async function placeInsert(tile) {
    const it = S.insert;
    const cx = Math.floor(tile[0] / 32), cz = Math.floor(tile[1] / 32);
    if (it.type === 'object') {
        const zone = cellZone(S.matrixName, cx, cz);
        if (!zone) { toast('No zone here.'); return; }
        const value = newEvent(it.kind, zone, tile[0], tile[1]);
        Object.assign(value, it.value || {});
        const uid = newUid();
        await commit([{ op: 'event', zone, kind: it.kind, action: 'add', _uid: uid, value }]);
        select({ type: 'event', zone, uid });
        if (it.kind === 'warps') toast('Door placed: set where it leads in the panel.');
        return;
    }
    const bundle = bundleAt(cx, cz);
    if (bundle !== it.bundle) { toast('This chunk uses another prop set: pick from its own.'); return; }
    const value = { resId: it.resId, translation: [(tile[0] - cx * 32) * 16 + 8 - 256, heightAt(tile[0], tile[1]), (tile[1] - cz * 32) * 16 + 8 - 256], rotation: yawQuat(S.rot * Math.PI / 2), scale: [1, 1, 1] };
    const ops = [{ op: 'prop', matrix: S.matrixName, x: cx, z: cz, action: 'add', value }];
    if ($('blockUnder') && $('blockUnder').checked) ops.push(...blockTilesOps(cx, cz, propFootprint(bundle, value)));
    await commit(ops);
}

function ghostFootprint(tile) {
    const it = S.insert;
    if (!it || it.type !== 'prop') return null;
    const cx = Math.floor(tile[0] / 32), cz = Math.floor(tile[1] / 32);
    const p = { resId: it.resId, translation: [(tile[0] - cx * 32) * 16 + 8 - 256, 0, (tile[1] - cz * 32) * 16 + 8 - 256], rotation: yawQuat(S.rot * Math.PI / 2) };
    const f = propFootprint(it.bundle, p);
    return [cx * 32 + f[0], cz * 32 + f[1], cx * 32 + f[2], cz * 32 + f[3]];
}

async function updateGhost(tile) {
    const it = S.tool === 'insert' ? S.insert : null;
    const want = it && it.type === 'prop' && tile ? it.bundle + ':' + it.resId : null;
    if (!want) { if (ghost) { scene.remove(ghost); ghost = null; } return; }
    if (!ghost || ghost.userData.id !== want) {
        if (ghost) scene.remove(ghost);
        ghost = null;
        const scn = await propModel(it.bundle, it.resId);
        if (!scn || !S.insert || S.insert.bundle + ':' + S.insert.resId !== want) return;
        if (ghost) scene.remove(ghost);
        ghost = SkeletonUtils.clone(scn);
        ghost.userData.id = want;
        scene.add(ghost);
    }
    const t = S.hover || tile;
    ghost.position.set(t[0] * 16 + 8, heightAt(t[0], t[1]), t[1] * 16 + 8);
    ghost.quaternion.set(...yawQuat(S.rot * Math.PI / 2));
    requestRender();
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
    if (S.selection && S.selection.type === 'area') { const r = S.selection.rect; s += `  ·  selection ${r[2] - r[0]}×${r[3] - r[1]}`; }
    $('status').textContent = s;
}

function toast(msg) {
    const t = $('toast');
    t.textContent = msg;
    t.style.display = 'block';
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { t.style.display = 'none'; }, 4000);
}

// ---- Insert palette ------------------------------------------------------------------------------------------------

let thumbRenderer = null;
const thumbs = {};

function thumbnail(bundle, resId, img) {
    const id = bundle + ':' + resId;
    if (thumbs[id]) { img.src = thumbs[id]; return; }
    propModel(bundle, resId).then((scn) => {
        if (!scn) return;
        if (!thumbRenderer) {
            thumbRenderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
            thumbRenderer.outputColorSpace = THREE.LinearSRGBColorSpace;
            thumbRenderer.setSize(96, 96);
        }
        const sc = new THREE.Scene();
        sc.add(new THREE.AmbientLight(0xffffff, 3));
        sc.add(SkeletonUtils.clone(scn));
        const box = propBoxes[id];
        const c = box.getCenter(new THREE.Vector3());
        const r = Math.max(8, box.getSize(new THREE.Vector3()).length() / 2);
        const cam = new THREE.OrthographicCamera(-r, r, r, -r, -r * 10, r * 10);
        cam.position.set(c.x + r, c.y + r * 1.1, c.z + r * 1.6);
        cam.lookAt(c);
        thumbRenderer.render(sc, cam);
        thumbs[id] = thumbRenderer.domElement.toDataURL();
        img.src = thumbs[id];
    });
}

function palette() {
    const box = $('palette');
    box.innerHTML = '';
    const filter = el('input', { type: 'text', placeholder: 'Filter (door, fence, rock…)', value: S.paletteFilter || '' });
    filter.oninput = () => { S.paletteFilter = filter.value; paletteItems(); };
    box.appendChild(filter);
    const turn = el('div', { class: 'row' }, el('label', {}, 'Turn'), el('button', { onclick: () => { S.rot = (S.rot + 1) % 4; palette(); updateGhost(S.hover); } }, `${S.rot * 90}° (Q)`));
    const block = el('input', { type: 'checkbox', id: 'blockUnder' });
    block.checked = S.blockUnder !== false;
    block.onchange = () => { S.blockUnder = block.checked; };
    box.appendChild(turn);
    box.appendChild(el('div', { class: 'checks' }, el('label', {}, block, 'Block the tiles under a prop')));
    box.appendChild(el('div', { id: 'palItems' }));
    paletteItems();
}

function paletteItems() {
    const list = $('palItems');
    if (!list) return;
    list.innerHTML = '';
    const f = (S.paletteFilter || '').toLowerCase();
    const pick = (item) => { S.insert = item; setTool('insert'); };
    const isOn = (item) => S.insert && S.insert.label === item.label && S.insert.type === item.type;
    list.appendChild(el('h3', {}, 'Objects'));
    const objs = el('div', { class: 'pal' });
    for (const o of OBJECTS) {
        if (f && !o.label.toLowerCase().includes(f)) continue;
        const item = { type: 'object', ...o };
        const img = el('img');
        const url = o.value && o.value.model ? pack.sprite(o.value.model) : null;
        if (url) {
            // The sprite's first frame
            const raw = new Image();
            raw.onload = () => {
                const c = document.createElement('canvas');
                const fw = Math.min(raw.width, raw.height);
                c.width = fw; c.height = fw;
                c.getContext('2d').drawImage(raw, 0, 0, fw, fw, 0, 0, fw, fw);
                img.src = c.toDataURL();
            };
            raw.src = url;
        }
        const tile = el('div', { class: 'palItem' + (isOn(item) ? ' on' : ''), title: o.hint || o.label, onclick: () => pick(item) }, url ? img : el('i', { class: 'swatch', style: `background:${KIND_COLOR[o.kind]}` }), el('span', {}, o.label));
        objs.appendChild(tile);
    }
    list.appendChild(objs);
    const center = toWorld(size().w / 2, size().h / 2);
    let cx = Math.floor(center[0] / CHUNK), cz = Math.floor(center[1] / CHUNK);
    if (S.hover) { cx = Math.floor(S.hover[0] / 32); cz = Math.floor(S.hover[1] / 32); }
    const bundles = new Set();
    for (const c of Object.values(cells)) { const b = bundleAt(c.cx, c.cz); if (b) bundles.add(b); }
    const first = bundleAt(cx, cz);
    const order = [...bundles].sort((a, b) => (b === first) - (a === first) || a.localeCompare(b));
    pack.loadIndex().then(() => {
        for (const b of order) {
            pack.loadProps(b).then((entries) => {
                if (!entries || !$('palItems')) return;
                const items = Object.entries(entries).filter(([, e]) => !f || e.name.toLowerCase().includes(f)).sort((a, b2) => a[1].name.localeCompare(b2[1].name));
                if (!items.length) return;
                list.appendChild(el('h3', {}, 'Props: ' + b.replace('FIELD_PROPS_', '').toLowerCase()));
                const grid = el('div', { class: 'pal' });
                for (const [resId, e] of items) {
                    const item = { type: 'prop', bundle: b, resId: +resId, label: e.name };
                    const img = el('img', { loading: 'lazy' });
                    const tile = el('div', { class: 'palItem' + (S.insert && S.insert.type === 'prop' && S.insert.bundle === b && S.insert.resId === +resId ? ' on' : ''), title: `${e.name} (${resId})`, onclick: () => pick(item) }, img, el('span', {}, e.name));
                    grid.appendChild(tile);
                    thumbnail(b, +resId, img);
                }
                list.appendChild(grid);
            });
        }
    });
}

// ---- Inspector -----------------------------------------------------------------------------------------------------

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

function row(label, input) {
    return el('div', { class: 'row' }, el('label', { title: label }, label), input);
}

// A form for an event: every field, nested ones under their parent's name
function eventForm(value, onApply) {
    const box = el('div');
    const inputs = [];
    const walk = (obj, path) => {
        for (const [k, v] of Object.entries(obj)) {
            if (k === '_uid' || k === 'unk0a') continue;
            const p = path.concat(k);
            if (v && typeof v === 'object') { walk(v, p); continue; }
            const inp = el('input', { type: 'text', value: String(v) });
            const list = LISTS[k] && path.length === 0 ? datalist('dl-' + k, S.idx.constants[LISTS[k]]) : k === 'direction' && typeof v === 'string' ? datalist('dl-dir', DIRS) : null;
            if (list) inp.setAttribute('list', list);
            inputs.push([p, inp]);
            box.appendChild(row(p.join('.'), inp));
        }
    };
    walk(value, []);
    box.appendChild(el('div', { class: 'btns' }, el('button', { onclick: () => {
        const v = JSON.parse(JSON.stringify(value));
        for (const [p, inp] of inputs) {
            let o = v;
            for (const k of p.slice(0, -1)) o = o[k];
            const raw = inp.value.trim();
            o[p[p.length - 1]] = /^-?\d+$/.test(raw) ? parseInt(raw, 10) : /^0x[0-9a-f]+$/i.test(raw) && p[p.length - 1] !== 'flag' ? parseInt(raw, 16) : raw;
        }
        onApply(v);
    } }, 'Apply')));
    return box;
}

// The door panel: where a warp leads, how the player arrives, and its lock
function doorPanel(zone, o) {
    const box = el('div', { class: 'feature' });
    box.appendChild(el('h3', {}, 'Door'));
    const zi = el('input', { type: 'text', value: o.zone, list: datalist('dl-zone', S.idx.constants.zones) });
    const wi = el('select');
    const fillDoors = () => {
        wi.innerHTML = '';
        const dz = zi.value.trim();
        const list = S.idx.zones[dz] ? zoneEvents(dz).warps : [];
        if (!list.length) wi.appendChild(el('option', { value: o.warp }, `warp ${o.warp}`));
        list.forEach((w, i) => wi.appendChild(el('option', { value: i }, `#${i} at ${Math.floor(w.grid.x / 16)}, ${Math.floor(w.grid.z / 16)} → ${String(w.zone).replace('ZONE_', '')}`)));
        wi.value = String(dz === o.zone ? o.warp : 0);
    };
    zi.onchange = fillDoors;
    fillDoors();
    const fi = el('select');
    for (const [v, n] of ARRIVE) fi.appendChild(el('option', { value: v }, n));
    fi.value = String(o.unk4 || 0);
    box.appendChild(row('Leads to', zi));
    box.appendChild(row('Its door', wi));
    box.appendChild(row('Arrive facing', fi));
    const lock = E.lockAt(zone, o.grid.x, o.grid.z);
    const li = el('input', { type: 'checkbox' }); li.checked = !!lock;
    const ki = el('input', { type: 'text', value: (lock && lock.item) || '', placeholder: 'none: never opens', list: datalist('dl-items', S.idx.constants.items || []) });
    const ci = el('input', { type: 'checkbox' }); ci.checked = !!(lock && lock.consume);
    const ri = el('input', { type: 'checkbox' }); ri.checked = !!(lock && lock.relock);
    const lockBox = el('div', {}, row('Key item', ki), el('div', { class: 'checks' }, el('label', {}, ci, 'Uses up the key'), el('label', {}, ri, 'Locks again each raid')));
    const sync = () => { lockBox.style.display = li.checked ? 'block' : 'none'; };
    li.onchange = sync; sync();
    box.appendChild(el('div', { class: 'checks' }, el('label', {}, li, 'Locked')));
    box.appendChild(lockBox);
    box.appendChild(el('div', { class: 'hint' }, 'A locked door says so when walked into. With a key item it opens for good once the player has it; without one it stays shut.'));
    const btns = el('div', { class: 'btns' });
    btns.appendChild(el('button', { onclick: async () => {
        const v = JSON.parse(JSON.stringify(clean(o)));
        v.zone = zi.value.trim(); v.warp = +wi.value; v.unk4 = +fi.value;
        if (v.zone && !S.idx.constants.zones.includes(v.zone)) { toast(v.zone + ' is not a zone.'); return; }
        const item = ki.value.trim();
        if (item && S.idx.constants.items && !S.idx.constants.items.includes(item)) { toast(item + ' is not an item.'); return; }
        const ops = [];
        if (canon(v) !== canon(clean(o))) ops.push(eventSetOp(zone, 'warps', o, v));
        const want = li.checked ? { op: 'lock', zone, x: o.grid.x, z: o.grid.z, locked: true, item: item || null, consume: ci.checked, relock: ri.checked } : null;
        if (want && (!lock || canon({ ...clean(lock), locked: true }) !== canon(want))) ops.push(want);
        if (!want && lock) ops.push({ op: 'lock', zone, x: o.grid.x, z: o.grid.z, locked: false });
        await commit(ops);
    } }, 'Apply'));
    btns.appendChild(el('button', { onclick: () => goToWarp(zi.value.trim(), +wi.value) }, 'Show its door'));
    btns.appendChild(el('button', { title: 'Sets the door it leads to to lead back here', onclick: async () => {
        const dz = zi.value.trim();
        const target = S.idx.zones[dz] && zoneEvents(dz).warps[+wi.value];
        if (!target) { toast('No such door.'); return; }
        const here = zoneEvents(zone).warps.findIndex((w) => w._uid === o._uid);
        const v = { ...clean(target), zone, warp: here };
        if (canon(v) === canon(clean(target))) { toast('It already leads back here.'); return; }
        await commit([eventSetOp(dz, 'warps', target, v)]);
        toast(`${dz.replace('ZONE_', '')} #${wi.value} now leads back here.`);
    } }, 'Make it two-way'));
    box.appendChild(btns);
    return box;
}

function inspector() {
    const box = $('inspector');
    box.innerHTML = '';
    const sel = S.selection;
    const sourceOnly = S.matrixName && matrix(S.matrixName).sourceOnly;
    if (!sel) { box.appendChild(el('div', { class: 'hint' }, 'Click a tile, an event, a prop or (Chunk tool) a chunk.')); return; }
    if (sel.type === 'event') {
        const found = findEvent(sel.zone, sel.uid);
        if (!found) { box.appendChild(el('div', { class: 'hint' }, 'Gone.')); return; }
        const { kind, o, i } = found;
        box.appendChild(el('div', {}, el('b', {}, `${KIND_LABEL[kind]} ${i}`), ` of ${sel.zone.replace('ZONE_', '')}`));
        if (o.script !== undefined) box.appendChild(el('div', { class: 'hint' }, `Script ${o.script}${S.idx.constants.scripts[String(o.script)] ? ' = ' + scriptName(o.script) : ''}`));
        if (kind === 'warps') {
            if (!sourceOnly) box.appendChild(doorPanel(sel.zone, o));
            box.appendChild(el('div', { class: 'hint' }, 'Warps are counted by their place in the list: other zones\' warps lead here by number.'));
        }
        const preset = kind === 'npcs' && OBJECTS.find((p) => p.value && p.value.model === o.model && (p.value.script === undefined || p.value.script === o.script));
        if (preset && preset.hint) box.appendChild(el('div', { class: 'hint' }, preset.hint));
        if (sourceOnly) { box.appendChild(el('pre', { class: 'hint' }, JSON.stringify(clean(o), null, 1))); return; }
        const details = el('details', kind === 'warps' ? {} : { open: '' }, el('summary', {}, 'All fields'));
        details.appendChild(eventForm(clean(o), (v) => commit([eventSetOp(sel.zone, kind, o, v), ...(kind === 'warps' ? lockMoveOps(sel.zone, o, v) : [])])));
        box.appendChild(details);
        const btns = el('div', { class: 'btns' });
        btns.appendChild(el('button', { onclick: async () => {
            const uid = newUid();
            const r = eventRect(kind, o);
            const moved = movedEvent(kind, clean(o), r[0] + 1, r[1]);
            if (kind === 'npcs') moved.id = Math.max(...zoneEvents(sel.zone).npcs.map((n) => n.id)) + 1;
            await commit([{ op: 'event', zone: sel.zone, kind, action: 'add', _uid: uid, value: moved }]);
            select({ type: 'event', zone: sel.zone, uid });
        } }, 'Duplicate'));
        btns.appendChild(el('button', { class: 'danger', onclick: async () => {
            const list = zoneEvents(sel.zone)[kind];
            if (kind === 'warps' && i < list.length - 1 && !confirm('Deleting this warp renumbers the warps after it, which other zones\' warps may lead to. Delete anyway?')) return;
            const ops = [{ op: 'event', zone: sel.zone, kind, action: 'delete', _uid: sel.uid, match: clean(o) }];
            if (kind === 'warps' && E.lockAt(sel.zone, o.grid.x, o.grid.z)) ops.push({ op: 'lock', zone: sel.zone, x: o.grid.x, z: o.grid.z, locked: false });
            await commit(ops);
            select(null);
        } }, 'Delete'));
        box.appendChild(btns);
        return;
    }
    if (sel.type === 'prop') {
        const pr = allProps().find((q) => q.cx === sel.cx && q.cz === sel.cz && G.propKey(q.p) === sel.key) || allProps().find((q) => q.cx === sel.cx && q.cz === sel.cz && q.i === sel.i);
        if (!pr) { box.appendChild(el('div', { class: 'hint' }, 'Gone.')); return; }
        sel.i = pr.i; sel.key = G.propKey(pr.p);
        const bundle = bundleAt(pr.cx, pr.cz);
        const name = (pack.propName && pack.propName(bundle, pr.p.resId)) || `prop ${pr.p.resId}`;
        box.appendChild(el('div', {}, el('b', {}, name), ` · chunk ${pr.cx}, ${pr.cz}`));
        box.appendChild(el('div', { class: 'hint' }, `id ${pr.p.resId} · at ${pr.p.translation.map((v) => Math.round(v * 10) / 10).join(', ')} · turned ${Math.round(yaw(pr.p.rotation) * 180 / Math.PI)}°`));
        if (sourceOnly) return;
        const btns = el('div', { class: 'btns' });
        btns.appendChild(el('button', { onclick: async () => { await commit(movePropOps(pr, 0, 0, 1)); } }, 'Turn 90°'));
        btns.appendChild(el('button', { onclick: async () => { await commit(blockTilesOps(pr.cx, pr.cz, propFootprint(bundle, pr.p))); toast('Blocked the tiles under it.'); } }, 'Block its tiles'));
        btns.appendChild(el('button', { class: 'danger', onclick: async () => {
            await commit([{ op: 'prop', matrix: S.matrixName, x: pr.cx, z: pr.cz, action: 'delete', match: { resId: pr.p.resId, translation: pr.p.translation, rotation: pr.p.rotation, scale: pr.p.scale } }]);
            select(null);
        } }, 'Delete'));
        box.appendChild(btns);
        // A door: the warp on or beside it
        const gx = Math.floor(pr.x / 16), gz = Math.floor(pr.z / 16);
        const zone = cellZone(S.matrixName, pr.cx, pr.cz);
        const near = allEvents().filter((e) => e.kind === 'warps' && Math.abs(e.r[0] - gx) <= 1 && Math.abs(e.r[1] - gz) <= 1);
        if (near.length) {
            const e = near.sort((a, b) => (Math.abs(a.r[0] - gx) + Math.abs(a.r[1] - gz)) - (Math.abs(b.r[0] - gx) + Math.abs(b.r[1] - gz)))[0];
            box.appendChild(doorPanel(e.zone, e.o));
        } else if (/door|gate|shutter|entrance/i.test(name) && zone) {
            box.appendChild(el('div', { class: 'btns' }, el('button', { onclick: async () => {
                const uid = newUid();
                await commit([{ op: 'event', zone, kind: 'warps', action: 'add', _uid: uid, value: newEvent('warps', zone, gx, gz) }]);
                select({ type: 'event', zone, uid });
            } }, 'Make it a door (add a warp)')));
        }
        return;
    }
    if (sel.type === 'area') {
        const r = sel.rect;
        box.appendChild(el('div', {}, el('b', {}, `Selection ${r[2] - r[0]}×${r[3] - r[1]}`), ` from ${r[0]}, ${r[1]}`));
        box.appendChild(el('div', { class: 'hint' }, `Layers: ${[...S.layers].join(', ') || 'none'}. ${eventsIn(r).length} event(s) inside.`));
        const btns = el('div', { class: 'btns' });
        btns.appendChild(el('button', { onclick: () => copySelection(false) }, 'Copy'));
        if (!sourceOnly) {
            btns.appendChild(el('button', { onclick: () => copySelection(true) }, 'Cut'));
            btns.appendChild(el('button', { class: 'danger', onclick: () => commit(eraseOps(r)) }, 'Erase'));
            btns.appendChild(el('button', { onclick: () => {
                const ops = [];
                for (const part of splitRect(r)) {
                    const v = E.view(S.matrixName, part.cx, part.cz);
                    if (!v || !v.terrain) continue;
                    const set = {};
                    for (let x = part.local[0]; x < part.local[2]; x++) for (let z = part.local[1]; z < part.local[3]; z++) set[x + ',' + z] = { tile_type: (v.terrain.cells[z * 32 + x][3] | G.BLOCKED) >>> 0 };
                    ops.push({ op: 'tiles', matrix: S.matrixName, x: part.cx, z: part.cz, set });
                }
                commit(ops);
            } }, 'Block all'));
        }
        if (S.clipboard) btns.appendChild(el('button', { onclick: () => { S.pasting = true; setTool('marquee'); } }, 'Paste…'));
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
        for (const [v, n] of Object.entries(classes)) clsSel.appendChild(el('option', { value: v }, `${n} (0x${(+v).toString(16)})`));
        clsSel.value = String(cls);
        box.appendChild(row('Class', clsSel));
        const checks = el('div', { class: 'checks' });
        const flagInputs = FLAGS.map(([bit, name]) => {
            const c = el('input', { type: 'checkbox' });
            c.checked = !!((type >>> 16) & bit);
            checks.appendChild(el('label', {}, c, name));
            return [bit, c];
        });
        box.appendChild(checks);
        box.appendChild(el('div', { class: 'btns' }, el('button', { onclick: async () => {
            let flags = (type >>> 16) & ~FLAGS.reduce((a, [b]) => a | b, 0);
            for (const [bit, c] of flagInputs) if (c.checked) flags |= bit;
            const nt = ((flags << 16) | +clsSel.value) >>> 0;
            await commit([{ op: 'tiles', matrix: S.matrixName, x: t.cx, z: t.cz, set: { [t.x + ',' + t.z]: { tile_type: nt } } }]);
        } }, 'Apply')));
        return;
    }
    if (sel.type === 'cell') {
        const m = matrix(S.matrixName);
        const model = m.maps[sel.cz][sel.cx];
        const zone = m.zones ? m.zones[sel.cz][sel.cx] : cellZone(S.matrixName, sel.cx, sel.cz);
        box.appendChild(el('div', {}, el('b', {}, `Chunk ${sel.cx}, ${sel.cz}`)));
        const mi = el('input', { type: 'text', value: model, list: datalist('dl-models', Object.keys(S.idx.models)) });
        box.appendChild(row('Map model', mi));
        let zi = null;
        if (m.zones) {
            zi = el('input', { type: 'text', value: zone, list: datalist('dl-zone', S.idx.constants.zones) });
            box.appendChild(row('Zone', zi));
        }
        box.appendChild(el('div', { class: 'hint' }, 'A new model drops the edits made to this chunk before. Only models in the pack can be shown; OVERWORLD_2_MAP_OUTTREE is the blocked forest.'));
        if (sourceOnly) return;
        box.appendChild(el('div', { class: 'btns' }, el('button', { onclick: async () => {
            const op = { op: 'matrix', matrix: S.matrixName, x: sel.cx, z: sel.cz };
            if (mi.value.trim() && mi.value.trim() !== model) op.model = mi.value.trim();
            if (zi && zi.value.trim() && zi.value.trim() !== zone) op.zone = zi.value.trim();
            if (!op.model && !op.zone) return;
            if (op.model && !S.idx.models[op.model]) { toast(op.model + ' is not in the pack.'); return; }
            await commit([op]);
        } }, 'Apply')));
    }
}

async function goToWarp(zone, warp) {
    const z = S.idx.zones[zone];
    if (!z) { toast(zone + ' is not in the pack.'); return; }
    const m = z.header.matrix;
    if (!S.idx.matrices[m]) { toast(m + ' is not in the pack.'); return; }
    await showMatrix(m, false);
    const w = zoneEvents(zone).warps[warp];
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
        let x0 = 1e9, z0 = 1e9, x1 = -1e9, z1 = -1e9;
        m.maps.forEach((r, cz) => r.forEach((c, cx) => {
            if (c && (!c.endsWith('OUTTREE') || m.maps.length * r.length <= 4)) {
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
    await E.loadMatrix(name);
    $('loading').style.display = 'none';
    if (S.tool === 'insert') palette();
    requestRender();
}

function refreshAll() {
    inspector();
    summary();
    requestRender();
}

function describe(op) {
    const cell = op.matrix ? `${op.matrix.replace('MAP_MATRIX_', '')} ${op.x},${op.z}` : '';
    const rect = (r) => `${r[2] - r[0]}×${r[3] - r[1]} at ${r[0]},${r[1]}`;
    if (op.op === 'event') return `${op.action} ${KIND_LABEL[op.kind]} in ${op.zone.replace('ZONE_', '')}`;
    if (op.op === 'tiles') return `${Object.keys(op.set).length} tile(s) in ${cell}`;
    if (op.op === 'erase') return `erase ${rect(op.rect)} (${op.layers.join(', ')})`;
    if (op.op === 'copy') return `copy ${rect(op.from.rect)} to ${op.to.length > 1 ? op.to.length + ' places' : op.to[0].join(',')} (${op.layers.join(', ')})`;
    if (op.op === 'prop') return `${op.action} prop in ${cell}`;
    if (op.op === 'lock') return `${op.locked === false ? 'unlock' : 'lock'} a door in ${op.zone.replace('ZONE_', '')}${op.item ? ' (' + op.item.replace('ITEM_', '') + ')' : ''}`;
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

function layerBoxes() {
    const box = $('layers');
    box.innerHTML = '';
    const all = el('input', { type: 'checkbox' });
    all.checked = LAYERS.every(([l]) => S.layers.has(l));
    all.onchange = () => { for (const [l] of LAYERS) all.checked ? S.layers.add(l) : S.layers.delete(l); layerBoxes(); };
    box.appendChild(el('label', { class: 'all' }, all, 'All'));
    LAYERS.forEach(([l, label], i) => {
        const c = el('input', { type: 'checkbox' });
        c.checked = S.layers.has(l);
        c.onchange = () => { c.checked ? S.layers.add(l) : S.layers.delete(l); layerBoxes(); };
        box.appendChild(el('label', { title: `Alt+${i + 1}` }, c, label));
    });
    if (S.selection && S.selection.type === 'area') inspector();
}

// ---- Saving --------------------------------------------------------------------------------------------------------

let fileHandle = null;

function output() {
    const ops = compact([...S.baseOps, ...S.ops]);
    return '{\n"version": 2,\n"ops": [\n' + ops.map((o) => JSON.stringify(o)).join(',\n') + '\n]\n}\n';
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

async function openEdits(text) {
    let data;
    try { data = JSON.parse(text); } catch (e) { toast('Not JSON.'); return; }
    const ops = data.ops || [];
    const base = S.baseOps.map(canon);
    const prefix = base.every((b, i) => ops[i] && canon(ops[i]) === b);
    if (!prefix && !confirm('This file doesn\'t start with the edits this pack was made with. Show all of its edits as new?')) return;
    S.undo.push(S.ops.slice());
    await adopt(ops.slice(prefix ? base.length : 0));
    changed();
}

// Operations from a file: event edits name their event by its fields, so each gets the uid of the event it matches
// as the edits before it leave the world
async function adopt(ops) {
    await E.preload(ops);
    E.replay([]);
    S.ops = [];
    for (const op of ops) {
        let o = op;
        if (op.op === 'event') {
            if (op.action === 'add') o = { ...op, _uid: newUid() };
            else {
                const k = canon(op.match);
                const found = zoneEvents(op.zone)[op.kind].find((e) => canon(e) === k);
                o = { ...op, _uid: found ? found._uid : newUid() };
            }
        }
        S.ops.push(o);
        E.applyOp(o);
    }
}

// ---- Boot ----------------------------------------------------------------------------------------------------------

function setup3d(on) {
    if (on) {
        if (!orbit) { orbit = new OrbitControls(persp, ov); orbit.addEventListener('change', requestRender); }
        orbit.enabled = true;
        persp.position.set(S.view.x, 700, S.view.z + 700);
        orbit.target.set(S.view.x, 0, S.view.z);
        orbit.update();
    } else if (orbit) {
        orbit.enabled = false;
    }
    requestRender();
}

function zonesOfMatrixRaw(idx, name) {
    const m = idx.matrices[name];
    const set = new Set();
    if (m.zones && !m.source_only) for (const r of m.zones) for (const z of r) set.add(z);
    if (!m.source_only) for (const [z, v] of Object.entries(idx.zones)) if (v.header.matrix === name) set.add(z);
    return [...set].filter(Boolean);
}

function onKey(e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
    const k = e.key.toLowerCase();
    const mod = e.ctrlKey || e.metaKey;
    if (e.code === 'Space') { spaceDown = true; e.preventDefault(); return; }
    if (mod && k === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); return; }
    if (mod && k === 'y') { e.preventDefault(); redo(); return; }
    if (mod && k === 's') { e.preventDefault(); save(); return; }
    if (mod && k === 'c') { e.preventDefault(); copySelection(false); return; }
    if (mod && k === 'x') { e.preventDefault(); copySelection(true); return; }
    if (mod && k === 'v') { e.preventDefault(); if (S.clipboard) { S.pasting = true; setTool('marquee'); S.pasting = true; toast('Click where the top left goes. Shift+click to paste again.'); } return; }
    if (mod && k === 'a') { e.preventDefault(); for (const [l] of LAYERS) S.layers.add(l); layerBoxes(); return; }
    if (e.altKey && /^[1-5]$/.test(e.key)) {
        e.preventDefault();
        const l = LAYERS[+e.key - 1][0];
        S.layers.has(l) ? S.layers.delete(l) : S.layers.add(l);
        layerBoxes();
        return;
    }
    if (e.key === 'Escape') {
        S.pasting = false; S.drag = null;
        if (S.selection && S.selection.type === 'area') select(null);
        if (S.tool === 'insert') { S.insert = null; setTool('insert'); updateGhost(null); }
        requestRender();
        return;
    }
    if (e.key === 'Delete' || e.key === 'Backspace') {
        const sel = S.selection;
        if (sel && sel.type === 'area') { if (editable()) commit(eraseOps(sel.rect)); return; }
        if (sel && (sel.type === 'event' || sel.type === 'prop')) { const b = [...document.querySelectorAll('#inspector button.danger')][0]; if (b) b.click(); }
        return;
    }
    if (k === 'q' && !mod) {
        if (S.tool === 'insert') { S.rot = (S.rot + 1) % 4; palette(); updateGhost(S.hover); return; }
        if (S.selection && S.selection.type === 'prop') { const b = [...document.querySelectorAll('#inspector button')].find((x) => x.textContent === 'Turn 90°'); if (b) b.click(); return; }
    }
    const t = TOOLS.find(([, , key]) => key.toLowerCase() === k);
    if (t && !mod && !e.altKey) setTool(t[0]);
}

async function boot() {
    const idx = await pack.loadIndex().catch(() => null);
    if (!idx) { $('loading').textContent = 'No pack/ folder next to index.html: run export_pack.py.'; return; }
    S.idx = idx;
    S.baseOps = (idx.edits && idx.edits.ops) || [];
    E.init(idx, S.baseOps);
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
    $('legend').innerHTML = Object.entries(KIND_COLOR).map(([k, c]) => `<span><i style="background:${c}"></i>${KIND_LABEL[k]}</span>`).join('') + '<span><i style="background:#ff9f1c;transform:rotate(45deg)"></i>Prop</span>';
    for (const id of ['overlay', 'showEvents', 'showGrid', 'snapHeight', 'showFest']) $(id).onchange = () => requestRender();
    $('showProps').onchange = () => { for (const c of Object.values(cells)) if (c.propGroup) c.propGroup.visible = $('showProps').checked; requestRender(); };
    $('show3d').onchange = () => setup3d($('show3d').checked);
    $('saveBtn').onclick = save;
    $('openBtn').onclick = () => $('openFile').click();
    $('openFile').onchange = async () => { const f = $('openFile').files[0]; if (f) await openEdits(await f.text()); $('openFile').value = ''; };
    $('undoBtn').onclick = undo;
    $('redoBtn').onclick = redo;
    ov.addEventListener('pointerdown', onDown);
    ov.addEventListener('pointermove', onMove);
    ov.addEventListener('pointerup', onUp);
    ov.addEventListener('pointerleave', () => { S.hover = null; updateGhost(null); requestRender(); });
    ov.addEventListener('wheel', onWheel, { passive: false });
    ov.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('resize', resize);
    window.addEventListener('keydown', onKey);
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') spaceDown = false; });
    // The selection's border marches
    setInterval(() => { if (S.selection && S.selection.type === 'area' && !is3d()) requestRender(); }, 120);
    resize();
    layerBoxes();
    setTool('select');
    try {
        const saved = JSON.parse(localStorage.getItem(STORAGE) || 'null');
        if (saved && saved.ops && saved.ops.length && saved.base === canon(S.baseOps) && confirm(`Restore ${saved.ops.length} unsaved edit(s) from last time?`)) await adopt(saved.ops);
    } catch (e) { /* storage is a convenience */ }
    summary();
    await showMatrix(names.includes('MAP_MATRIX_EFU_ZONE_1') ? 'MAP_MATRIX_EFU_ZONE_1' : names[0]);
    window.__efu = { S, E, cells, output, compact, commit, adopt, showMatrix, setTool, select, requestRender, allProps, copySelection, moveOps, eraseOps, pasteOps };
}

boot();
