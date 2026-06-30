--!nocheck
-- Module: Arrows.luau
-- Off-screen triangle indicator based on arws.luau, adapted to ESPlib module API.

local Arrows = {
    Priority = 30,
    SettingsKey = "Arrows"
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local V3 = Vector3.new
local CF = CFrame.new

local cloneref = cloneref or function(o) return o end
local Workspace = cloneref(game:GetService("Workspace"))
local Players = cloneref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer

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

local function relativeToLocalPlayer(targetPos)
    local char = LocalPlayer.Character
    local root = char and char.PrimaryPart
    if not root or not Camera then return nil end

    local rootP = root.Position
    local camP = Camera.CFrame.Position
    local relative = CF(V3(rootP.X, camP.Y, rootP.Z), camP):PointToObjectSpace(targetPos)

    return V2(relative.X, relative.Z)
end

local function toScreenCenter(v)
    return Camera.ViewportSize * 0.5 - v
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

    if not cf or not Camera or renderData.OnScreen then
        hide(triangle, cache)
        return
    end

    local rel = relativeToLocalPlayer(cf.Position)
    if not rel or rel.Magnitude <= 0.01 then
        hide(triangle, cache)
        return
    end

    local set = espObj.Settings
    local dist = set.ArrowDistanceFromCenter or set.ArrowDistFromCenter or 325
    local height = set.ArrowHeight or 16
    local width = set.ArrowWidth or 16

    local direction = rel.Unit
    local base = direction * dist
    local baseL, baseR = rotatedBase(direction, base, width * 0.5)
    local tip = direction * (dist + height)

    triangle.PointA = toScreenCenter(baseL)
    triangle.PointB = toScreenCenter(baseR)
    triangle.PointC = toScreenCenter(tip)

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
