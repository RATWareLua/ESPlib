--!nocheck
-- Module: CornerBox3D.luau
-- Угловой 3D-бокс: 8 вершин мирового параллелепипеда проецируются модулем,
-- в каждом углу рисуются короткие скобки вдоль трёх рёбер. Опирается на
-- renderData.WorldCF / WorldSize (мировой трансформ, уже разрешённый ядром).
-- Опционально (Outline) — подложка-контур контрастного цвета ПОД каждой скобкой.

local CornerBox3D = {
    Priority = 15,
    SettingsKey = "CornerBox3D"
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local V3 = Vector3.new

local cloneref = cloneref or function(o) return o end
local Workspace = cloneref(game:GetService("Workspace"))

local Camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

local DEFAULT_COLOR = Color3.fromRGB(0, 255, 120)

-- Противоположный (инвертированный) цвет для контура
local function invert(c)
    return Color3.new(1 - c.R, 1 - c.G, 1 - c.B)
end

-- Вершины AABB (знаки по осям X,Y,Z)
local SIGNS = {
    {  1,  1,  1 }, {  1,  1, -1 }, {  1, -1,  1 }, {  1, -1, -1 },
    { -1,  1,  1 }, { -1,  1, -1 }, { -1, -1,  1 }, { -1, -1, -1 },
}

-- 12 рёбер (пары вершин, отличающихся одной осью)
local EDGES = {
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 }, -- по X
    { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 }, -- по Y
    { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 }, -- по Z
}

-- 24 «скобки»: от каждого конца ребра короткий отрезок внутрь ребра
local STUBS = {}
for _, e in ipairs(EDGES) do
    STUBS[#STUBS + 1] = { e[1], e[2] }
    STUBS[#STUBS + 1] = { e[2], e[1] }
end

local function newArray(n, fill)
    if table.create then return table.create(n, fill) end
    local t = {}
    for i = 1, n do t[i] = fill end
    return t
end

function CornerBox3D.Init(espObj)
    local settings = espObj.Settings
    local color = settings.BoxColor or DEFAULT_COLOR
    local thickness = settings.Box3DThickness or settings.BoxThickness or 1.5
    local transp = settings.BoxTransparency or 1

    local lines = {}
    for i = 1, 24 do
        local line = DRAWING("Line")
        line.Visible      = false
        line.Color        = color
        line.Thickness    = thickness
        line.Transparency = transp
        lines[i] = line
    end
    espObj.Drawings.CornerBox3D = lines

    -- Контуры: подложки контрастного цвета, ПОД core по ZIndex
    local outlines
    if settings.Outline then
        outlines = {}
        local ocolor = settings.OutlineColor or invert(color)
        local othick = thickness + (settings.OutlineThickness or 2)
        for i = 1, 24 do
            local o = DRAWING("Line")
            o.Visible      = false
            o.Color        = ocolor
            o.Thickness    = othick
            o.Transparency = transp
            o.ZIndex       = 0
            outlines[i] = o
            lines[i].ZIndex = 1
        end
    end

    espObj.CustomData.CornerBox3D = {
        Outlines = outlines,
        Shown = false,
        LastColor = color,
        LastThickness = thickness,
        LastTransparency = transp,
        PX = newArray(8, 0),       -- переиспользуемые буферы проекции
        PY = newArray(8, 0),
        PV = newArray(8, false),
    }
end

function CornerBox3D.Update(espObj, renderData)
    local lines = espObj.Drawings.CornerBox3D
    if not lines then return end

    local cache = espObj.CustomData.CornerBox3D
    local outlines = cache.Outlines
    local cf = renderData.WorldCF

    if not renderData.OnScreen or not cf or not Camera then
        if cache.Shown then
            for i = 1, 24 do lines[i].Visible = false end
            if outlines then for i = 1, 24 do outlines[i].Visible = false end end
            cache.Shown = false
        end
        return
    end

    local size = renderData.WorldSize
    local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
    local wtvp = Camera.WorldToViewportPoint
    local PX, PY, PV = cache.PX, cache.PY, cache.PV

    -- Проекция 8 вершин (модуль делает это сам — ядро лишнего не считает)
    for i = 1, 8 do
        local s = SIGNS[i]
        local p = wtvp(Camera, cf * V3(s[1] * hx, s[2] * hy, s[3] * hz))
        PX[i] = p.X
        PY[i] = p.Y
        PV[i] = p.Z > 0
    end

    local set = espObj.Settings
    local frac = set.Corner3DScale or 0.3

    -- Скобки: отрезок от вершины внутрь ребра на долю frac (+ контур под ним)
    for k = 1, 24 do
        local stub = STUBS[k]
        local a, b = stub[1], stub[2]
        local line = lines[k]
        local o = outlines and outlines[k]
        if PV[a] and PV[b] then
            local ax, ay = PX[a], PY[a]
            local bx, by = PX[b], PY[b]
            local from = V2(ax, ay)
            local to = V2(ax + (bx - ax) * frac, ay + (by - ay) * frac)
            line.From = from
            line.To = to
            line.Visible = true
            if o then
                o.From = from
                o.To = to
                o.Visible = true
            end
        else
            line.Visible = false
            if o then o.Visible = false end
        end
    end
    cache.Shown = true

    -- Свойства — через dirty-check
    local color = set.BoxColor or DEFAULT_COLOR
    local thickness = set.Box3DThickness or set.BoxThickness or 1.5
    local transp = set.BoxTransparency or 1

    if color ~= cache.LastColor or thickness ~= cache.LastThickness or transp ~= cache.LastTransparency then
        for i = 1, 24 do
            local line = lines[i]
            line.Color        = color
            line.Thickness    = thickness
            line.Transparency = transp
        end

        if outlines then
            local ocolor = set.OutlineColor or invert(color)
            local othick = thickness + (set.OutlineThickness or 2)
            for i = 1, 24 do
                local o = outlines[i]
                o.Color        = ocolor
                o.Thickness    = othick
                o.Transparency = transp
            end
        end

        cache.LastColor = color
        cache.LastThickness = thickness
        cache.LastTransparency = transp
    end
end

function CornerBox3D.Destroy(espObj)
    local lines = espObj.Drawings.CornerBox3D
    if lines then
        for i = 1, #lines do
            lines[i]:Remove()
        end
        local cache = espObj.CustomData.CornerBox3D
        if cache and cache.Outlines then
            for i = 1, 24 do cache.Outlines[i]:Remove() end
        end
        espObj.Drawings.CornerBox3D = nil
        espObj.CustomData.CornerBox3D = nil
    end
end

return CornerBox3D
