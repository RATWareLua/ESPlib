--!nocheck
-- Module: CornerBox.luau

local CornerBox = {
    Priority = 10,             -- Приоритет рендеринга (Z-Index)
    SettingsKey = "CornerBox"  -- Явный маппинг на ключ в settings
}
local DRAWING = Drawing.new
local V2 = Vector2.new
local math_floor = math.floor

local math_clamp = math.clamp or function(v, lo, hi)
    return v < lo and lo or v > hi and hi or v
end

local DEFAULT_COLOR = Color3.fromRGB(0, 255, 120)

-- Противоположный (инвертированный) цвет для контура
local function invert(c)
    return Color3.new(1 - c.R, 1 - c.G, 1 - c.B)
end

function CornerBox.Init(espObj)
    -- Именованные линии (TL/TR/BL/BR + H/V) — читаемее в позиционировании
    local lines = {
        TL_H = DRAWING("Line"), TL_V = DRAWING("Line"),
        TR_H = DRAWING("Line"), TR_V = DRAWING("Line"),
        BL_H = DRAWING("Line"), BL_V = DRAWING("Line"),
        BR_H = DRAWING("Line"), BR_V = DRAWING("Line")
    }
    espObj.Drawings.CornerBox = lines

    local settings = espObj.Settings
    local color = settings.BoxColor or DEFAULT_COLOR
    local thickness = settings.BoxThickness or 2.5
    local transparency = settings.BoxTransparency or 1

    -- Плоский массив тех же линий — для быстрых проходов в кадре (мимо pairs по хэшу)
    local list = {
        lines.TL_H, lines.TL_V, lines.TR_H, lines.TR_V,
        lines.BL_H, lines.BL_V, lines.BR_H, lines.BR_V,
    }

    for i = 1, 8 do
        local line = list[i]
        line.Visible      = false
        line.Color        = color
        line.Thickness    = thickness
        line.Transparency = transparency
    end

    -- Контуры: подложки контрастного цвета, ПОД core по ZIndex
    local outlines
    if settings.Outline then
        outlines = {}
        local ocolor = settings.OutlineColor or invert(color)
        local othick = thickness + (settings.OutlineThickness or 2)
        for i = 1, 8 do
            local o = DRAWING("Line")
            o.Visible      = false
            o.Color        = ocolor
            o.Thickness    = othick
            o.Transparency = transparency
            o.ZIndex       = 0
            outlines[i] = o
            list[i].ZIndex = 1
        end
    end

    -- Приватный неймспейс модуля в CustomData (кэш для dirty-check)
    espObj.CustomData.CornerBox = {
        List = list,
        Outlines = outlines,
        Shown = false,
        LastThickness = thickness,
        LastColor = color,
        LastTransparency = transparency,
    }
end

function CornerBox.Update(espObj, renderData)
    local lines = espObj.Drawings.CornerBox
    if not lines then return end

    local cache = espObj.CustomData.CornerBox
    local list = cache.List
    local outlines = cache.Outlines

    if not renderData.OnScreen then
        -- Гасим только при переходе в оффскрин, а не каждый кадр
        if cache.Shown then
            for i = 1, 8 do list[i].Visible = false end
            if outlines then for i = 1, 8 do outlines[i].Visible = false end end
            cache.Shown = false
        end
        return
    end

    local set = espObj.Settings

    local x, y = renderData.X, renderData.Y
    local w, h = renderData.W, renderData.H

    local dynT        = set.BoxThickness or 2.5
    local cornerScale = set.CornerScale or 0.25
    local halfT       = dynT * 0.5 -- держим float до округления координат

    local minLen = 3
    local maxLen = w * 0.5
    local len
    if maxLen >= minLen then
        len = math_clamp(w * cornerScale, minLen, maxLen)
    else
        len = maxLen
    end

    -- Пиксельное выравнивание координат
    local roundedX = math_floor(x)
    local roundedY = math_floor(y)
    local roundedW = math_floor(w)
    local roundedH = math_floor(h)
    local roundedLen = math_floor(len)

    -- off округляется ОДИН раз и применяется симметрично на обе стороны.
    -- floor(a - b) != a - floor(b) при дробном b — это давало лишний пиксель
    -- смещения на стороне "-" (tLeft/tTop). round-to-nearest минимизирует погрешность.
    local off = math_floor(halfT + 0.5)

    local tLeft  = roundedX - off
    local tRight = roundedX + roundedW + off
    local tTop   = roundedY - off
    local tBot   = roundedY + roundedH + off

    -- TL Corner (Top-Left)
    lines.TL_H.From = V2(tLeft, roundedY);              lines.TL_H.To = V2(roundedX + roundedLen, roundedY)
    lines.TL_V.From = V2(roundedX, tTop);               lines.TL_V.To = V2(roundedX, roundedY + roundedLen)
    -- TR Corner (Top-Right)
    lines.TR_H.From = V2(tRight, roundedY);             lines.TR_H.To = V2(roundedX + roundedW - roundedLen, roundedY)
    lines.TR_V.From = V2(roundedX + roundedW, tTop);    lines.TR_V.To = V2(roundedX + roundedW, roundedY + roundedLen)
    -- BL Corner (Bottom-Left)
    lines.BL_H.From = V2(tLeft, roundedY + roundedH);   lines.BL_H.To = V2(roundedX + roundedLen, roundedY + roundedH)
    lines.BL_V.From = V2(roundedX, tBot);               lines.BL_V.To = V2(roundedX, roundedY + roundedH - roundedLen)
    -- BR Corner (Bottom-Right)
    lines.BR_H.From = V2(tRight, roundedY + roundedH);  lines.BR_H.To = V2(roundedX + roundedW - roundedLen, roundedY + roundedH)
    lines.BR_V.From = V2(roundedX + roundedW, tBot);    lines.BR_V.To = V2(roundedX + roundedW, roundedY + roundedH - roundedLen)

    -- Контур повторяет координаты основных линий
    if outlines then
        for i = 1, 8 do
            local l = list[i]
            local o = outlines[i]
            o.From = l.From
            o.To = l.To
        end
    end

    local color = set.BoxColor or DEFAULT_COLOR
    local transp = set.BoxTransparency or 1

    -- Dirty-check: пишем свойства линий только когда они реально поменялись
    local updateThickness = (dynT ~= cache.LastThickness)
    local updateColor = (color ~= cache.LastColor)
    local updateTransparency = (transp ~= cache.LastTransparency)

    if updateThickness or updateColor or updateTransparency then
        for i = 1, 8 do
            local line = list[i]
            if updateThickness then line.Thickness = dynT end
            if updateColor then line.Color = color end
            if updateTransparency then line.Transparency = transp end
        end

        if outlines then
            local ocolor = set.OutlineColor or invert(color)
            local othick = dynT + (set.OutlineThickness or 2)
            for i = 1, 8 do
                local o = outlines[i]
                if updateThickness then o.Thickness = othick end
                if updateColor then o.Color = ocolor end
                if updateTransparency then o.Transparency = transp end
            end
        end

        cache.LastThickness = dynT
        cache.LastColor = color
        cache.LastTransparency = transp
    end

    -- Показываем только при переходе из оффскрина
    if not cache.Shown then
        for i = 1, 8 do list[i].Visible = true end
        if outlines then for i = 1, 8 do outlines[i].Visible = true end end
        cache.Shown = true
    end
end

function CornerBox.Destroy(espObj)
    local lines = espObj.Drawings.CornerBox
    if lines then
        for _, line in pairs(lines) do
            line:Remove()
        end
        local cache = espObj.CustomData.CornerBox
        if cache and cache.Outlines then
            for i = 1, 8 do cache.Outlines[i]:Remove() end
        end
        espObj.Drawings.CornerBox = nil
        espObj.CustomData.CornerBox = nil
    end
end

return CornerBox
