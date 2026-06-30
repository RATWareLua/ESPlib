--!nocheck
-- Module: Tracer.luau
-- Линия от края экрана к низу бокса цели. Полностью на контракте ядра
-- (renderData + espObj.Instance), правок в main.luau не требует.

local Tracer = {
    Priority = 20,            -- рисуется после бокса
    SettingsKey = "Tracer"    -- ключ в settings, которым модуль включают
}

local DRAWING = Drawing.new
local V2 = Vector2.new

local cloneref = cloneref or function(o) return o end
local Workspace = cloneref(game:GetService("Workspace"))
local UserInputService = cloneref(game:GetService("UserInputService"))

-- Камера держится свежей через сигнал, а не читается каждый кадр
local Camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

local DEFAULT_COLOR = Color3.fromRGB(255, 50, 50)

-- Точка-начало трассера на экране в зависимости от режима
local function originPoint(vp, mode)
    if mode == "mouse" then
        local m = UserInputService:GetMouseLocation()
        return m.X, m.Y
    elseif mode == "top" then
        return vp.X * 0.5, 0
    elseif mode == "center" then
        return vp.X * 0.5, vp.Y * 0.5
    else -- "bottom" (по умолчанию)
        return vp.X * 0.5, vp.Y
    end
end

function Tracer.Init(espObj)
    local settings = espObj.Settings
    local line = DRAWING("Line")
    line.Visible      = false
    line.Thickness    = settings.TracerThickness or 1.5
    line.Transparency = settings.TracerTransparency or 1
    line.Color        = settings.TracerColor or settings.BoxColor or DEFAULT_COLOR

    espObj.Drawings.Tracer = line
    espObj.CustomData.Tracer = {
        Shown = false,
        LastColor = line.Color,
        LastThickness = line.Thickness,
        LastTransparency = line.Transparency,
    }
end

function Tracer.Update(espObj, renderData)
    local line = espObj.Drawings.Tracer
    if not line then return end

    local cache = espObj.CustomData.Tracer

    if not renderData.OnScreen or not Camera then
        if cache.Shown then
            line.Visible = false
            cache.Shown = false
        end
        return
    end

    local set = espObj.Settings

    -- Геометрия: низ экрана -> низ-центр бокса (≈ ноги цели)
    local ox, oy = originPoint(Camera.ViewportSize, set.TracerOrigin)
    local tx = renderData.X + renderData.W * 0.5
    local ty = renderData.Y + renderData.H

    line.From = V2(ox, oy)
    line.To = V2(tx, ty)

    -- Свойства — через dirty-check (как в CornerBox)
    local color = set.TracerColor or set.BoxColor or DEFAULT_COLOR
    local thickness = set.TracerThickness or 1.5
    local transp = set.TracerTransparency or 1

    if color ~= cache.LastColor then line.Color = color; cache.LastColor = color end
    if thickness ~= cache.LastThickness then line.Thickness = thickness; cache.LastThickness = thickness end
    if transp ~= cache.LastTransparency then line.Transparency = transp; cache.LastTransparency = transp end

    if not cache.Shown then
        line.Visible = true
        cache.Shown = true
    end
end

function Tracer.Destroy(espObj)
    local line = espObj.Drawings.Tracer
    if line then
        line:Remove()
        espObj.Drawings.Tracer = nil
        espObj.CustomData.Tracer = nil
    end
end

return Tracer
