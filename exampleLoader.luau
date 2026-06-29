--[[
paste this shit in you exec
]]--


local storage = (getgenv and getgenv()) or shared
if storage.CornerESP_Cleanup then
    pcall(storage.CornerESP_Cleanup)
end

local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/RATWareLua/ESPlib/refs/heads/main/main.luau"))()

ESP:Import("CornerBox")

-- Настройки воссоздают твой оригинальный статический 2D бокс через примитивы
local ESP_SETTINGS = {
    CornerBox       = true,
    DynamicSize     = 0,                             -- 0 = статика, 1 = динамика (3D AABB)
    
    -- ПРИМИТИВЫ: Настраиваем математику под Roblox-персонажей:
    UsePrimaryPart  = true,                          -- Привязываемся к HRP, а не габаритам аксессуаров
    SizeOverride    = Vector3.new(4, 6.9, 4),        -- Высота ровно 6.9 студа (3.3 + 3.6)
    CFrameOffset    = CFrame.new(0, -0.15, 0),       -- Смещаем центр на 0.15 студа вниз для компенсации асимметрии
    
    BoxColor        = Color3.fromRGB(0, 255, 120),   
    BoxThickness    = 2.5,                           
    BoxTransparency = 1,                             
    CornerScale     = 0.25,                          
    MinBoxSize      = 4,                             
    MaxDistance     = 10000,                         
}

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
        track.ActiveESP = ESP:Add(char, ESP_SETTINGS)
    end

    track.CharConn = plr.CharacterAdded:Connect(function(char)
        task.spawn(handleCharacter, char)
    end)

    if plr.Character then
        task.spawn(handleCharacter, plr.Character)
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    pcall(AddPlayer, plr)
end

local playerAddedConn = Players.PlayerAdded:Connect(function(plr)
    pcall(AddPlayer, plr)
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
