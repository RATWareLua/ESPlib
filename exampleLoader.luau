--!nocheck
-- Loader: трекинг игроков, индивидуальные настройки ESP, очистка

local storage = (getgenv and getgenv()) or shared
-- Снимаем любой ранее запущенный инстанс. Чистим и легаси-ключ: при переименовании
-- ключа старый инстанс иначе остаётся жить со своими Drawing'ами и render-циклом
-- (это и давало «двойные» трассеры до перезахода в плейс).
for _, key in ipairs({ "ESP_Cleanup", "CornerESP_Cleanup" }) do
    if storage[key] then
        pcall(storage[key])
        storage[key] = nil
    end
end

-- 1. Загрузка ядра
local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/RATWareLua/ESPlib/refs/heads/main/main.luau"))()

-- 2. Загрузка модулей
ESP:Import("CornerBox")
ESP:Import("Tracer")

-- Базовый шаблон настроек (копируется на каждого игрока)
local BASE_ESP_SETTINGS = {
    CornerBox       = true,                    -- включить модуль CornerBox
    DynamicSize     = 0,                       -- 0 = статичный бокс фикс. размера
    SizeOverride    = Vector3.new(4, 6.9, 4),  -- габариты бокса; убрать -> бокс по телу
    BoxColor        = Color3.fromRGB(0, 255, 120),
    BoxThickness    = 2.5,
    BoxTransparency = 1,
    CornerScale     = 0.25,                    -- длина уголка как доля ширины
    TracerThickness = 1.5,                     -- толщина трассера
    TracerOrigin    = "mouse",                 -- от курсора ("bottom"/"top"/"center"/"mouse")
    Outline         = true,                    -- контур контрастного цвета под линиями
    OutlineThickness = 2,                      -- доп. толщина контура (px)
    MinBoxSize      = 4,
    MaxDistance     = 10000,
    -- TracerColor / OutlineColor не задаём -> берутся из BoxColor / его инверсии
}

-- Поведение тимчека и цвета (A: различение команд, B: подсветка цветом команды)
local CONFIG = {
    UseTeamColor = true,                        -- B: красить бокс в реальный цвет команды
    TeamCheck    = true,                        -- A: различать своих и чужих
    HideAllies   = false,                       -- true -> не рисовать союзников; трассер только врагам
    Tracer       = true,                        -- мастер-вкл трассера
    AllyColor    = Color3.fromRGB(0, 170, 255), -- цвет своих  (когда UseTeamColor = false)
    EnemyColor   = Color3.fromRGB(255, 60, 60), -- цвет врагов (когда UseTeamColor = false)
}

-- Глубокая копия настроек — у каждого игрока свой независимый набор
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

-- ── Тимчек и цвет команды ───────────────────────────────────────────────
-- Свой, если у нас и у цели одна и та же Team. Если у кого-то Team нет
-- (free-for-all / игра без Team-объектов) — считаем врагом.
local function isAlly(plr)
    return plr.Team ~= nil and plr.Team == LocalPlayer.Team
end

-- Цвет бокса для игрока:
--   UseTeamColor -> реальный цвет его команды (plr.TeamColor)
--   иначе TeamCheck -> свой/враг по фикс. цветам из CONFIG
--   иначе -> базовый BoxColor
local function resolveBoxColor(plr)
    if CONFIG.UseTeamColor and plr.Team then
        return plr.TeamColor.Color
    end
    if CONFIG.TeamCheck then
        return isAlly(plr) and CONFIG.AllyColor or CONFIG.EnemyColor
    end
    return BASE_ESP_SETTINGS.BoxColor
end

-- Применяет цвет и видимость к активному ESP игрока. Зовётся при спавне и при
-- смене команды: новый цвет линий подхватит CornerBox своим dirty-check, а
-- Enabled управляет показом союзников.
local function applyTeamState(track, plr)
    if not track.ActiveESP then return end
    local hideAlly = CONFIG.TeamCheck and CONFIG.HideAllies and isAlly(plr)
    track.ActiveESP:UpdateSettings({
        Enabled  = not hideAlly,
        BoxColor = resolveBoxColor(plr),
        -- Трассер «не на скрытых»: при HideAllies = true это только враги
        Tracer   = CONFIG.Tracer and not hideAlly,
    })
end

local function RemovePlayer(plr)
    local track = PlayerTracking[plr]
    if track then
        if track.CharConn then pcall(function() track.CharConn:Disconnect() end) end
        if track.TeamConn then pcall(function() track.TeamConn:Disconnect() end) end
        if track.ActiveESP then pcall(function() track.ActiveESP:Remove() end) end
        PlayerTracking[plr] = nil
    end
end

local function AddPlayer(plr)
    if plr == LocalPlayer then return end
    if PlayerTracking[plr] then return end

    local track = {
        CharConn = nil,
        TeamConn = nil,
        ActiveESP = nil
    }
    PlayerTracking[plr] = track

    local function handleCharacter(char)
        if track.ActiveESP then
            pcall(function() track.ActiveESP:Remove() end)
            track.ActiveESP = nil
        end

        -- Индивидуальная копия настроек для каждого игрока
        local playerSettings = copyTable(BASE_ESP_SETTINGS)
        track.ActiveESP = ESP:Add(char, playerSettings)

        -- A + B: тимчек + цвет команды (далее обновляется по сигналу смены Team)
        applyTeamState(track, plr)
    end

    track.CharConn = plr.CharacterAdded:Connect(function(char)
        task.spawn(handleCharacter, char)
    end)

    -- Перекрашиваем / перепроверяем команду на лету при её смене
    track.TeamConn = plr:GetPropertyChangedSignal("Team"):Connect(function()
        applyTeamState(track, plr)
    end)

    if plr.Character then
        task.spawn(handleCharacter, plr.Character)
    end
end

-- Инициализация уже подключённых игроков (с логом ошибок вместо слепого pcall)
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

storage.ESP_Cleanup = cleanup
