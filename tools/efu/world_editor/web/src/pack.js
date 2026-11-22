// The data pack: classic scripts in pack/ that call EFU.<kind>(...), loaded on demand, so the editor runs from a
// plain folder (file://), where fetch and modules can't read files

const store = { index: null, models: {}, textures: {}, props: {}, sprites: {} };
const loading = {};

window.EFU = {
    index: (data) => { store.index = data; },
    model: (name, data) => { store.models[name] = data; },
    textures: (data) => { Object.assign(store.textures, data); },
    props: (bundle, data) => { store.props[bundle] = data; },
    sprites: (data) => { store.sprites = data; },
};

function script(src) {
    if (!loading[src]) {
        loading[src] = new Promise((resolve, reject) => {
            const s = document.createElement('script');
            s.src = src;
            s.onload = () => resolve();
            s.onerror = () => reject(new Error('missing ' + src));
            document.head.appendChild(s);
        });
    }
    return loading[src];
}

export async function loadIndex() {
    await script('pack/index.js');
    await script('pack/actors.js');
    return store.index;
}

export function index() {
    return store.index;
}

export async function loadModel(name) {
    const info = store.index.models[name];
    if (!info) return null;
    await script('pack/models/' + info.folder + '.js');
    return store.models[name];
}

export async function loadTextures(keys) {
    const files = new Set();
    for (const k of keys) {
        const f = store.index.textures[k];
        if (f !== undefined && !store.textures[k]) files.add(f);
    }
    await Promise.all([...files].map((f) => script('pack/textures/' + f + '.js')));
}

export function texture(key) {
    return store.textures[key];
}

export async function loadProps(bundle) {
    if (!store.index.props[bundle]) return null;
    await script('pack/props/' + bundle + '.js');
    return store.props[bundle];
}

export function propName(bundle, resId) {
    const b = store.props[bundle];
    return b && b[resId] ? b[resId].name : null;
}

export function sprite(code) {
    return store.sprites[String(code)];
}

export function b64ToBuffer(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
}

export function normalize(path) {
    const out = [];
    for (const part of path.split('/')) {
        if (part === '..') out.pop();
        else if (part && part !== '.') out.push(part);
    }
    return out.join('/');
}
