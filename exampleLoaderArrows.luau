--!nocheck
-- Loader: 2D corner box + off-screen arrows test

local storage = (getgenv and getgenv()) or shared
for _, key in ipairs({ "ESP_Cleanup", "CornerESP_Cleanup" }) do
    if storage[key] then
        pcall(storage[key])
        storage[key] = nil
    end
end

local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/RATWareLua/ESPlib/refs/heads/main/main.luau"))()

ESP:Import("CornerBox")
ESP:Import("Arrows")

local BASE_ESP_SETTINGS = {
    CornerBox = true,
    Arrows = true,

    DynamicSize = 0,
    UsePrimaryPart = true,
    SizeOverride = Vector3.new(4, 6.9, 4),
    MinBoxSize = 4,
    MaxDistance = 10000,

    BoxColor = Color3.fromRGB(0, 255, 120),
    BoxThickness = 2.5,
    BoxTransparency = 1,
    CornerScale = 0.25,
    Outline = true,
    OutlineThickness = 2,

    ArrowColor = Color3.fromRGB(255, 255, 255),
    ArrowDistanceFromCenter = 325,
    ArrowHeight = 16,
    ArrowWidth = 16,
    ArrowFilled = true,
    ArrowTransparency = 1,
    ArrowThickness = 1,
}

local CONFIG = {
    UseTeamColor = true,
    TeamCheck = true,
    HideAllies = false,
    AllyColor = Color3.fromRGB(0, 170, 255),
    EnemyColor = Color3.fromRGB(255, 60, 60),
}

local function copyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == "table" and copyTable(v) or v
    end
    return copy
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local PlayerTracking = {}
local globalConnections = {}

local function isAlly(plr)
    return plr.Team ~= nil and plr.Team == LocalPlayer.Team
end

local function resolveColor(plr)
    if CONFIG.UseTeamColor and plr.Team then
        return plr.TeamColor.Color
    end
    if CONFIG.TeamCheck then
        return isAlly(plr) and CONFIG.AllyColor or CONFIG.EnemyColor
    end
    return BASE_ESP_SETTINGS.BoxColor
end

local function applyTeamState(track, plr)
    if not track.ActiveESP then return end

    local hideAlly = CONFIG.TeamCheck and CONFIG.HideAllies and isAlly(plr)
    local color = resolveColor(plr)
    track.ActiveESP:UpdateSettings({
        Enabled = not hideAlly,
        BoxColor = color,
        ArrowColor = color,
    })
end

local function removePlayer(plr)
    local track = PlayerTracking[plr]
    if not track then return end

    if track.CharConn then pcall(function() track.CharConn:Disconnect() end) end
    if track.TeamConn then pcall(function() track.TeamConn:Disconnect() end) end
    if track.ActiveESP then pcall(function() track.ActiveESP:Remove() end) end
    PlayerTracking[plr] = nil
end

local function addPlayer(plr)
    if plr == LocalPlayer or PlayerTracking[plr] then return end

    local track = {
        CharConn = nil,
        TeamConn = nil,
        ActiveESP = nil,
    }
    PlayerTracking[plr] = track

    local function handleCharacter(char)
        if track.ActiveESP then
            pcall(function() track.ActiveESP:Remove() end)
            track.ActiveESP = nil
        end

        track.ActiveESP = ESP:Add(char, copyTable(BASE_ESP_SETTINGS))
        applyTeamState(track, plr)
    end

    track.CharConn = plr.CharacterAdded:Connect(function(char)
        task.spawn(handleCharacter, char)
    end)
    track.TeamConn = plr:GetPropertyChangedSignal("Team"):Connect(function()
        applyTeamState(track, plr)
    end)

    if plr.Character then
        task.spawn(handleCharacter, plr.Character)
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    local ok, err = pcall(addPlayer, plr)
    if not ok then
        warn(string.format("[ESP Arrows Loader] Ошибка инициализации игрока '%s': %s", plr.Name, tostring(err)))
    end
end

globalConnections[#globalConnections + 1] = Players.PlayerAdded:Connect(function(plr)
    local ok, err = pcall(addPlayer, plr)
    if not ok then
        warn(string.format("[ESP Arrows Loader] Ошибка подключения игрока '%s': %s", plr.Name, tostring(err)))
    end
end)

globalConnections[#globalConnections + 1] = Players.PlayerRemoving:Connect(function(plr)
    pcall(removePlayer, plr)
end)

storage.ESP_Cleanup = function()
    for _, conn in ipairs(globalConnections) do
        pcall(function() conn:Disconnect() end)
    end
    for plr in pairs(PlayerTracking) do
        pcall(removePlayer, plr)
    end
    if ESP and ESP.Destroy then
        pcall(function() ESP:Destroy() end)
    end
end
