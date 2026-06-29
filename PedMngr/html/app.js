// ============================================================
// PedMngr JavaScript v2.3 — Model-specific outfits, model memory
// ============================================================

const $ = (id) => document.getElementById(id);
const $$ = (sel) => document.querySelectorAll(sel);

let COMPONENTS   = [];
let PROPS        = [];
let OVERLAYS     = [];
let PED_MODELS   = [];
let HAIR_COLORS  = [];
let currentData  = null;
let hairColorMap = {};
let forceOpen    = false;

const FACE_FEATURES = [
    "Nose Width", "Nose Peak Height", "Nose Peak Length", "Nose Bone Height",
    "Nose Peak Lowering", "Nose Bone Twist", "Eyebrow Height", "Eyebrow Depth",
    "Cheekbone Height", "Cheekbone Width", "Cheek Width", "Eye Opening",
    "Lip Thickness", "Jaw Bone Width", "Jaw Bone Depth", "Chin Height",
    "Chin Depth", "Chin Width", "Chin Hole Size", "Neck Thickness"
];

// ============================================================
// NUI MESSAGE LISTENER
// ============================================================

window.addEventListener('message', (event) => {
    const d = event.data;
    if (!d.action) return;

    switch (d.action) {
        case 'open':
            COMPONENTS  = d.components  || [];
            PROPS       = d.props       || [];
            OVERLAYS    = d.overlays    || [];
            PED_MODELS  = d.pedModels   || [];
            HAIR_COLORS = d.hairColors  || [];
            currentData = d.currentData;
            forceOpen   = d.forceOpen   || false;

            hairColorMap = {};
            HAIR_COLORS.forEach(c => { hairColorMap[c[0]] = c[1]; });

            populateModelSelector();
            renderAll();
            renderSavedOutfits(d.savedOutfits || []);
            updateForceOpenUI();
            $('app').classList.remove('hidden');
            $('camPanel').classList.remove('hidden');
            setCamActive('full');
            nuiFetch('listOutfits', {});
            break;

        case 'close':
            $('app').classList.add('hidden');
            $('camPanel').classList.add('hidden');
            forceOpen = false;
            closeCodeModal();
            break;

        case 'refreshData':
            currentData = d.data;
            renderAll();
            break;

        case 'outfitList':
            renderSavedOutfits(d.outfits || []);
            break;
    }
});

// ============================================================
// NUI FETCH HELPER
// ============================================================

function nuiFetch(endpoint, data) {
    return fetch('https://' + GetParentResourceName() + '/' + endpoint, {
        method: 'POST',
        body: JSON.stringify(data || {})
    }).then(r => r.json()).catch(() => null);
}

// ============================================================
// TABS
// ============================================================

$$('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        $$('.tab-btn').forEach(b => b.classList.remove('active'));
        $$('.tab-panel').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        $('tab-' + btn.dataset.tab).classList.add('active');
    });
});

// ============================================================
// CLOSE + FORCE OPEN UI
// ============================================================

function updateForceOpenUI() {
    const closeBtn = $('closeBtn');
    const hint = $('forceOpenHint');
    if (forceOpen) {
        if (closeBtn) closeBtn.style.display = 'none';
        if (hint) hint.style.display = 'block';
        $('app').classList.add('force-open');
    } else {
        if (closeBtn) closeBtn.style.display = '';
        if (hint) hint.style.display = 'none';
        $('app').classList.remove('force-open');
    }
}

$('closeBtn').addEventListener('click', () => {
    if (forceOpen) return;
    nuiFetch('close');
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !forceOpen) nuiFetch('close');
});

// ============================================================
// ARROW BUTTONS — Delegated handler for ALL sliders
// ============================================================

$('app').addEventListener('click', (e) => {
    const btn = e.target.closest('.arrow-btn');
    if (!btn) return;
    const targetId = btn.dataset.target;
    const delta = parseInt(btn.dataset.delta);
    if (!targetId || isNaN(delta)) return;

    const slider = $(targetId);
    if (!slider) return;

    const newVal = Math.max(parseInt(slider.min), Math.min(parseInt(slider.max), parseInt(slider.value) + delta));
    slider.value = newVal;
    slider.dispatchEvent(new Event('input'));
});

// ============================================================
// CAMERA PANEL
// ============================================================

function setCamActive(viewName) {
    $$('.cam-btn').forEach(b => b.classList.toggle('active', b.dataset.view === viewName));
    nuiFetch('setCameraView', { view: viewName });
}

$('camPanel').addEventListener('click', (e) => {
    const btn = e.target.closest('.cam-btn');
    if (!btn) return;

    if (btn.id === 'rotLeft') {
        nuiFetch('rotatePedDelta', { delta: -25 });
        return;
    }
    if (btn.id === 'rotRight') {
        nuiFetch('rotatePedDelta', { delta: 25 });
        return;
    }

    setCamActive(btn.dataset.view);
});

// Helper to create arrow-wrapped slider HTML
function sliderWithArrows(id, min, max, value, extraClasses) {
    return `
        <button class="arrow-btn arrow-left" data-target="${id}" data-delta="-1" title="Previous">&#9664;</button>
        <input type="range" class="${extraClasses || ''}" id="${id}" min="${min}" max="${max}" value="${value}">
        <button class="arrow-btn arrow-right" data-target="${id}" data-delta="1" title="Next">&#9654;</button>
    `;
}

// ============================================================
// PED MODEL SELECTOR
// ============================================================

function populateModelSelector() {
    const sel = $('modelSelect');
    sel.innerHTML = '';
    PED_MODELS.forEach(m => {
        const opt = document.createElement('option');
        opt.value = m.hash;
        opt.textContent = m.name;
        sel.appendChild(opt);
    });

    if (currentData && currentData.model) {
        for (let i = 0; i < sel.options.length; i++) {
            if (parseInt(sel.options[i].value) === currentData.model) {
                sel.selectedIndex = i;
                break;
            }
        }
    }
}

$('modelSelect').addEventListener('change', async () => {
    const model = $('modelSelect').value;
    const res = await nuiFetch('setPedModel', { model: parseInt(model) });
    if (res && res.currentData) {
        currentData = res.currentData;
        renderAll();
    }
    // Refresh outfit list for new model
    await nuiFetch('listOutfits', {});
});

// ============================================================
// RENDER ALL
// ============================================================

function renderAll() {
    if (!currentData) return;
    renderClothing();
    renderProps();
    renderFaceBlend();
    renderFaceFeatures();
    renderHair();
    renderOverlays();
}

// ============================================================
// CLOTHING COMPONENTS
// ============================================================

function renderClothing() {
    const container = $('clothing-list');
    container.innerHTML = '';

    COMPONENTS.forEach(comp => {
        const id   = comp.id;
        const cur  = (currentData.components || {})[id.toString()] || { drawable: 0, texture: 0 };
        const info = (currentData.compInfo   || {})[id.toString()] || { maxDrawable: 255, maxTexture: 15 };

        const drawRow = document.createElement('div');
        drawRow.className = 'comp-row';
        drawRow.innerHTML = `
            <span class="comp-name">${comp.name}</span>
            <div class="slider-wrap">
                ${sliderWithArrows(`cs-${id}`, 0, info.maxDrawable, cur.drawable, 'comp-slider')}
            </div>
            <span class="comp-val" id="cv-${id}">${cur.drawable}/${info.maxDrawable}</span>
            <span></span>
        `;
        container.appendChild(drawRow);

        const texRow = document.createElement('div');
        texRow.className = 'tex-row';
        texRow.innerHTML = `
            <span class="tex-label">&#8627; Texture</span>
            <div class="slider-wrap">
                ${sliderWithArrows(`ts-${id}`, 0, info.maxTexture, cur.texture, 'comp-slider')}
            </div>
            <span class="comp-val" id="tv-${id}">${cur.texture}/${info.maxTexture}</span>
            <span></span>
        `;
        container.appendChild(texRow);

        const drawSlider = $(`cs-${id}`);
        const texSlider  = $(`ts-${id}`);
        const drawVal    = $(`cv-${id}`);
        const texVal     = $(`tv-${id}`);

        async function onDrawableChange() {
            const drawable = parseInt(drawSlider.value);
            drawVal.textContent = drawable + '/' + drawSlider.max;

            // TEXTURE RESET FIX: different drawables can have completely
            // different texture counts. Reset to 0 and apply it in the
            // SAME call -- previously the stale old texture was sent
            // along with the new drawable, and only the SLIDER's display
            // got corrected afterward, leaving the ped actually wearing
            // the old/invalid texture index until it was nudged by hand.
            texSlider.value = 0;
            texVal.textContent = '0/' + texSlider.max;

            const res = await nuiFetch('setComponent', {
                componentId: id,
                drawable,
                texture: 0
            });
            if (res && res.maxTexture !== undefined) {
                texSlider.max = res.maxTexture;
                const applied = (res.texture !== undefined) ? res.texture : 0;
                texSlider.value = applied;
                texVal.textContent = applied + '/' + res.maxTexture;
            }
        }

        function onTextureChange() {
            const drawable = parseInt(drawSlider.value);
            const texture  = parseInt(texSlider.value);
            texVal.textContent = texture + '/' + texSlider.max;
            nuiFetch('setComponent', { componentId: id, drawable, texture });
        }

        drawSlider.addEventListener('input', onDrawableChange);
        texSlider.addEventListener('input', onTextureChange);
    });
}

// ============================================================
// PROPS
// ============================================================

function renderProps() {
    const container = $('props-list');
    container.innerHTML = '';

    PROPS.forEach(prop => {
        const id   = prop.id;
        const cur  = (currentData.props    || {})[id.toString()] || { drawable: -1, texture: 0 };
        const info = (currentData.propInfo || {})[id.toString()] || { maxDrawable: 100, maxTexture: 10 };

        const drawRow = document.createElement('div');
        drawRow.className = 'comp-row';
        drawRow.innerHTML = `
            <span class="comp-name">${prop.name}</span>
            <div class="slider-wrap">
                ${sliderWithArrows(`ps-${id}`, -1, info.maxDrawable, cur.drawable, 'comp-slider')}
            </div>
            <span class="comp-val" id="pv-${id}">${cur.drawable < 0 ? 'Off' : cur.drawable + '/' + info.maxDrawable}</span>
            <button class="comp-remove" id="pr-${id}" title="Remove">&#10005;</button>
        `;
        container.appendChild(drawRow);

        const texRow = document.createElement('div');
        texRow.className = 'tex-row';
        texRow.innerHTML = `
            <span class="tex-label">&#8627; Texture</span>
            <div class="slider-wrap">
                ${sliderWithArrows(`pt-${id}`, 0, info.maxTexture, Math.max(0, cur.texture), 'comp-slider')}
            </div>
            <span class="comp-val" id="ptv-${id}">${Math.max(0, cur.texture)}/${info.maxTexture}</span>
            <span></span>
        `;
        container.appendChild(texRow);

        const drawSlider = $(`ps-${id}`);
        const texSlider  = $(`pt-${id}`);
        const drawVal    = $(`pv-${id}`);
        const texVal     = $(`ptv-${id}`);
        const removeBtn  = $(`pr-${id}`);

        async function onDrawableChange() {
            const drawable = parseInt(drawSlider.value);
            drawVal.textContent = drawable < 0 ? 'Off' : drawable + '/' + drawSlider.max;

            // Same texture-reset fix as clothing components above.
            texSlider.value = 0;
            texVal.textContent = '0/' + texSlider.max;

            const res = await nuiFetch('setProp', {
                propId: id,
                drawable,
                texture: 0
            });
            if (res && res.maxTexture !== undefined) {
                texSlider.max = res.maxTexture;
                const applied = (res.texture !== undefined) ? res.texture : 0;
                texSlider.value = applied;
                texVal.textContent = applied + '/' + res.maxTexture;
            }
        }

        function onTextureChange() {
            const drawable = parseInt(drawSlider.value);
            const texture  = parseInt(texSlider.value);
            texVal.textContent = texture + '/' + texSlider.max;
            if (drawable >= 0) nuiFetch('setProp', { propId: id, drawable, texture });
        }

        removeBtn.addEventListener('click', () => {
            drawSlider.value = -1;
            onDrawableChange();
        });

        drawSlider.addEventListener('input', onDrawableChange);
        texSlider.addEventListener('input', onTextureChange);
    });
}

// ============================================================
// FACE BLEND
// ============================================================

function renderFaceBlend() {
    if (!currentData || !currentData.headBlend) return;
    const hb = currentData.headBlend;

    $('shapeFirst').value  = hb.shapeFirst  || 0;
    $('shapeSecond').value = hb.shapeSecond || 0;
    $('shapeMix').value    = Math.round((hb.shapeMix || 0.5) * 100);
    $('skinFirst').value   = hb.skinFirst   || 0;
    $('skinSecond').value  = hb.skinSecond  || 0;
    $('skinMix').value     = Math.round((hb.skinMix || 0.5) * 100);
    $('eyeColor').value    = currentData.eyeColor || 0;

    updateFaceBlendLabels();
}

function updateFaceBlendLabels() {
    $('shapeFirst-val').textContent  = $('shapeFirst').value;
    $('shapeSecond-val').textContent = $('shapeSecond').value;
    $('shapeMix-val').textContent    = ($('shapeMix').value / 100).toFixed(2);
    $('skinFirst-val').textContent   = $('skinFirst').value;
    $('skinSecond-val').textContent  = $('skinSecond').value;
    $('skinMix-val').textContent     = ($('skinMix').value / 100).toFixed(2);
    $('eyeColor-val').textContent    = $('eyeColor').value;
}

function sendFaceBlend() {
    nuiFetch('setHeadBlend', {
        shapeFirst:  parseInt($('shapeFirst').value),
        shapeSecond: parseInt($('shapeSecond').value),
        skinFirst:   parseInt($('skinFirst').value),
        skinSecond:  parseInt($('skinSecond').value),
        shapeMix:    parseInt($('shapeMix').value)  / 100,
        skinMix:     parseInt($('skinMix').value)   / 100,
    });
    updateFaceBlendLabels();
}

['shapeFirst', 'shapeSecond', 'shapeMix', 'skinFirst', 'skinSecond', 'skinMix'].forEach(id => {
    $(id).addEventListener('input', sendFaceBlend);
});

$('eyeColor').addEventListener('input', () => {
    const val = parseInt($('eyeColor').value);
    $('eyeColor-val').textContent = val;
    nuiFetch('setEyeColor', { color: val });
});

// ============================================================
// FACE FEATURES
// ============================================================

function renderFaceFeatures() {
    const container = $('face-features-list');
    container.innerHTML = '';

    FACE_FEATURES.forEach((name, idx) => {
        const curVal     = currentData && currentData.faceFeatures
            ? (parseFloat(currentData.faceFeatures[idx.toString()]) || 0) : 0;
        const displayVal = Math.round(curVal * 100);

        const row = document.createElement('div');
        row.className = 'control-row';
        row.innerHTML = `
            <label>${name}</label>
            <div class="slider-wrap">
                ${sliderWithArrows(`ff-${idx}`, -100, 100, displayVal, '')}
            </div>
            <span class="val" id="ffv-${idx}">${curVal.toFixed(2)}</span>
        `;
        container.appendChild(row);

        function onFeatureChange() {
            const scale = parseInt($(`ff-${idx}`).value) / 100;
            $(`ffv-${idx}`).textContent = scale.toFixed(2);
            nuiFetch('setFaceFeature', { index: idx, scale });
        }

        $(`ff-${idx}`).addEventListener('input', onFeatureChange);
    });
}

// ============================================================
// HAIR
// ============================================================

function renderHair() {
    if (!currentData) return;

    function getColorName(id) {
        return hairColorMap[id] || ('Color ' + id);
    }

    const styleMax = (currentData.compInfo || {})['2']?.maxDrawable ?? 74;
    $('hairStyle').max   = styleMax;
    $('hairStyle').value = currentData.hairStyle || 0;
    $('hairStyle-val').textContent = $('hairStyle').value;

    $('hairStyle').oninput = () => {
        const style = parseInt($('hairStyle').value);
        $('hairStyle-val').textContent = style;
        nuiFetch('setComponent', { componentId: 2, drawable: style, texture: 0 });
    };

    function updatePreview() {
        const c1 = parseInt($('hairColor').value);
        const c2 = parseInt($('hairHighlight').value);

        $('hairColor-val').textContent    = getColorName(c1);
        $('hairHighlight-val').textContent = getColorName(c2);

        const colors = [
            '#111','#3d2314','#5c3a1e','#8b6239','#c4a35a','#a89048',
            '#e8dcc8','#888','#bbb','#fff','#c41e1e','#ff6600',
            '#228b22','#4169e1','#8b008b','#ff69b4','#800020','#722f37',
            '#ff4444','#8b0000','#6b4226','#daa520','#ffd700','#e6a8d7',
            '#b87333','#e6e6fa','#008080','#40e0d0','#50c878','#000080',
            '#ff7f50','#ffdab9','#ff007f','#ff00ff','#32cd32','#808000',
            '#555','#333','#999','#f7e7ce','#fffff0','#e6d8ad','#ccc','#f0f8ff',
            '#0a0a0a','#3b2f2f','#5c4033','#c68e17','#d2b48c','#e6d7b8',
            '#ffb6c1','#add8e6','#90ee90','#dda0dd','#ff1493','#00bfff',
            '#39ff14','#ff4500','#ff0000','#ffff00','#9400d3','#ff0033',
            '#4169e1','#00ff00'
        ];
        const col1 = colors[c1] || '#111';
        const col2 = colors[c2] || '#111';
        $('colorPreview').style.background = `linear-gradient(90deg, ${col1} 50%, ${col2} 50%)`;

        nuiFetch('setHairColor', { color: c1, highlight: c2 });
    }

    $('hairColor').addEventListener('input', updatePreview);
    $('hairHighlight').addEventListener('input', updatePreview);
    updatePreview();
}

// ============================================================
// OVERLAYS
// ============================================================

function renderOverlays() {
    const container = $('overlays-list');
    container.innerHTML = '';

    if (!OVERLAYS || OVERLAYS.length === 0) {
        container.innerHTML = '<div class="empty">No overlay data available</div>';
        return;
    }

    OVERLAYS.forEach(ov => {
        const idx    = ov.id;
        const cur    = (currentData.overlays || {})[idx.toString()] || { value: 255, opacity: 0.0 };
        const maxVal = ov.max || 15;
        const val    = (cur.value === 255 || cur.value == null) ? -1 : (cur.value || 0);
        const opac   = Math.round((cur.opacity || 0.0) * 100);

        const div = document.createElement('div');
        div.className = 'overlay-row';

        let extraColorHtml = '';
        if (ov.hasColor) {
            const curColor = cur.color || 0;
            extraColorHtml = `
                <div class="overlay-subrow">
                    <span class="overlay-sublabel">&#8627; Color</span>
                    <div class="slider-wrap">
                        ${sliderWithArrows(`oc-${idx}`, 0, 63, curColor, '')}
                    </div>
                    <span class="val" id="ocv-${idx}">${hairColorMap[curColor] || curColor}</span>
                </div>
            `;
        }

        div.innerHTML = `
            <div class="overlay-header">
                <span class="overlay-name">${ov.name}</span>
                <div class="slider-wrap">
                    ${sliderWithArrows(`ov-${idx}`, -1, maxVal, val, '')}
                </div>
                <span class="val" id="ovv-${idx}">${val < 0 ? 'Off' : val}</span>
            </div>
            <div class="overlay-subrow">
                <span class="overlay-sublabel">&#8627; Opacity</span>
                <div class="slider-wrap">
                    ${sliderWithArrows(`opo-${idx}`, 0, 100, opac, '')}
                </div>
                <span class="val" id="opov-${idx}">${(opac / 100).toFixed(2)}</span>
            </div>
            ${extraColorHtml}
        `;
        container.appendChild(div);

        const valSlider   = $(`ov-${idx}`);
        const opacSlider  = $(`opo-${idx}`);
        const valLabel    = $(`ovv-${idx}`);
        const opacLabel   = $(`opov-${idx}`);
        const colorSlider = ov.hasColor ? $(`oc-${idx}`) : null;
        const colorLabel  = ov.hasColor ? $(`ocv-${idx}`) : null;

        function sendOverlay() {
            const v     = parseInt(valSlider.value);
            const opac  = parseInt(opacSlider.value) / 100;
            valLabel.textContent  = v < 0 ? 'Off' : v;
            opacLabel.textContent = opac.toFixed(2);

            const payload = {
                index: idx,
                value: v < 0 ? 255 : v,
                opacity: opac
            };

            if (ov.hasColor && ov.colorType && colorSlider) {
                payload.color = parseInt(colorSlider.value);
                payload.color2 = parseInt(colorSlider.value);
                payload.colorType = ov.colorType;
            }

            nuiFetch('setOverlay', payload);
        }

        function onColorChange() {
            if (colorSlider && colorLabel) {
                colorLabel.textContent = hairColorMap[parseInt(colorSlider.value)] || parseInt(colorSlider.value);
                sendOverlay();
            }
        }

        valSlider.addEventListener('input', sendOverlay);
        opacSlider.addEventListener('input', sendOverlay);

        if (colorSlider) {
            colorSlider.addEventListener('input', onColorChange);
        }
    });
}

// ============================================================
// SAVED OUTFITS
// ============================================================

function renderSavedOutfits(names) {
    const container = $('saved-outfits-list');
    container.innerHTML = '';

    if (!names || names.length === 0) {
        container.innerHTML = '<div class="empty">No saved outfits yet</div>';
        return;
    }

    names.forEach(name => {
        container.appendChild(makeOutfitItem(name));
    });
}

function makeOutfitItem(name) {
    const item = document.createElement('div');
    item.className = 'outfit-item';
    item.innerHTML = `
        <span class="outfit-item-name">${escapeHtml(name)}</span>
        <div class="outfit-item-btns">
            <button class="outfit-btn btn-load">LOAD</button>
            <button class="outfit-btn btn-update">UPDATE</button>
            <button class="outfit-btn btn-del">DEL</button>
        </div>
    `;

    item.querySelector('.btn-load').addEventListener('click', async () => {
        await nuiFetch('loadOutfit', { name });
    });

    item.querySelector('.btn-update').addEventListener('click', async () => {
        await nuiFetch('updateOutfit', { name });
    });

    item.querySelector('.btn-del').addEventListener('click', async () => {
        await nuiFetch('deleteOutfit', { name });
        item.remove();
        if ($('saved-outfits-list').children.length === 0) {
            $('saved-outfits-list').innerHTML = '<div class="empty">No saved outfits yet</div>';
        }
    });

    return item;
}

$('btnSave').addEventListener('click', async () => {
    const name = $('outfitName').value.trim();
    if (!name) return;

    await nuiFetch('saveOutfit', { name });
    $('outfitName').value = '';
    await nuiFetch('listOutfits', {});
});

// ============================================================
// EXPORT / IMPORT
//
// Export just serializes the exact same data structure already used
// for saving/loading outfits (components, props, face/hair, etc.) into
// a short server-backed code. Import reuses the same ApplyData() path
// on the Lua side that loading a saved outfit already uses.
//
// This lives in its own standalone popup (#codeModalOverlay), entirely
// separate from the main editor's DOM — opening/closing it never
// resizes or reflows the ped editor panel underneath. One shared modal
// handles both export and import depending on `codeModalMode`.
// ============================================================

let codeModalMode = null; // 'export' | 'import'

function setCodeStatus(text, kind) {
    const el = $('codeModalStatus');
    el.textContent = text || '';
    el.classList.remove('success', 'error');
    if (kind) el.classList.add(kind);
}

function closeCodeModal() {
    $('codeModalOverlay').classList.add('hidden');
    codeModalMode = null;
    $('codeModalBox').value = '';
    setCodeStatus('', null);
}

function openExportModal() {
    codeModalMode = 'export';
    $('codeModalTitle').textContent = 'Export Outfit';
    $('codeModalBox').readOnly = true;
    $('codeModalBox').placeholder = '';
    $('codeModalBox').value = '';
    $('codeModalActionBtn').textContent = 'Copy to Clipboard';
    $('codeModalActionBtn').classList.remove('btn-code-apply');
    setCodeStatus('', null);
    $('codeModalOverlay').classList.remove('hidden');

    // The Lua side generates the code and replies immediately, without
    // waiting on the server save round-trip — this should land well
    // under a frame, no "generating" placeholder needed.
    nuiFetch('exportOutfit', {}).then(res => {
        if (codeModalMode !== 'export') return; // modal was closed/switched while waiting
        if (res && res.ok && res.code) {
            $('codeModalBox').value = res.code;
            $('codeModalBox').select();
        } else {
            setCodeStatus((res && res.error) || 'Export failed.', 'error');
        }
    });
}

function openImportModal() {
    codeModalMode = 'import';
    $('codeModalTitle').textContent = 'Import Outfit';
    $('codeModalBox').readOnly = false;
    $('codeModalBox').placeholder = 'PVP-XXXXXXXX';
    $('codeModalBox').value = '';
    $('codeModalActionBtn').textContent = 'Apply Code';
    $('codeModalActionBtn').classList.add('btn-code-apply');
    setCodeStatus('', null);
    $('codeModalOverlay').classList.remove('hidden');
    $('codeModalBox').focus();
}

$('btnExportOutfit').addEventListener('click', openExportModal);
$('btnImportOutfit').addEventListener('click', openImportModal);
$('codeModalClose').addEventListener('click', closeCodeModal);
$('codeModalOverlay').addEventListener('click', (e) => {
    if (e.target === $('codeModalOverlay')) closeCodeModal(); // click outside the box closes it
});

$('codeModalActionBtn').addEventListener('click', async () => {
    if (codeModalMode === 'export') {
        const box = $('codeModalBox');
        box.select();
        let copied = false;
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(box.value);
                copied = true;
            }
        } catch (e) { /* fall through to legacy method below */ }

        if (!copied) {
            try { copied = document.execCommand('copy'); } catch (e) { copied = false; }
        }

        if (copied) {
            setCodeStatus('Copied!', 'success');
            setTimeout(closeCodeModal, 700);
        } else {
            setCodeStatus('Could not copy — select & Ctrl+C manually.', 'error');
        }
    } else if (codeModalMode === 'import') {
        const code = $('codeModalBox').value.trim();
        if (!code) {
            setCodeStatus('Paste a code first.', 'error');
            return;
        }

        setCodeStatus('Applying…', null);
        const res = await nuiFetch('importOutfit', { code });

        if (res && res.ok) {
            if (res.currentData) currentData = res.currentData;
            renderAll();
            setCodeStatus('Applied!', 'success');
            setTimeout(closeCodeModal, 700);
        } else {
            setCodeStatus((res && res.error) || 'Import failed — check the code and try again.', 'error');
        }
    }
});

// ============================================================
// SAVE CHARACTER
// ============================================================

$('btnSaveChar').addEventListener('click', async () => {
    await nuiFetch('saveCharacter', {});
});

// ============================================================
// RANDOMIZE
// ============================================================

$('btnRandom').addEventListener('click', async () => {
    if (!COMPONENTS.length) return;

    for (const comp of COMPONENTS) {
        const max      = parseInt(($(`cs-${comp.id}`) || {}).max) || 50;
        const drawable = Math.floor(Math.random() * (max + 1));
        const texture  = Math.floor(Math.random() * 4);
        await nuiFetch('setComponent', { componentId: comp.id, drawable, texture });
    }

    for (const prop of PROPS) {
        const max      = parseInt(($(`ps-${prop.id}`) || {}).max) || 20;
        const drawable = Math.random() > 0.5 ? Math.floor(Math.random() * (max + 1)) : -1;
        await nuiFetch('setProp', { propId: prop.id, drawable, texture: 0 });
    }

    await nuiFetch('setHeadBlend', {
        shapeFirst:  Math.floor(Math.random() * 46),
        shapeSecond: Math.floor(Math.random() * 46),
        skinFirst:   Math.floor(Math.random() * 46),
        skinSecond:  Math.floor(Math.random() * 46),
        shapeMix:    parseFloat(Math.random().toFixed(2)),
        skinMix:     parseFloat(Math.random().toFixed(2)),
    });

    for (let i = 0; i < 20; i++) {
        const scale = parseFloat((Math.random() * 2 - 1).toFixed(2));
        await nuiFetch('setFaceFeature', { index: i, scale });
    }

    if (OVERLAYS && OVERLAYS.length > 0) {
        for (const ov of OVERLAYS) {
            if (Math.random() > 0.5) {
                const val = Math.floor(Math.random() * (ov.max + 1));
                const op = parseFloat((0.3 + Math.random() * 0.7).toFixed(2));
                const payload = { index: ov.id, value: val, opacity: op };
                if (ov.hasColor && ov.colorType) {
                    payload.color = Math.floor(Math.random() * 64);
                    payload.color2 = payload.color;
                    payload.colorType = ov.colorType;
                }
                await nuiFetch('setOverlay', payload);
            } else {
                await nuiFetch('setOverlay', { index: ov.id, value: 255, opacity: 0.0 });
            }
        }
    }

    const hairC = Math.floor(Math.random() * 64);
    const hairH = Math.floor(Math.random() * 64);
    await nuiFetch('setHairColor', { color: hairC, highlight: hairH });
    await nuiFetch('setEyeColor',  { color: Math.floor(Math.random() * 32) });

    const res = await nuiFetch('refresh', {});
    if (res && res.currentData) {
        currentData = res.currentData;
        renderAll();
    }
});

// ============================================================
// UTILITIES
// ============================================================

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Hide on load
window.addEventListener('DOMContentLoaded', () => {
    $('app').classList.add('hidden');
});
