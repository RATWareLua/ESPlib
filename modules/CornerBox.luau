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

function CornerBox.Init(espObj)
    -- Проблема 10: Уходим от индексов 1-8 к структурированным именам линий
    espObj.Drawings.CornerBox = {
        TL_H = DRAWING("Line"), TL_V = DRAWING("Line"),
        TR_H = DRAWING("Line"), TR_V = DRAWING("Line"),
        BL_H = DRAWING("Line"), BL_V = DRAWING("Line"),
        BR_H = DRAWING("Line"), BR_V = DRAWING("Line")
    }
    
    local settings = espObj.Settings
    local color = settings.BoxColor or Color3.fromRGB(0, 255, 120)
    local thickness = settings.BoxThickness or 2.5
    local transparency = settings.BoxTransparency or 1

    for _, line in pairs(espObj.Drawings.CornerBox) do
        line.Visible      = false
        line.Color        = color
        line.Thickness    = thickness
        line.Transparency = transparency
    end

    -- Проблема 9: Изолируем CustomData в приватный неймспейс
    espObj.CustomData.CornerBox = {
        LastThickness = thickness,
        LastColor = color,
        LastTransparency = transparency
    } 
end

function CornerBox.Update(espObj, renderData)
    local lines = espObj.Drawings.CornerBox
    if not lines then return end

    if not renderData.OnScreen then
        for _, line in pairs(lines) do
            line.Visible = false
        end
        return
    end

    local set = espObj.Settings
    local cache = espObj.CustomData.CornerBox
    
    local x, y = renderData.X, renderData.Y
    local w, h = renderData.W, renderData.H

    local dynT        = set.BoxThickness or 2.5
    local cornerScale = set.CornerScale or 0.25
    local halfT       = dynT * 0.5 -- Проблема 8: сохраняем float до этапа вычисления координат

    local minLen = 3
    local maxLen = w * 0.5
    local len
    if maxLen >= minLen then
        len = math_clamp(w * cornerScale, minLen, maxLen)
    else
        len = maxLen
    end

    -- Проблема 8: Выравнивание без потери точности halfT
    local roundedX = math_floor(x)
    local roundedY = math_floor(y)
    local roundedW = math_floor(w)
    local roundedH = math_floor(h)
    local roundedLen = math_floor(len)

    local tLeft  = math_floor(roundedX - halfT)
    local tRight = math_floor(roundedX + roundedW + halfT)
    local tTop   = math_floor(roundedY - halfT)
    local tBot   = math_floor(roundedY + roundedH + halfT)

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

    -- Свойства для Dirty check
    local color = set.BoxColor or Color3.fromRGB(0, 255, 120)
    local transp = set.BoxTransparency or 1

    -- Проблема 7: Оптимальное обновление свойств через dirty check
    local updateThickness = (dynT ~= cache.LastThickness)
    local updateColor = (color ~= cache.LastColor)
    local updateTransparency = (transp ~= cache.LastTransparency)

    if updateThickness or updateColor or updateTransparency then
        for _, line in pairs(lines) do
            if updateThickness then line.Thickness = dynT end
            if updateColor then line.Color = color end
            if updateTransparency then line.Transparency = transp end
        end
        cache.LastThickness = dynT
        cache.LastColor = color
        cache.LastTransparency = transp
    end

    for _, line in pairs(lines) do
        line.Visible = true
    end
end

function CornerBox.Destroy(espObj)
    if espObj.Drawings.CornerBox then
        for _, line in pairs(espObj.Drawings.CornerBox) do
            line:Remove()
        end
        espObj.Drawings.CornerBox = nil
        espObj.CustomData.CornerBox = nil
    end
end

return CornerBox
