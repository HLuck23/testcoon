-- ============================================================
-- PedMngr v2.4 — Model-specific outfits, model memory, shirt/pants icons, rotation
-- ============================================================

local FREEMODE_MODELS = {
    [GetHashKey("mp_m_freemode_01")] = true,
    [GetHashKey("mp_f_freemode_01")] = true,
}

local PM = {
    open = false,
    camera = nil,
    oldPos = nil,
    oldHeading = nil,
    forceOpen = false,
    serverAppearance = nil,
    lastPedModel = nil,
    hasNotifiedReady = false,
    autoSaveTimer = 0,
    modelSwitching = false, -- true while ApplyData/setPedModel is mid-swap; blocks
                            -- GetCurrentData()-based saves so a half-spawned ped
                            -- (still wearing the previous model's components) can
                            -- never get captured and written back over a good save

    -- FIX: FiveM's GetPedHeadBlendData() lua binding is unreliable -- it only
    -- consistently returns the first shape ID and leaves the other 9 values
    -- nil/zeroed. Reading head blend back through that native (instead of
    -- tracking it ourselves) is what was resetting the Face tab sliders to
    -- defaults every time the menu was reopened, even though the actual ped
    -- never changed. This cache is the single source of truth for head blend
    -- and is updated everywhere we actually call SetPedHeadBlendData.
    headBlendCache = {
        shapeFirst = 0, shapeSecond = 0,
        skinFirst = 0, skinSecond = 0,
        shapeMix = 0.5, skinMix = 0.5,
    },

    models = {
        { name = "Male",   hash = GetHashKey("mp_m_freemode_01"), id = "mp_m_freemode_01" },
        { name = "Female", hash = GetHashKey("mp_f_freemode_01"), id = "mp_f_freemode_01" },
    },

    categories = {
        {
            name = "Head",
            items = {
                {id = 2,  name = "Hair",       max = 78},
                {id = 1,  name = "Mask",       max = 169},
                {id = 0,  name = "Face",       max = 45},
            }
        },
        {
            name = "Upper Body",
            items = {
                {id = 11, name = "Jacket / Top", max = 334},
                {id = 8,  name = "Undershirt",   max = 164},
                {id = 3,  name = "Arms / Torso", max = 183},
                {id = 9,  name = "Armor / Vest", max = 18},
            }
        },
        {
            name = "Lower Body",
            items = {
                {id = 4,  name = "Pants",   max = 325},
                {id = 6,  name = "Shoes",   max = 89},
            }
        },
        {
            name = "Accessories",
            items = {
                {id = 5,  name = "Bag",         max = 82},
                {id = 7,  name = "Accessories", max = 121},
                {id = 10, name = "Decals",      max = 110},
            }
        },
    },

    props = {
        {id = 0, name = "Hat",       max = 160},
        {id = 1, name = "Glasses",   max = 35},
        {id = 2, name = "Ears",      max = 18},
        {id = 6, name = "Watch",     max = 30},
        {id = 7, name = "Bracelet",  max = 10},
    },

    faceFeatures = {
        {id = 0,  name = "Nose Width",        group = "Nose"},
        {id = 1,  name = "Nose Peak Height",  group = "Nose"},
        {id = 2,  name = "Nose Peak Length",  group = "Nose"},
        {id = 3,  name = "Nose Bone Height",  group = "Nose"},
        {id = 4,  name = "Nose Peak Lower",   group = "Nose"},
        {id = 5,  name = "Nose Bone Twist",   group = "Nose"},
        {id = 6,  name = "Eyebrow Height",    group = "Eyes"},
        {id = 7,  name = "Eyebrow Depth",     group = "Eyes"},
        {id = 11, name = "Eye Opening",       group = "Eyes"},
        {id = 12, name = "Lip Thickness",     group = "Mouth"},
        {id = 15, name = "Chin Height",       group = "Jaw / Chin"},
        {id = 16, name = "Chin Depth",        group = "Jaw / Chin"},
        {id = 17, name = "Chin Width",        group = "Jaw / Chin"},
        {id = 18, name = "Chin Dimple",       group = "Jaw / Chin"},
        {id = 13, name = "Jaw Bone Width",    group = "Jaw / Chin"},
        {id = 14, name = "Jaw Bone Depth",    group = "Jaw / Chin"},
        {id = 8,  name = "Cheekbone Height",  group = "Cheeks"},
        {id = 9,  name = "Cheekbone Width",   group = "Cheeks"},
        {id = 10, name = "Cheek Width",       group = "Cheeks"},
        {id = 19, name = "Neck Thickness",    group = "Neck"},
    },

    overlays = {
        {id = 0,  name = "Blemishes",          max = 23, hasColor = false},
        {id = 1,  name = "Facial Hair",        max = 28, hasColor = true,  colorType = 1},
        {id = 2,  name = "Eyebrows",           max = 33, hasColor = true,  colorType = 1},
        {id = 3,  name = "Ageing",             max = 14, hasColor = false},
        {id = 4,  name = "Makeup",             max = 74, hasColor = false},
        {id = 5,  name = "Blush",              max = 6,  hasColor = true,  colorType = 2},
        {id = 6,  name = "Complexion",         max = 11, hasColor = false},
        {id = 7,  name = "Sun Damage",         max = 10, hasColor = false},
        {id = 8,  name = "Lipstick",           max = 9,  hasColor = true,  colorType = 2},
        {id = 9,  name = "Moles / Freckles",   max = 17, hasColor = false},
        {id = 10, name = "Chest Hair",         max = 16, hasColor = true,  colorType = 1},
        {id = 11, name = "Body Blemishes",     max = 11, hasColor = false},
        {id = 12, name = "Add Body Blemishes", max = 11, hasColor = false},
    },

    hairColors = {
        {0, "Black"}, {1, "Dark Brown"}, {2, "Brown"}, {3, "Light Brown"},
        {4, "Blonde"}, {5, "Dirty Blonde"}, {6, "Platinum"}, {7, "Gray"},
        {8, "Silver"}, {9, "White"}, {10, "Red"}, {11, "Orange"},
        {12, "Green"}, {13, "Blue"}, {14, "Purple"}, {15, "Pink"},
        {16, "Burgundy"}, {17, "Auburn"}, {18, "Light Red"}, {19, "Dark Red"},
        {20, "Chestnut"}, {21, "Honey"}, {22, "Golden"}, {23, "Strawberry"},
        {24, "Copper"}, {25, "Lavender"}, {26, "Teal"}, {27, "Turquoise"},
        {28, "Emerald"}, {29, "Navy"}, {30, "Coral"}, {31, "Peach"},
        {32, "Rose"}, {33, "Magenta"}, {34, "Lime"}, {35, "Olive"},
        {36, "Dark Gray"}, {37, "Charcoal"}, {38, "Ash"}, {39, "Champagne"},
        {40, "Ivory"}, {41, "Pale Blonde"}, {42, "Light Gray"}, {43, "Snow White"},
        {44, "Jet Black"}, {45, "Espresso"}, {46, "Chocolate"}, {47, "Caramel"},
        {48, "Sandy"}, {49, "Platinum Blonde"}, {50, "Pastel Pink"},
        {51, "Pastel Blue"}, {52, "Pastel Green"}, {53, "Pastel Purple"},
        {54, "Neon Pink"}, {55, "Neon Blue"}, {56, "Neon Green"},
        {57, "Neon Orange"}, {58, "Neon Red"}, {59, "Neon Yellow"},
        {60, "Neon Purple"}, {61, "Bright Red"}, {62, "Bright Blue"},
        {63, "Bright Green"},
    },
}

-- ============================================================
-- CAMERA VIEW PRESETS
-- ============================================================

local CAMERA_VIEWS = {
    full  = { dist = 3.5, zOff = 0.3, lookZ = 0.0 },
    head  = { dist = 0.8, zOff = 0.6, lookZ = 0.6 },
    chest = { dist = 1.6, zOff = 0.4, lookZ = 0.15 },
    legs  = { dist = 2.2, zOff = -0.2, lookZ = -0.55 },
}

local currentCamView = 'full'

local function SetCameraView(viewName)
    if not PM.camera then return end
    currentCamView = viewName
    local view = CAMERA_VIEWS[viewName] or CAMERA_VIEWS.full
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local angle = math.rad(180)
    local offset = vector3(math.sin(angle) * view.dist, math.cos(angle) * view.dist, view.zOff)
    SetCamCoord(PM.camera, coords.x + offset.x, coords.y + offset.y, coords.z + offset.z)
    PointCamAtEntity(PM.camera, ped, 0.0, 0.0, view.lookZ, true)
end

-- ============================================================
-- SAFE MAX HELPERS
-- ============================================================

local function GetSafeMaxDrawable(componentId)
    local ped = PlayerPedId()
    local hardMax = 255
    for _, cat in ipairs(PM.categories) do
        for _, item in ipairs(cat.items) do
            if item.id == componentId then hardMax = item.max break end
        end
    end
    local actualMax = GetNumberOfPedDrawableVariations(ped, componentId) - 1
    return math.min(hardMax, math.max(0, actualMax))
end

local function GetSafeMaxProp(propId)
    local ped = PlayerPedId()
    local hardMax = 255
    for _, prop in ipairs(PM.props) do
        if prop.id == propId then hardMax = prop.max break end
    end
    local actualMax = GetNumberOfPedPropDrawableVariations(ped, propId) - 1
    return math.min(hardMax, math.max(0, actualMax))
end

-- ============================================================
-- NUI CALLBACKS
-- ============================================================

RegisterNUICallback('close', function(_, cb) ClosePedMngr() cb('ok') end)

RegisterNUICallback('setComponent', function(data, cb)
    local ped = PlayerPedId()
    local componentId = tonumber(data.componentId)
    local drawable = tonumber(data.drawable)
    local texture = tonumber(data.texture) or 0
    local safeMax = GetSafeMaxDrawable(componentId)
    if drawable > safeMax then drawable = safeMax end

    SetPedComponentVariation(ped, componentId, drawable, texture, 0)
    local maxTex = math.max(0, GetNumberOfPedTextureVariations(ped, componentId, drawable) - 1)

    -- TEXTURE RESET FIX: different drawables (especially across addon/EUP
    -- packs) can have wildly different texture counts. If the requested
    -- texture doesn't actually exist on this drawable -- a stale value
    -- carried over from before a drawable change -- clamp it down to 0
    -- and actually re-apply it, instead of leaving the ped wearing
    -- whatever the engine silently fell back to internally.
    if texture > maxTex then
        texture = 0
        SetPedComponentVariation(ped, componentId, drawable, texture, 0)
    end

    cb({ maxTexture = maxTex, texture = texture })
end)

RegisterNUICallback('setProp', function(data, cb)
    local ped = PlayerPedId()
    local id = tonumber(data.propId)
    local drawable = tonumber(data.drawable)
    local texture = tonumber(data.texture) or 0
    if drawable == -1 then
        ClearPedProp(ped, id)
        cb({ maxTexture = 0, texture = 0 })
    else
        local safeMax = GetSafeMaxProp(id)
        if drawable > safeMax then drawable = safeMax end
        SetPedPropIndex(ped, id, drawable, texture, true)
        local maxTex = math.max(0, GetNumberOfPedPropTextureVariations(ped, id, drawable) - 1)

        -- Same texture-reset fix as setComponent above.
        if texture > maxTex then
            texture = 0
            SetPedPropIndex(ped, id, drawable, texture, true)
        end

        cb({ maxTexture = maxTex, texture = texture })
    end
end)

RegisterNUICallback('setHairColor', function(data, cb)
    SetPedHairColor(PlayerPedId(), tonumber(data.color), tonumber(data.highlight) or tonumber(data.color))
    cb('ok')
end)

RegisterNUICallback('setFaceFeature', function(data, cb)
    SetPedFaceFeature(PlayerPedId(), tonumber(data.index), tonumber(data.scale))
    cb('ok')
end)

RegisterNUICallback('setHeadBlend', function(data, cb)
    local shapeFirst  = data.shapeFirst  or 0
    local shapeSecond = data.shapeSecond or 0
    local skinFirst   = data.skinFirst   or 0
    local skinSecond  = data.skinSecond  or 0
    local shapeMix    = data.shapeMix    or 0.5
    local skinMix     = data.skinMix     or 0.5

    SetPedHeadBlendData(PlayerPedId(), shapeFirst, shapeSecond, 0,
        skinFirst, skinSecond, 0, shapeMix, skinMix, 0.0, false)

    PM.headBlendCache = {
        shapeFirst = shapeFirst, shapeSecond = shapeSecond,
        skinFirst = skinFirst, skinSecond = skinSecond,
        shapeMix = shapeMix, skinMix = skinMix,
    }
    cb('ok')
end)

RegisterNUICallback('setEyeColor', function(data, cb)
    SetPedEyeColor(PlayerPedId(), tonumber(data.color) or 0)
    cb('ok')
end)

RegisterNUICallback('rotatePed', function(data, cb)
    SetEntityHeading(PlayerPedId(), tonumber(data.heading) or 180.0)
    cb('ok')
end)

RegisterNUICallback('rotatePedDelta', function(data, cb)
    local ped = PlayerPedId()
    local current = GetEntityHeading(ped)
    local delta = tonumber(data.delta) or 25.0
    SetEntityHeading(ped, (current + delta) % 360.0)
    cb('ok')
end)

RegisterNUICallback('setCameraView', function(data, cb)
    SetCameraView(data.view or 'full')
    cb('ok')
end)

RegisterNUICallback('randomize', function(_, cb)
    RandomizePed()
    cb({ currentData = BuildCurrentDataWithInfo() })
end)

RegisterNUICallback('resetFit', function(_, cb)
    ResetToDefault()
    cb({ currentData = BuildCurrentDataWithInfo() })
end)

RegisterNUICallback('refresh', function(_, cb)
    cb({ currentData = BuildCurrentDataWithInfo() })
end)

-- ============================================================
-- NUI CALLBACK — setPedModel (with model memory)
-- ============================================================

RegisterNUICallback('setPedModel', function(data, cb)
    local newModel = tonumber(data.model)
    if not newModel then
        cb({ currentData = BuildCurrentDataWithInfo() })
        return
    end

    local ped = PlayerPedId()
    local currentModel = GetEntityModel(ped)
    if currentModel == newModel then
        cb({ currentData = BuildCurrentDataWithInfo() })
        return
    end

    -- Save current model's appearance before switching
    TriggerServerEvent('pedmngr:saveModelAppearance', currentModel, GetCurrentData())

    PM.modelSwitching = true
    RequestModel(newModel)
    local timeout = 0
    while not HasModelLoaded(newModel) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(newModel) then
        SetPlayerModel(PlayerId(), newModel)
        SetModelAsNoLongerNeeded(newModel)
        Wait(200)

        ped = PlayerPedId()
        SetPedDefaultComponentVariation(ped)

        if FREEMODE_MODELS[newModel] then
            SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
            PM.headBlendCache = { shapeFirst = 0, shapeSecond = 0, skinFirst = 0, skinSecond = 0, shapeMix = 0.5, skinMix = 0.5 }
            SetPedHairColor(ped, 0, 0)
            SetPedEyeColor(ped, 0)
            for _, ff in ipairs(PM.faceFeatures) do
                SetPedFaceFeature(ped, ff.id, 0.0)
            end
            for i = 0, 12 do
                SetPedHeadOverlay(ped, i, 255, 0.0)
            end
        end

        -- Request saved appearance for new model (server will apply via pedmngr:applyData)
        TriggerServerEvent('pedmngr:loadModelAppearance', newModel)
    end
    PM.lastPedModel = GetEntityModel(PlayerPedId())
    PM.modelSwitching = false

    cb({ currentData = BuildCurrentDataWithInfo() })
end)

-- ============================================================
-- NUI CALLBACK — setOverlay
-- ============================================================

RegisterNUICallback('setOverlay', function(data, cb)
    local ped = PlayerPedId()
    local overlayId = tonumber(data.index)
    local value = tonumber(data.value) or 255
    local opacity = tonumber(data.opacity) or 0.0
    local color = tonumber(data.color)
    local color2 = tonumber(data.color2)
    local colorType = tonumber(data.colorType)

    SetPedHeadOverlay(ped, overlayId, value, opacity)
    if colorType and color and value ~= 255 then
        SetPedHeadOverlayColor(ped, overlayId, colorType, color, color2 or color)
    end
    cb('ok')
end)

-- ============================================================
-- NUI CALLBACKS — Outfits (server-synced, model-specific)
-- ============================================================

RegisterNUICallback('saveOutfit', function(data, cb)
    if data.name and data.name ~= "" then
        TriggerServerEvent('pedmngr:saveOutfit', data.name, GetEntityModel(PlayerPedId()), GetCurrentData())
    end
    cb({ outfits = {} })
end)

RegisterNUICallback('updateOutfit', function(data, cb)
    if data.name and data.name ~= "" then
        TriggerServerEvent('pedmngr:updateOutfit', data.name, GetEntityModel(PlayerPedId()), GetCurrentData())
    end
    cb({ outfits = {} })
end)

RegisterNUICallback('loadOutfit', function(data, cb)
    if data.name then
        TriggerServerEvent('pedmngr:loadOutfit', data.name, GetEntityModel(PlayerPedId()))
    end
    cb({ currentData = BuildCurrentDataWithInfo() })
end)

RegisterNUICallback('deleteOutfit', function(data, cb)
    if data.name then
        TriggerServerEvent('pedmngr:deleteOutfit', data.name, GetEntityModel(PlayerPedId()))
    end
    cb({ outfits = {} })
end)

RegisterNUICallback('listOutfits', function(_, cb)
    TriggerServerEvent('pedmngr:listOutfits', GetEntityModel(PlayerPedId()))
    cb({ outfits = {} })
end)

-- ============================================================
-- NUI CALLBACK — Export / Import Outfit
--
-- Short "PVP-XXXXXXXX" codes (8 random uppercase letters/digits). The
-- actual outfit data (the exact same GetCurrentData()/ApplyData() pair
-- already used for saving/loading outfits) is stored server-side via
-- KVP, keyed by the short code -- the code itself is just a lookup
-- key, not a self-contained blob, which is the only way to keep it
-- actually short. That does mean a code only means something on THIS
-- server -- anyone playing here can import it, but pasting it into a
-- different server's PedMngr won't do anything unless that server
-- happens to have the same code stored.
--
-- Export shows the code INSTANTLY rather than waiting on a server
-- round-trip -- the actual save happens in the background. Import has
-- to wait on the server lookup since that's where the data actually
-- lives, but the result is still never trusted blindly: pcall'd decode,
-- shape-checked, and pcall'd apply before it ever touches the ped.
-- ============================================================

local CODE_PREFIX = 'PVP-'
local CODE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

local function GenerateShortCode(len)
    len = len or 8
    local parts = {}
    for i = 1, len do
        local idx = math.random(1, #CODE_CHARS)
        parts[i] = CODE_CHARS:sub(idx, idx)
    end
    return table.concat(parts)
end

-- Only one import lookup can realistically be in flight from this
-- client at a time -- a fresh import request just replaces whatever
-- was pending rather than stacking callbacks.
local pendingImportCb = nil

RegisterNUICallback('exportOutfit', function(_, cb)
    local ok, data = pcall(GetCurrentData)
    if not ok then
        cb({ ok = false, error = 'Could not read current appearance.' })
        return
    end

    local ok2, jsonStr = pcall(json.encode, data)
    if not ok2 or not jsonStr then
        cb({ ok = false, error = 'Failed to generate export code.' })
        return
    end

    local shortCode = GenerateShortCode(8)

    -- Show the code immediately -- don't make the player wait on a
    -- server round-trip just to see it.
    cb({ ok = true, code = CODE_PREFIX .. shortCode })

    -- Persist it server-side in the background.
    TriggerServerEvent('pedmngr:storeExportCode', shortCode, jsonStr)
end)

RegisterNUICallback('importOutfit', function(data, cb)
    local rawCode = data and data.code
    if type(rawCode) ~= 'string' then
        cb({ ok = false, error = 'No code provided.' })
        return
    end

    local cleaned = rawCode:gsub('%s', ''):upper()
    local shortCode = cleaned:match('^PVP%-([A-Z0-9]+)$') or cleaned:match('^([A-Z0-9]+)$')
    if not shortCode or #shortCode < 4 then
        cb({ ok = false, error = "That doesn't look like a valid code." })
        return
    end

    pendingImportCb = cb
    TriggerServerEvent('pedmngr:requestImportCode', shortCode)

    -- Safety timeout: never leave the NUI fetch hanging forever if the
    -- server never responds for any reason (e.g. a drop mid-request).
    Citizen.SetTimeout(8000, function()
        if pendingImportCb == cb then
            pendingImportCb = nil
            cb({ ok = false, error = 'Timed out waiting for the server.' })
        end
    end)
end)

RegisterNetEvent('pedmngr:importCodeResult')
AddEventHandler('pedmngr:importCodeResult', function(success, payload)
    local cb = pendingImportCb
    if not cb then return end
    pendingImportCb = nil

    if not success then
        cb({ ok = false, error = payload or 'Code not found on this server.' })
        return
    end

    local ok, decoded = pcall(json.decode, payload)
    if not ok or type(decoded) ~= 'table' then
        cb({ ok = false, error = 'Stored outfit data was corrupted.' })
        return
    end

    if type(decoded.components) ~= 'table' and type(decoded.props) ~= 'table' then
        cb({ ok = false, error = 'That code does not look like a valid outfit.' })
        return
    end

    local ok2, applyErr = pcall(ApplyData, decoded)
    if not ok2 then
        cb({ ok = false, error = 'Import failed while applying: ' .. tostring(applyErr) })
        return
    end

    cb({ ok = true, currentData = BuildCurrentDataWithInfo() })
end)

-- ============================================================
-- NUI CALLBACK — Save Character
-- ============================================================

RegisterNUICallback('saveCharacter', function(_, cb)
    local appearanceData = GetCurrentData()
    TriggerServerEvent('pedmngr:saveAppearance', appearanceData)
    ClosePedMngr()
    cb('ok')
end)

-- ============================================================
-- GET / APPLY / RANDOMIZE / RESET
-- ============================================================

function GetCurrentData()
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)

    local d = {
        model = model,
        components = {},
        props = {},
        faceFeatures = {},
        headBlend = {},
        overlays = {},
        hairColor = 0,
        hairHighlight = 0,
        eyeColor = 0,
        hairStyle = 0,
    }

    for _, cat in ipairs(PM.categories) do
        for _, item in ipairs(cat.items) do
            d.components[tostring(item.id)] = {
                drawable = GetPedDrawableVariation(ped, item.id),
                texture = GetPedTextureVariation(ped, item.id)
            }
        end
    end

    for _, prop in ipairs(PM.props) do
        d.props[tostring(prop.id)] = {
            drawable = GetPedPropIndex(ped, prop.id),
            texture = GetPedPropTextureIndex(ped, prop.id)
        }
    end

    -- FIX: don't trust GetPedHeadBlendData(ped) here -- see PM.headBlendCache
    -- comment above for why. Use our own tracked values instead.
    d.headBlend = {
        shapeFirst  = PM.headBlendCache.shapeFirst,
        shapeSecond = PM.headBlendCache.shapeSecond,
        skinFirst   = PM.headBlendCache.skinFirst,
        skinSecond  = PM.headBlendCache.skinSecond,
        shapeMix    = PM.headBlendCache.shapeMix,
        skinMix     = PM.headBlendCache.skinMix,
    }

    for _, ff in ipairs(PM.faceFeatures) do
        d.faceFeatures[tostring(ff.id)] = GetPedFaceFeature(ped, ff.id)
    end

    for i = 0, 12 do
        local success, overlayValue, colourType, firstColour, secondColour, overlayOpacity = GetPedHeadOverlayData(ped, i)
        if success then
            d.overlays[tostring(i)] = {
                value = overlayValue,
                opacity = overlayOpacity,
                colorType = colourType,
                color = firstColour,
                color2 = secondColour,
            }
        else
            d.overlays[tostring(i)] = { value = 255, opacity = 0.0 }
        end
    end

    d.eyeColor = GetPedEyeColor(ped)
    d.hairStyle = GetPedDrawableVariation(ped, 2)

    local hc, hh = GetPedHairColor(ped)
    d.hairColor = hc
    d.hairHighlight = hh

    return d
end

function BuildCurrentDataWithInfo()
    local ped = PlayerPedId()
    local d = GetCurrentData()
    d.compInfo = {}
    d.propInfo = {}
    d.overlayInfo = {}

    for _, cat in ipairs(PM.categories) do
        for _, item in ipairs(cat.items) do
            local safeMax = GetSafeMaxDrawable(item.id)
            local drawable = GetPedDrawableVariation(ped, item.id)
            if drawable > safeMax then drawable = safeMax end
            local maxTex = GetNumberOfPedTextureVariations(ped, item.id, drawable) - 1
            d.compInfo[tostring(item.id)] = {
                maxDrawable = safeMax,
                maxTexture = math.max(0, maxTex)
            }
        end
    end

    for _, prop in ipairs(PM.props) do
        local safeMax = GetSafeMaxProp(prop.id)
        local drawable = GetPedPropIndex(ped, prop.id)
        local maxTex = 0
        if drawable >= 0 then
            maxTex = GetNumberOfPedPropTextureVariations(ped, prop.id, drawable) - 1
        end
        d.propInfo[tostring(prop.id)] = {
            maxDrawable = safeMax,
            maxTexture = math.max(0, maxTex)
        }
    end

    for _, ov in ipairs(PM.overlays) do
        d.overlayInfo[tostring(ov.id)] = { maxValue = ov.max, hasColor = ov.hasColor }
    end

    return d
end

function ApplyData(data)
    if not data then return end
    local ped = PlayerPedId()

    if data.model then
        local currentModel = GetEntityModel(ped)
        if currentModel ~= data.model then
            PM.modelSwitching = true
            RequestModel(data.model)
            local timeout = 0
            while not HasModelLoaded(data.model) and timeout < 100 do
                Wait(10)
                timeout = timeout + 1
            end
            if HasModelLoaded(data.model) then
                SetPlayerModel(PlayerId(), data.model)
                SetModelAsNoLongerNeeded(data.model)
                Wait(200)
                ped = PlayerPedId()

                -- FIX: reset the new ped to its freemode default before applying
                -- saved data, exactly like setPedModel does. Without this, the
                -- previous model's component variations can still be resident
                -- on the new mesh, so components only partially overwrite and
                -- you get a male body with mismatched/bugged item indices when
                -- the saved appearance was captured as female (and vice versa).
                if FREEMODE_MODELS[data.model] then
                    SetPedDefaultComponentVariation(ped)
                    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
                    PM.headBlendCache = { shapeFirst = 0, shapeSecond = 0, skinFirst = 0, skinSecond = 0, shapeMix = 0.5, skinMix = 0.5 }
                    SetPedHairColor(ped, 0, 0)
                    SetPedEyeColor(ped, 0)
                    for _, ff in ipairs(PM.faceFeatures) do
                        SetPedFaceFeature(ped, ff.id, 0.0)
                    end
                    for i = 0, 12 do
                        SetPedHeadOverlay(ped, i, 255, 0.0)
                    end
                end
            end
            PM.lastPedModel = GetEntityModel(ped)
            PM.modelSwitching = false
        end
    end

    if data.components then
        for id, vals in pairs(data.components) do
            local compId = tonumber(id)
            -- FIX: component 10 ("Decals") has no menu control anywhere in the UI,
            -- so players have no way to remove a bad/glitched decal once it's set.
            -- Force it to none (drawable 0, texture 0) on every apply so old saves
            -- carrying a stuck decal from a previous Randomize self-heal instead of
            -- re-applying the glitch forever.
            if compId == 10 then
                SetPedComponentVariation(ped, 10, 0, 0, 0)
            else
                SetPedComponentVariation(ped, compId, vals.drawable or 0, vals.texture or 0, 0)
            end
        end
    end

    if data.props then
        for id, vals in pairs(data.props) do
            if vals.drawable == -1 then
                ClearPedProp(ped, tonumber(id))
            else
                SetPedPropIndex(ped, tonumber(id), vals.drawable or 0, vals.texture or 0, true)
            end
        end
    end

    if data.headBlend then
        local hb = data.headBlend
        SetPedHeadBlendData(ped, hb.shapeFirst or 0, hb.shapeSecond or 0, 0,
            hb.skinFirst or 0, hb.skinSecond or 0, 0, hb.shapeMix or 0.5, hb.skinMix or 0.5, 0.0, false)
        PM.headBlendCache = {
            shapeFirst = hb.shapeFirst or 0, shapeSecond = hb.shapeSecond or 0,
            skinFirst = hb.skinFirst or 0, skinSecond = hb.skinSecond or 0,
            shapeMix = hb.shapeMix or 0.5, skinMix = hb.skinMix or 0.5,
        }
    end

    if data.faceFeatures then
        for id, scale in pairs(data.faceFeatures) do
            SetPedFaceFeature(ped, tonumber(id), scale or 0.0)
        end
    end

    if data.overlays then
        for id, vals in pairs(data.overlays) do
            local overlayId = tonumber(id)
            SetPedHeadOverlay(ped, overlayId, vals.value or 255, vals.opacity or 0.0)
            if vals.colorType and vals.color and (vals.value or 255) ~= 255 then
                SetPedHeadOverlayColor(ped, overlayId, vals.colorType, vals.color, vals.color2 or vals.color)
            end
        end
    end

    if data.eyeColor then SetPedEyeColor(ped, data.eyeColor) end

    if data.hairColor or data.hairHighlight then
        SetPedHairColor(ped, data.hairColor or 0, data.hairHighlight or 0)
    end
end

function RandomizePed()
    local ped = PlayerPedId()
    for _, cat in ipairs(PM.categories) do
        for _, item in ipairs(cat.items) do
            -- FIX: component 10 ("Decals") is in this data table but has no
            -- corresponding control anywhere in the menu UI. Randomizing it
            -- left players with a glitched decal/texture they had no way to
            -- remove. Always force it to none instead of rolling a random value.
            if item.id == 10 then
                SetPedComponentVariation(ped, 10, 0, 0, 0)
            else
                local safeMax = GetSafeMaxDrawable(item.id)
                local applied = false
                if safeMax >= 0 then
                    for _ = 1, 20 do
                        local drawable = math.random(0, safeMax)
                        local texMax = GetNumberOfPedTextureVariations(ped, item.id, drawable) - 1
                        local texture = 0
                        if texMax > 0 then texture = math.random(0, math.min(4, texMax)) end
                        if IsPedComponentVariationValid(ped, item.id, drawable, texture) then
                            SetPedComponentVariation(ped, item.id, drawable, texture, 0)
                            applied = true
                            break
                        end
                    end
                end
                if not applied then SetPedComponentVariation(ped, item.id, 0, 0, 0) end
            end
        end
    end

    for _, prop in ipairs(PM.props) do
        if math.random() > 0.6 then
            local safeMax = GetSafeMaxProp(prop.id)
            if safeMax >= 0 then
                local pd = math.random(0, safeMax)
                local ptMax = GetNumberOfPedPropTextureVariations(ped, prop.id, pd) - 1
                local pt = ptMax > 0 and math.random(0, math.min(3, ptMax)) or 0
                SetPedPropIndex(ped, prop.id, pd, pt, true)
            else
                ClearPedProp(ped, prop.id)
            end
        else
            ClearPedProp(ped, prop.id)
        end
    end

    local rShapeFirst, rShapeSecond = math.random(0, 45), math.random(0, 45)
    local rSkinFirst, rSkinSecond   = math.random(0, 45), math.random(0, 45)
    local rShapeMix, rSkinMix       = math.random(), math.random()
    SetPedHeadBlendData(ped, rShapeFirst, rShapeSecond, 0,
        rSkinFirst, rSkinSecond, 0, rShapeMix, rSkinMix, 0.0, false)
    PM.headBlendCache = {
        shapeFirst = rShapeFirst, shapeSecond = rShapeSecond,
        skinFirst = rSkinFirst, skinSecond = rSkinSecond,
        shapeMix = rShapeMix, skinMix = rSkinMix,
    }

    for _, ff in ipairs(PM.faceFeatures) do
        SetPedFaceFeature(ped, ff.id, (math.random() * 2 - 1))
    end

    for _, ov in ipairs(PM.overlays) do
        if math.random() > 0.5 then
            local val = math.random(0, ov.max)
            local op = 0.3 + (math.random() * 0.7)
            SetPedHeadOverlay(ped, ov.id, val, op)
            if ov.hasColor and ov.colorType then
                SetPedHeadOverlayColor(ped, ov.id, ov.colorType, math.random(0, 63), math.random(0, 63))
            end
        else
            SetPedHeadOverlay(ped, ov.id, 255, 0.0)
        end
    end

    SetPedHairColor(ped, math.random(0, 63), math.random(0, 63))
    SetPedEyeColor(ped, math.random(0, 31))
end

function ResetToDefault()
    local ped = PlayerPedId()
    SetPedComponentVariation(ped, 11, 15, 0, 0)
    SetPedComponentVariation(ped, 8, 15, 0, 0)
    SetPedComponentVariation(ped, 3, 15, 0, 0)
    SetPedComponentVariation(ped, 4, 14, 0, 0)
    SetPedComponentVariation(ped, 6, 1, 0, 0)
    SetPedComponentVariation(ped, 1, 0, 0, 0)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    SetPedComponentVariation(ped, 7, 0, 0, 0)
    SetPedComponentVariation(ped, 9, 0, 0, 0)
    SetPedComponentVariation(ped, 10, 0, 0, 0)
    for _, p in ipairs(PM.props) do ClearPedProp(ped, p.id) end
    for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 0.0) end
end

-- ============================================================
-- OPEN / CLOSE
-- ============================================================

function OpenPedMngr()
    if PM.open then return end
    PM.open = true

    local ped = PlayerPedId()
    PM.oldPos = GetEntityCoords(ped)
    PM.oldHeading = GetEntityHeading(ped)

    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetPlayerInvincible(PlayerId(), true)

    -- Create camera with FULL BODY default view
    local coords = PM.oldPos
    PM.camera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA",
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0, 35.0, false, 0)
    SetCamActive(PM.camera, true)
    RenderScriptCams(true, true, 500, false, false)

    -- Set default full-body view
    SetCameraView('full')

    SetEntityHeading(ped, 180.0)

    local flatComponents = {}
    for _, cat in ipairs(PM.categories) do
        for _, item in ipairs(cat.items) do
            local safeMax = GetSafeMaxDrawable(item.id)
            table.insert(flatComponents, { id = item.id, name = item.name, max = safeMax })
        end
    end

    local enrichedProps = {}
    for _, prop in ipairs(PM.props) do
        local safeMax = GetSafeMaxProp(prop.id)
        table.insert(enrichedProps, { id = prop.id, name = prop.name, max = safeMax })
    end

    local modelList = {}
    for _, m in ipairs(PM.models) do
        table.insert(modelList, { name = m.name, hash = m.hash, id = m.id })
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        components = flatComponents,
        props = enrichedProps,
        overlays = PM.overlays,
        pedModels = modelList,
        hairColors = PM.hairColors,
        currentData = BuildCurrentDataWithInfo(),
        savedOutfits = {},
        forceOpen = PM.forceOpen,
    })

    TriggerServerEvent('pedmngr:listOutfits', GetEntityModel(PlayerPedId()))
end

function ClosePedMngr()
    if not PM.open then return end
    PM.open = false
    PM.forceOpen = false

    if PM.camera then
        SetCamActive(PM.camera, false)
        DestroyCam(PM.camera, false)
        PM.camera = nil
    end
    RenderScriptCams(false, true, 500, false, false)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetPlayerInvincible(PlayerId(), false)

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })

    -- Auto-save current appearance when closing editor
    TriggerServerEvent('pedmngr:saveAppearance', GetCurrentData())
end

-- ============================================================
-- COMMANDS
-- ============================================================

RegisterCommand("register", function() OpenPedMngr() end, false)
RegisterCommand("appearance", function() OpenPedMngr() end, false)

-- ============================================================
-- SERVER EVENTS
-- ============================================================

RegisterNetEvent('pedmngr:applyAppearance')
AddEventHandler('pedmngr:applyAppearance', function(data)
    PM.serverAppearance = data
    if data then
        ApplyData(data)
    end
end)

RegisterNetEvent('pedmngr:openEditor')
AddEventHandler('pedmngr:openEditor', function()
    PM.forceOpen = true
    Citizen.CreateThread(function()
        Wait(2000)
        OpenPedMngr()
    end)
end)

RegisterNetEvent('pedmngr:applyData')
AddEventHandler('pedmngr:applyData', function(data)
    if data then ApplyData(data) end
    if PM.open then
        SendNUIMessage({
            action = 'refreshData',
            data = BuildCurrentDataWithInfo()
        })
    end
end)

RegisterNetEvent('pedmngr:outfitList')
AddEventHandler('pedmngr:outfitList', function(names)
    SendNUIMessage({
        action = 'outfitList',
        outfits = names
    })
end)

RegisterNetEvent('pedmngr:appearanceSaved')
AddEventHandler('pedmngr:appearanceSaved', function()
    PM.forceOpen = false

end)

-- ============================================================
-- PED CHANGE DETECTION — Re-apply appearance after respawn
-- FIX: Don't re-apply when editor is open (model switcher)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Wait(1000)
        -- SKIP if editor is open (prevents model switcher from reverting)
        if PM.open then
            PM.lastPedModel = GetEntityModel(PlayerPedId())
            goto continue
        end

        -- SKIP while ApplyData is already mid-swap (e.g. right after join).
        -- Without this, this thread can see the briefly-still-male ped model,
        -- think "model changed unexpectedly", and fire a SECOND concurrent
        -- ApplyData() on top of the one already running -- two overlapping
        -- swaps racing on the same ped is exactly what leaves it half-applied
        -- (wrong mesh wearing mismatched component indices).
        if PM.modelSwitching then
            goto continue
        end

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local model = GetEntityModel(ped)
            if PM.lastPedModel and PM.lastPedModel ~= model and PM.serverAppearance then
                Wait(500)
                ApplyData(PM.serverAppearance)
            end
            PM.lastPedModel = model
        end
        ::continue::
    end
end)

-- ============================================================
-- PERIODIC AUTO-SAVE — Silently saves appearance every 60s
-- This ensures rejoin always wears what you actually had on
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Wait(60000) -- Every 60 seconds
        -- SKIP while a model swap is in flight. GetCurrentData() reads
        -- straight off PlayerPedId(), so capturing mid-swap can snapshot a
        -- half-applied ped (still wearing the previous model's components)
        -- and write that bad snapshot straight back over a good save.
        if not PM.open and not PM.modelSwitching then
            PM.autoSaveTimer = PM.autoSaveTimer + 1
            -- Auto-save current appearance to server
            local data = GetCurrentData()
            TriggerServerEvent('pedmngr:saveAppearance', data)
            -- Also update the local cache so respawns get latest
            PM.serverAppearance = data
        end
    end
end)

-- ============================================================
-- INIT
-- ============================================================

AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end

    math.randomseed(GetGameTimer() + GetPlayerServerId(PlayerId()))


    Citizen.CreateThread(function()
        local attempts = 0
        local maxAttempts = 30

        while attempts < maxAttempts do
            Wait(500)
            attempts = attempts + 1

            local ped = PlayerPedId()
            if DoesEntityExist(ped) and ped ~= -1 then
                local model = GetEntityModel(ped)
                if FREEMODE_MODELS[model] then
                    if not PM.hasNotifiedReady then
                        PM.hasNotifiedReady = true
                        PM.lastPedModel = model
                        TriggerServerEvent('pedmngr:playerReady')
                    end
                    return
                end
            end
        end

        if not PM.hasNotifiedReady then
            PM.hasNotifiedReady = true
            TriggerServerEvent('pedmngr:playerReady')
        end
    end)
end)

AddEventHandler("playerSpawned", function()
    if not PM.hasNotifiedReady then
        PM.hasNotifiedReady = true
        Citizen.CreateThread(function()
            Wait(2000)
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                PM.lastPedModel = GetEntityModel(ped)
            end
            TriggerServerEvent('pedmngr:playerReady')
        end)
    end
end)