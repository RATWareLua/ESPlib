--!nocheck
-- Module: Tracer.luau
-- Линия от курсора/центра к цели. Когда цель на экране — к низу бокса; когда
-- вне экрана/за спиной — к точке у края экрана в направлении цели (метод arws,
-- через горизонтальный XZ-фрейм, т.к. WorldToViewportPoint за камерой даёт мусор).
-- Опирается на renderData.WorldCF (ядро отдаёт его и для off-screen целей).

local Tracer = {
    Priority = 20,            -- рисуется после бокса
    SettingsKey = "Tracer"    -- ключ в settings, которым модуль включают
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local V3 = Vector3.new
local CF = CFrame.new

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

-- Точка-цель для off-screen/за-спиной случая: направление считается в горизонтальном
-- XZ-фрейме у игрока, смотрящем на камеру (как в arws) — корректно на все 360°.
-- Возвращает точку на круге радиусом radius от центра экрана, или nil.
local function offscreenPoint(targetPos, radius)
    local char = LocalPlayer.Character
    local root = char and char.PrimaryPart
    if not root then return nil end

    local rootP = root.Position
    local camP = Camera.CFrame.Position
    local rel = CF(V3(rootP.X, camP.Y, rootP.Z), camP):PointToObjectSpace(targetPos)
    local flat = V2(rel.X, rel.Z)
    if flat.Magnitude < 0.01 then return nil end

    local dir = flat.Unit
    local center = Camera.ViewportSize * 0.5
    local p = center - dir * radius
    return p.X, p.Y
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

    -- Точка цели: на экране — низ бокса; вне экрана/за спиной — индикатор у края
    local tx, ty
    if renderData.OnScreen then
        tx = renderData.X + renderData.W * 0.5
        ty = renderData.Y + renderData.H
    else
        tx, ty = offscreenPoint(cf.Position, set.TracerEdgeRadius or 300)
        if not tx then
            if cache.Shown then
                line.Visible = false
                cache.Shown = false
            end
            return
        end
    end

    local ox, oy = originPoint(Camera.ViewportSize, set.TracerOrigin)
    line.From = V2(ox, oy)
    line.To = V2(tx, ty)

    -- Свойства — через dirty-check
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
