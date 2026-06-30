--!nocheck
-- Module: Arrows.luau
-- Off-screen triangle indicator based on arws.luau, adapted to ESPlib module API.

local Arrows = {
    Priority = 30,
    SettingsKey = "Arrows"
}

local DRAWING = Drawing.new
local V2 = Vector2.new

local cloneref = cloneref or function(o) return o end
local Workspace = cloneref(game:GetService("Workspace"))

local Camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)

local function hide(triangle, cache)
    if cache.Shown then
        triangle.Visible = false
        cache.Shown = false
    end
end

local function screenDirection(targetPos)
    local projected = Camera:WorldToViewportPoint(targetPos)
    local center = Camera.ViewportSize * 0.5
    local dir = V2(projected.X - center.X, projected.Y - center.Y)

    -- Behind-camera projection is mirrored by perspective math; flip it back.
    if projected.Z < 0 then
        dir = -dir
    end

    if dir.Magnitude <= 0.01 then
        return projected.Z < 0 and V2(0, 1) or nil
    end

    return dir.Unit
end

local function rotatedBase(direction, base, sideLength)
    local rot90 = V2(-direction.Y, direction.X)
    return base + rot90 * sideLength, base - rot90 * sideLength
end

function Arrows.Init(espObj)
    local set = espObj.Settings
    local color = set.ArrowColor or set.BoxColor or DEFAULT_COLOR
    local thickness = set.ArrowThickness or 1
    local transparency = set.ArrowTransparency or 1
    local filled = set.ArrowFilled
    if filled == nil then filled = true end

    local triangle = DRAWING("Triangle")
    triangle.Visible = false
    triangle.Color = color
    triangle.Filled = filled
    triangle.Thickness = thickness
    triangle.Transparency = transparency

    espObj.Drawings.Arrows = triangle
    espObj.CustomData.Arrows = {
        Shown = false,
        LastColor = color,
        LastThickness = thickness,
        LastTransparency = transparency,
        LastFilled = filled,
    }
end

function Arrows.Update(espObj, renderData)
    local triangle = espObj.Drawings.Arrows
    if not triangle then return end

    local cache = espObj.CustomData.Arrows
    local cf = renderData.WorldCF

    if not cf or not Camera then
        hide(triangle, cache)
        return
    end

    local _, visible = Camera:WorldToViewportPoint(cf.Position)
    if visible then
        hide(triangle, cache)
        return
    end

    local direction = screenDirection(cf.Position)
    if not direction then
        hide(triangle, cache)
        return
    end

    local set = espObj.Settings
    local dist = set.ArrowDistanceFromCenter or set.ArrowDistFromCenter or 325
    local height = set.ArrowHeight or 16
    local width = set.ArrowWidth or 16

    local center = Camera.ViewportSize * 0.5
    local base = direction * dist
    local baseL, baseR = rotatedBase(direction, base, width * 0.5)
    local tip = direction * (dist + height)

    triangle.PointA = center + baseL
    triangle.PointB = center + baseR
    triangle.PointC = center + tip

    local color = set.ArrowColor or set.BoxColor or DEFAULT_COLOR
    local thickness = set.ArrowThickness or 1
    local transparency = set.ArrowTransparency or 1
    local filled = set.ArrowFilled
    if filled == nil then filled = true end

    if color ~= cache.LastColor then
        triangle.Color = color
        cache.LastColor = color
    end
    if thickness ~= cache.LastThickness then
        triangle.Thickness = thickness
        cache.LastThickness = thickness
    end
    if transparency ~= cache.LastTransparency then
        triangle.Transparency = transparency
        cache.LastTransparency = transparency
    end
    if filled ~= cache.LastFilled then
        triangle.Filled = filled
        cache.LastFilled = filled
    end

    if not cache.Shown then
        triangle.Visible = true
        cache.Shown = true
    end
end

function Arrows.Destroy(espObj)
    local triangle = espObj.Drawings.Arrows
    if triangle then
        triangle:Remove()
        espObj.Drawings.Arrows = nil
        espObj.CustomData.Arrows = nil
    end
end

return Arrows
