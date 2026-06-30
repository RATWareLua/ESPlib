--!nocheck
-- Module: Tracer.luau
-- Линия от курсора/центра к цели. На экране — к низу бокса; вне экрана/за спиной —
-- к точке у края экрана в том же screen-space направлении, что и Arrows.
-- Опирается на renderData.WorldCF.

local Tracer = {
    Priority = 20,            -- рисуется после бокса
    SettingsKey = "Tracer"    -- ключ в settings, которым модуль включают
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local math_min = math.min
local math_huge = math.huge

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

local function hideLine(line, cache)
    if cache.Shown then
        line.Visible = false
        cache.Shown = false
    end
end

local function screenDirection(targetPos)
    local projected = Camera:WorldToViewportPoint(targetPos)
    local center = Camera.ViewportSize * 0.5
    local dir = V2(projected.X - center.X, projected.Y - center.Y)

    -- У точки за камерой perspective projection зеркалится; Arrows чинят это тем же flip.
    if projected.Z < 0 then
        dir = -dir
    end

    if dir.Magnitude <= 0.01 then
        return projected.Z < 0 and V2(0, 1) or nil
    end

    return dir.Unit
end

-- Точка-цель для off-screen/за-спиной случая. Direction берём из той же модели,
-- что и стрелки, чтобы endpoint не перепрыгивал на противоположный край экрана.
local function offscreenPoint(targetPos)
    local vp = Camera.ViewportSize
    local cx, cy = vp.X * 0.5, vp.Y * 0.5
    local dir = screenDirection(targetPos)
    if not dir then return nil end

    -- Пересечение луча (cx,cy)+t*dir с прямоугольником экрана: ближайшая граница
    local t = math_huge
    if dir.X > 0 then t = math_min(t, (vp.X - cx) / dir.X)
    elseif dir.X < 0 then t = math_min(t, -cx / dir.X) end
    if dir.Y > 0 then t = math_min(t, (vp.Y - cy) / dir.Y)
    elseif dir.Y < 0 then t = math_min(t, -cy / dir.Y) end
    return cx + dir.X * t, cy + dir.Y * t
end

function Tracer.Init(espObj)
    local s = espObj.Settings
    local thickness = s.TracerThickness or 1.5
    local transp = s.TracerTransparency or 1
    local color = s.TracerColor or s.BoxColor or DEFAULT_COLOR

    local line = DRAWING("Line")
    line.Visible      = false
    line.Thickness    = thickness
    line.Transparency = transp
    line.Color        = color

    espObj.Drawings.Tracer = line
    espObj.CustomData.Tracer = {
        Shown = false,
        LastColor = color,
        LastThickness = thickness,
        LastTransparency = transp,
    }
end

function Tracer.Update(espObj, renderData)
    local line = espObj.Drawings.Tracer
    if not line then return end

    local cache = espObj.CustomData.Tracer
    local cf = renderData.WorldCF

    -- Реально скрыт (выключен / вне радиуса / нет родителя): WorldCF отсутствует
    if not cf or not Camera then
        hideLine(line, cache)
        return
    end

    local set = espObj.Settings

    -- Точка цели: на экране — низ бокса; вне экрана/за спиной — старая arws-точка у края.
    local tx, ty
    local vp = Camera.ViewportSize
    if renderData.OnScreen then
        tx = renderData.X + renderData.W * 0.5
        ty = renderData.Y + renderData.H
    else
        tx, ty = offscreenPoint(cf.Position)
        if not tx then
            hideLine(line, cache)
            return
        end
    end

    local ox, oy = originPoint(vp, set.TracerOrigin)
    line.From = V2(ox, oy)
    line.To = V2(tx, ty)

    -- Свойства — через dirty-check
    local color = set.TracerColor or set.BoxColor or DEFAULT_COLOR
    local thickness = set.TracerThickness or 1.5
    local transp = set.TracerTransparency or 1

    if color ~= cache.LastColor then
        line.Color = color
        cache.LastColor = color
    end
    if thickness ~= cache.LastThickness then
        line.Thickness = thickness
        cache.LastThickness = thickness
    end
    if transp ~= cache.LastTransparency then
        line.Transparency = transp
        cache.LastTransparency = transp
    end

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
