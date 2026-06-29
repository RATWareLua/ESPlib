--!nocheck
-- Universal ESP Framework - Core (main.luau)
-- Архитектура: Ядро считает математику (3D -> 2D) и управляет объектами. Модули занимаются отрисовкой.

local ESPLibrary = {
    Objects = {},
    Modules = {},
    Connections = {},
    
    RepoURL = "https://ссылка raw-гитхаб на модули.com",
    
    DefaultSettings = {
        Enabled = true,
        MaxDistance = 10000,
        MinBoxSize = 4,
        BBoxRefreshRate = 3,
        
    }
}

local Workspace = game:GetService("Workspace")
local RS = game:GetService("RunService")
local Camera = Workspace.CurrentCamera

-- Оптимизация математики
local math_min = math.min
local math_max = math.max
local math_huge = math.huge
local V3 = Vector3.new

----------------------------------------------------------------------
-- [ 1. СИСТЕМА МОДУЛЕЙ ]
----------------------------------------------------------------------

-- Загрузка модуля по URL или регистрация уже готовой таблицы
function ESPLibrary:Import(moduleName, customUrlOrModule)
    -- Если модуль уже загружен, не грузим дважды
    if self.Modules[moduleName] then return self.Modules[moduleName] end

    local moduleTable
    
    if type(customUrlOrModule) == "table" then
        moduleTable = customUrlOrModule
    else
        -- Скачиваем через HttpGet
        local url = type(customUrlOrModule) == "string" and customUrlOrModule or (self.RepoURL .. moduleName .. ".luau")
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        
        if ok and type(result) == "table" then
            moduleTable = result
        else
            warn(string.format("[ESP Core] Ошибка загрузки модуля '%s': %s", tostring(moduleName), tostring(result)))
            return nil
        end
    end

    self.Modules[moduleName] = moduleTable
    return moduleTable
end

----------------------------------------------------------------------
-- [ 2. УТИЛИТЫ И МАТЕМАТИКА ]
----------------------------------------------------------------------

local function MergeSettings(default, custom)
    local result = {}
    for k, v in pairs(default) do result[k] = v end
    if custom then for k, v in pairs(custom) do result[k] = v end end
    return result
end

-- Пересчет вершин BoundingBox (для моделей и партов)
local function RefreshBBox(espObj)
    local instance = espObj.Instance
    if not instance or not instance.Parent then return end

    if instance:IsA("Model") then
        local ok, cf, size = pcall(function() return instance:GetBoundingBox() end)
        if ok and cf and size then
            local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
            if primary then
                local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
                espObj.PrimaryPart = primary
                espObj.BoxOffset = primary.CFrame:ToObjectSpace(cf)
                espObj.LocalVertices = {
                    V3( hx,  hy,  hz), V3( hx,  hy, -hz),
                    V3( hx, -hy,  hz), V3( hx, -hy, -hz),
                    V3(-hx,  hy,  hz), V3(-hx,  hy, -hz),
                    V3(-hx, -hy,  hz), V3(-hx, -hy, -hz),
                }
                espObj.LastBBoxRefresh = tick()
            end
        end
    elseif instance:IsA("BasePart") then
        local size = instance.Size
        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        espObj.PrimaryPart = instance
        espObj.BoxOffset = CFrame.new()
        espObj.LocalVertices = {
            V3( hx,  hy,  hz), V3( hx,  hy, -hz),
            V3( hx, -hy,  hz), V3( hx, -hy, -hz),
            V3(-hx,  hy,  hz), V3(-hx,  hy, -hz),
            V3(-hx, -hy,  hz), V3(-hx, -hy, -hz),
        }
        espObj.LastBBoxRefresh = tick() + 999999 -- Парты обычно не меняют размер динамически
    end
end

----------------------------------------------------------------------
-- [ 3. УПРАВЛЕНИЕ ОБЪЕКТАМИ ]
----------------------------------------------------------------------

function ESPLibrary:Add(instance, customSettings)
    if not instance then return end
    if self.Objects[instance] then return self.Objects[instance] end 
    
    local settings = MergeSettings(self.DefaultSettings, customSettings)
    
    local espObject = {
        Instance = instance,
        PrimaryPart = nil,
        Settings = settings,
        Drawings = {},
        CustomData = {},
        LocalVertices = nil,
        BoxOffset = CFrame.new(),
        LastBBoxRefresh = 0
    }
    
    RefreshBBox(espObject)
    
    for modName, module in pairs(self.Modules) do
        if settings[modName] and module.Init then
            pcall(module.Init, espObject)
        end
    end
    
    function espObject:UpdateSettings(newSettings)
        for k, v in pairs(newSettings) do self.Settings[k] = v end
    end
    
    function espObject:Remove()
        for modName, module in pairs(ESPLibrary.Modules) do
            if module.Destroy then
                pcall(module.Destroy, self)
            end
        end
        ESPLibrary.Objects[self.Instance] = nil
    end

    self.Objects[instance] = espObject
    return espObject
end

function ESPLibrary:Remove(instance)
    if self.Objects[instance] then
        self.Objects[instance]:Remove()
    end
end

----------------------------------------------------------------------
-- [ 4. ГЛАВНЫЙ ЦИКЛ РЕНДЕРА ]
----------------------------------------------------------------------

local renderConnection = RS.RenderStepped:Connect(function()
    if not Camera then Camera = Workspace.CurrentCamera return end
    
    local camCF = Camera.CFrame
    local camPos = camCF.Position

    for instance, espObj in pairs(ESPLibrary.Objects) do
        local settings = espObj.Settings
        local primary = espObj.PrimaryPart

        if not instance or not instance.Parent or not primary or not primary.Parent or not settings.Enabled then
            for modName, module in pairs(ESPLibrary.Modules) do
                if settings[modName] and module.Update then
                    module.Update(espObj, { OnScreen = false })
                end
            end
            continue
        end

        local distance = (primary.Position - camPos).Magnitude
        if distance > settings.MaxDistance then
            for modName, module in pairs(ESPLibrary.Modules) do
                if settings[modName] and module.Update then
                    module.Update(espObj, { OnScreen = false })
                end
            end
            continue
        end

        if tick() - espObj.LastBBoxRefresh > settings.BBoxRefreshRate then
            RefreshBBox(espObj)
        end

        local verts = espObj.LocalVertices
        if not verts then continue end

        local baseCF = espObj.BoxOffset and (primary.CFrame * espObj.BoxOffset) or primary.CFrame
        local minX, minY = math_huge, math_huge
        local maxX, maxY = -math_huge, -math_huge
        local anyVisible = false
        local p

        for i = 1, 8 do
            p = Camera:WorldToViewportPoint(baseCF * verts[i])
            if p.Z > 0 then 
                anyVisible = true
                if p.X < minX then minX = p.X end 
                if p.X > maxX then maxX = p.X end
                if p.Y < minY then minY = p.Y end 
                if p.Y > maxY then maxY = p.Y end
            end
        end

        if anyVisible then
            local rawW = maxX - minX
            local rawH = maxY - minY
            local cx = minX + rawW * 0.5
            local cy = minY + rawH * 0.5
            
            local w = math_max(rawW, settings.MinBoxSize)
            local h = math_max(rawH, settings.MinBoxSize)
            local x = cx - w * 0.5
            local y = cy - h * 0.5
            
            local renderData = {
                OnScreen = true,
                Distance = distance,
                X = x,
                Y = y,
                W = w,
                H = h,
                CX = cx,
                CY = cy
            }

            for modName, module in pairs(ESPLibrary.Modules) do
                if settings[modName] and module.Update then
                    local ok, err = pcall(module.Update, espObj, renderData)
                    if not ok then warn(string.format("[ESP Module Error] %s: %s", modName, tostring(err))) end
                end
            end
        else
            for modName, module in pairs(ESPLibrary.Modules) do
                if settings[modName] and module.Update then
                    module.Update(espObj, { OnScreen = false })
                end
            end
        end
    end
end)
table.insert(ESPLibrary.Connections, renderConnection)

----------------------------------------------------------------------
-- [ 5. ОЧИСТКА БИБЛИОТЕКИ ]
----------------------------------------------------------------------
function ESPLibrary:Destroy()
    for _, conn in ipairs(self.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    for instance, _ in pairs(self.Objects) do
        self:Remove(instance)
    end
    self.Objects = {}
    self.Modules = {}
end

-- Возвращаем ядро
return ESPLibrary
