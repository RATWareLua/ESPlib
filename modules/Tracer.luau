--!nocheck
-- Module: Tracer.luau
-- Линия от курсора/центра к цели. На экране — к низу бокса; вне экрана/за спиной —
-- к точке у края экрана в направлении цели (метод arws через XZ-фрейм).
-- Опирается на renderData.WorldCF.

local Tracer = {
    Priority = 20,            -- рисуется после бокса
    SettingsKey = "Tracer"    -- ключ в settings, которым модуль включают
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local V3 = Vector3.new
local CF = CFrame.new
local math_min = math.min
local math_huge = math.huge

local cloneref = cloneref or function(o) return o end
local Workspace = cloneref(game:GetService("Workspace"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Players = cloneref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer

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

-- Точка-цель для off-screen/за-спиной случая. Это старая arws-модель: направление
-- считается в горизонтальном XZ-фрейме, поэтому pitch камеры не ломает привычный радар.
local function offscreenPoint(targetPos, originMode)
    local char = LocalPlayer.Character
    local root = char and char.PrimaryPart
    if not root then return nil end

    local vp = Camera.ViewportSize
    local cx, cy = vp.X * 0.5, vp.Y * 0.5

    local rootP = root.Position
    local camP = Camera.CFrame.Position
    local rel = CF(V3(rootP.X, camP.Y, rootP.Z), camP):PointToObjectSpace(targetPos)
    local flat = V2(rel.X, rel.Z)
    if flat.Magnitude < 0.01 then return nil end

    local dir = -flat.Unit

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
        if cache.Shown then
            line.Visible = false
            cache.Shown = false
        end
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
        tx, ty = offscreenPoint(cf.Position, set.TracerOrigin)
        if not tx then
            if cache.Shown then
                line.Visible = false
                cache.Shown = false
            end
            return
        end

        -- Narrow fix for the original bug only: bottom-origin tracer to a target
        -- almost exactly behind the camera should not draw a full-screen vertical line.
        local projected = Camera:WorldToViewportPoint(cf.Position)
        local mode = set.TracerOrigin or "bottom"
        if mode == "bottom" and projected.Z < 0 then
            local cx = vp.X * 0.5
            if tx > cx - 2 and tx < cx + 2 and ty < vp.Y * 0.5 then
                if cache.Shown then
                    line.Visible = false
                    cache.Shown = false
                end
                return
            end
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
