--!nocheck
-- Loader Script with Fixed Per-Player Copying and Logging

local storage = (getgenv and getgenv()) or shared
if storage.CornerESP_Cleanup then
    pcall(storage.CornerESP_Cleanup)
end

-- 1. Загрузка математически чистого ядра
local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/RATWareLua/ESPlib/refs/heads/main/main.luau"))()

-- 2. Загрузка модуля
ESP:Import("CornerBox")

-- Базовый неизменяемый шаблон настроек
local BASE_ESP_SETTINGS = {
    CornerBox       = true,
    DynamicSize     = 0,                             
    UsePrimaryPart  = true,                          
    SizeOverride    = Vector3.new(4, 6.9, 4),        
    CFrameOffset    = CFrame.new(0, -0.15, 0),       
    BoxColor        = Color3.fromRGB(0, 255, 120),   
    BoxThickness    = 2.5,                           
    BoxTransparency = 1,                             
    CornerScale     = 0.25,                          
    MinBoxSize      = 4,                             
    MaxDistance     = 10000,                         
}

-- Глубокое копирование таблиц для решения Проблемы 10
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

local function RemovePlayer(plr)
    local track = PlayerTracking[plr]
    if track then
        if track.CharConn then pcall(function() track.CharConn:Disconnect() end) end
        if track.ActiveESP then pcall(function() track.ActiveESP:Remove() end) end
        PlayerTracking[plr] = nil
    end
end

local function AddPlayer(plr)
    if plr == LocalPlayer then return end
    if PlayerTracking[plr] then return end

    local track = {
        CharConn = nil,
        ActiveESP = nil
    }
    PlayerTracking[plr] = track

    local function handleCharacter(char)
        if track.ActiveESP then
            pcall(function() track.ActiveESP:Remove() end)
            track.ActiveESP = nil
        end

        -- Решение Проблемы 10: Индивидуальная копия настроек для каждого игрока
        local playerSettings = copyTable(BASE_ESP_SETTINGS)
        
        -- Пример гибкой кастомизации под союзников/врагов:
        if plr.TeamColor == LocalPlayer.TeamColor then
            playerSettings.BoxColor = Color3.fromRGB(0, 150, 255)  -- Союзники синие
        else
            playerSettings.BoxColor = Color3.fromRGB(255, 50, 50)   -- Враги красные
        end

        track.ActiveESP = ESP:Add(char, playerSettings)
    end

    track.CharConn = plr.CharacterAdded:Connect(function(char)
        task.spawn(handleCharacter, char)
    end)

    if plr.Character then
        task.spawn(handleCharacter, plr.Character)
    end
end

-- Решение Проблемы 11: Логирование с варнингом вместо слепого pcall
for _, plr in ipairs(Players:GetPlayers()) do
    local ok, err = pcall(AddPlayer, plr)
    if not ok then
        warn(string.format("[ESP Loader] Ошибка инициализации игрока '%s': %s", plr.Name, tostring(err)))
    end
end

local playerAddedConn = Players.PlayerAdded:Connect(function(plr)
    local ok, err = pcall(AddPlayer, plr)
    if not ok then
        warn(string.format("[ESP Loader] Ошибка подключения нового игрока '%s': %s", plr.Name, tostring(err)))
    end
end)
table.insert(globalConnections, playerAddedConn)

local playerRemovingConn = Players.PlayerRemoving:Connect(function(plr)
    pcall(RemovePlayer, plr)
end)
table.insert(globalConnections, playerRemovingConn)

local function cleanup()
    for _, conn in ipairs(globalConnections) do
        pcall(function() conn:Disconnect() end)
    end
    for plr in pairs(PlayerTracking) do
        pcall(RemovePlayer, plr)
    end
    if ESP and ESP.Destroy then
        pcall(function() ESP:Destroy() end)
    end
end

storage.CornerESP_Cleanup = cleanup
