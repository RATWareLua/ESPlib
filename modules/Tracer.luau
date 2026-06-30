--!nocheck
-- Module: Tracer.luau
-- Линия от выбранной screen-origin точки напрямую к спроецированной точке цели.
-- Endpoint НЕ прижимается к краю экрана: Drawing нормально принимает off-screen координаты.

local Tracer = {
    Priority = 20,
    SettingsKey = "Tracer"
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local V3 = Vector3.new

local cloneref = cloneref or function(o) return o end
local Workspace = cloneref(game:GetService("Workspace"))
local UserInputService = cloneref(game:GetService("UserInputService"))

local Camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

local DEFAULT_COLOR = Color3.fromRGB(255, 50, 50)

local function originPoint(vp, mode)
    if mode == "mouse" then
        local m = UserInputService:GetMouseLocation()
        return m.X, m.Y
    elseif mode == "top" then
        return vp.X * 0.5, 0
    elseif mode == "center" then
        return vp.X * 0.5, vp.Y * 0.5
    else
        return vp.X * 0.5, vp.Y
    end
end

local function hideLine(line, cache)
    if cache.Shown then
        line.Visible = false
        cache.Shown = false
    end
end

local function projectedPoint(worldPos)
    local projected = Camera:WorldToViewportPoint(worldPos)
    local x, y = projected.X, projected.Y

    -- Behind-camera projection is mirrored around screen center; mirror it back.
    if projected.Z < 0 then
        local vp = Camera.ViewportSize
        x = vp.X - x
        y = vp.Y - y
    end

    return x, y
end

function Tracer.Init(espObj)
    local s = espObj.Settings
    local thickness = s.TracerThickness or 1.5
    local transp = s.TracerTransparency or 1
    local color = s.TracerColor or s.BoxColor or DEFAULT_COLOR

    local line = DRAWING("Line")
    line.Visible = false
    line.Thickness = thickness
    line.Transparency = transp
    line.Color = color

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
    if not cf or not Camera then
        hideLine(line, cache)
        return
    end

    local set = espObj.Settings
    local vp = Camera.ViewportSize
    local ox, oy = originPoint(vp, set.TracerOrigin)

    local footOffset = set.TracerFootOffset
    if footOffset == nil then footOffset = 3 end
    local tx, ty = projectedPoint(cf.Position - V3(0, footOffset, 0))

    line.From = V2(ox, oy)
    line.To = V2(tx, ty)

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
