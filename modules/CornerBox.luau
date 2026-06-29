--!nocheck
-- Module: CornerBox.luau
-- Описание: Рисует 8 линий (уголки) вокруг объекта. Логика 1в1 из оригинала.

local CornerBox = {}
local DRAWING = Drawing.new
local V2 = Vector2.new
local math_floor = math.floor

local math_clamp = math.clamp or function(v, lo, hi)
    return v < lo and lo or v > hi and hi or v
end

function CornerBox.Init(espObj)
    espObj.Drawings.CornerBox = {}

    local color = espObj.Settings.BoxColor or Color3.fromRGB(0, 255, 120)
    local thickness = espObj.Settings.BoxThickness or 2.5
    local transparency = espObj.Settings.BoxTransparency or 1

    for i = 1, 8 do
        local line = DRAWING("Line")
        if line then
            line.Visible      = false
            line.Color        = color
            line.Thickness    = thickness
            line.Transparency = transparency
            espObj.Drawings.CornerBox[i] = line
        end
    end

    espObj.CustomData.LastThickness = -1 
end

function CornerBox.Update(espObj, renderData)
    local lines = espObj.Drawings.CornerBox
    if not lines or not lines[1] then return end

    if not renderData.OnScreen then
        for i = 1, 8 do
            if lines[i] then lines[i].Visible = false end
        end
        return
    end

    local set = espObj.Settings

    local x, y = renderData.X, renderData.Y
    local w, h = renderData.W, renderData.H

    local dynT        = set.BoxThickness or 2.5
    local cornerScale = set.CornerScale or 0.25
    local halfT       = dynT * 0.5

    local minLen = 3
    local maxLen = w * 0.5
    local len
    if maxLen >= minLen then
        len = math_clamp(w * cornerScale, minLen, maxLen)
    else
        len = maxLen  -- бокс < 6px: уголки = половина ширины
    end

    x     = math_floor(x)
    y     = math_floor(y)
    w     = math_floor(w)
    h     = math_floor(h)
    len   = math_floor(len)
    halfT = math_floor(halfT)

    lines[1].From = V2(x - halfT,    y);             lines[1].To = V2(x + len,     y)
    lines[2].From = V2(x,            y - halfT);     lines[2].To = V2(x,           y + len)
    -- Правый верхний
    lines[3].From = V2(x + w + halfT, y);            lines[3].To = V2(x + w - len, y)
    lines[4].From = V2(x + w,         y - halfT);    lines[4].To = V2(x + w,       y + len)
    -- Левый нижний
    lines[5].From = V2(x - halfT,    y + h);         lines[5].To = V2(x + len,     y + h)
    lines[6].From = V2(x,            y + h + halfT); lines[6].To = V2(x,           y + h - len)
    -- Правый нижний
    lines[7].From = V2(x + w + halfT, y + h);        lines[7].To = V2(x + w - len, y + h)
    lines[8].From = V2(x + w,         y + h + halfT); lines[8].To = V2(x + w,      y + h - len)

    local needsThicknessUpdate = (dynT ~= espObj.CustomData.LastThickness)
    if needsThicknessUpdate then
        espObj.CustomData.LastThickness = dynT
    end

    local color = set.BoxColor or Color3.fromRGB(0, 255, 120)
    local transp = set.BoxTransparency or 1

    for i = 1, 8 do
        local l = lines[i]
        if needsThicknessUpdate then
            l.Thickness = dynT
        end
        l.Color = color
        l.Transparency = transp
        l.Visible = true
    end
end

function CornerBox.Destroy(espObj)
    if espObj.Drawings.CornerBox then
        for i = 1, 8 do
            if espObj.Drawings.CornerBox[i] then
                espObj.Drawings.CornerBox[i]:Remove()
            end
        end
        espObj.Drawings.CornerBox = nil
    end
end

return CornerBox