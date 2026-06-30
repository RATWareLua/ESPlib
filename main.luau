--!nocheck
-- Universal ESP Framework - Core (main.luau)

local ESPLibrary = {
    Objects = {},       
    Modules = {},       
    ModuleOrder = {},   
    Connections = {},   
    
    RepoURL = "https://raw.githubusercontent.com/RATWareLua/ESPlib/refs/heads/main/modules/",
    
    DefaultSettings = {
        Enabled = true,
        MaxDistance = 10000,
        MinBoxSize = 4,
        
        DynamicSize = 0,       -- 0 = Статический 2D бокс, 1 = 3D AABB
        UsePrimaryPart = false,-- Использовать PrimaryPart/HRP вместо общего BBox модели
        SizeOverride = nil,    -- Переопределение размера (Vector3)
        CFrameOffset = nil,    -- Смещение центра (CFrame)
    }
}

local Workspace = game:GetService("Workspace")
local RS = game:GetService("RunService")
local Camera = Workspace.CurrentCamera

local math_max = math.max
local math_huge = math.huge
local math_abs = math.abs
local V3 = Vector3.new

local function dispatchHide(espObj)
    for _, entry in ipairs(ESPLibrary.ModuleOrder) do
        local module = entry.Module
        if espObj.Settings[module.SettingsKey] and module.Update then
            pcall(module.Update, espObj, { OnScreen = false })
        end
    end
end

function ESPLibrary:Import(moduleName, customUrlOrModule)
    if self.Modules[moduleName] then return self.Modules[moduleName] end

    local moduleTable
    if type(customUrlOrModule) == "table" then
        moduleTable = customUrlOrModule
    else
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

    moduleTable.Priority = moduleTable.Priority or 100
    moduleTable.SettingsKey = moduleTable.SettingsKey or moduleName

    self.Modules[moduleName] = moduleTable
    table.insert(self.ModuleOrder, { Name = moduleName, Module = moduleTable })
    
    table.sort(self.ModuleOrder, function(a, b)
        return a.Module.Priority < b.Module.Priority
    end)

    for _, espObj in pairs(self.Objects) do
        if espObj.Settings[moduleTable.SettingsKey] and not espObj.Drawings[moduleName] then
            if moduleTable.Init then
                local ok, err = pcall(moduleTable.Init, espObj)
                if not ok then
                    warn(string.format("[ESP Core] Ошибка поздней инициализации '%s' на '%s': %s", moduleName, espObj.Instance.Name, tostring(err)))
                end
            end
        end
    end

    return moduleTable
end

local function MergeSettings(default, custom)
    local result = {}
    for k, v in pairs(default) do result[k] = v end
    if custom then for k, v in pairs(custom) do result[k] = v end end
    return result
end

local function GetTargetCFAndSize(instance, settings)
    if settings.UsePrimaryPart and instance:IsA("Model") then
        local primary = instance.PrimaryPart 
            or instance:FindFirstChild("HumanoidRootPart") 
            or instance:FindFirstChildWhichIsA("BasePart")
        if primary then
            return primary.CFrame, primary.Size
        end
    end

    if instance:IsA("Model") then
        local cf, size = instance:GetBoundingBox()
        return cf, size
    elseif instance:IsA("BasePart") then
        return instance.CFrame, instance.Size
    end
    return nil, nil
end

local function ProjectVolume(camera, cf, size, isStatic, minSize)
    local camCF = camera.CFrame
    local x, y, w, h
    local anyVisible = false

    if isStatic then
        -- 2D Проекция по высоте (Биллборд, ориентированный по вектору вверх камеры — предотвращает схлопывание вида сверху)
        local camUp = camCF.UpVector
        local halfHeight = size.Y * 0.5
        local tp = camera:WorldToViewportPoint(cf.Position + camUp * halfHeight)
        local bp = camera:WorldToViewportPoint(cf.Position - camUp * halfHeight)

        if tp.Z > 0 and bp.Z > 0 then
            anyVisible = true
            local rawH = math_abs(tp.Y - bp.Y)
            local rawW = rawH / 1.6
            
            h = math_max(rawH, minSize)
            w = math_max(rawW, minSize)
            
            local cx = (tp.X + bp.X) * 0.5
            local cy = (tp.Y + bp.Y) * 0.5
            x = cx - w * 0.5
            y = cy - h * 0.5
        end
    else
        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        local verts = {
            V3( hx,  hy,  hz), V3( hx,  hy, -hz),
            V3( hx, -hy,  hz), V3( hx, -hy, -hz),
            V3(-hx,  hy,  hz), V3(-hx,  hy, -hz),
            V3(-hx, -hy,  hz), V3(-hx, -hy, -hz),
        }

        local minX, minY = math_huge, math_huge
        local maxX, maxY = -math_huge, -math_huge
        local p

        for i = 1, 8 do
            p = camera:WorldToViewportPoint(cf * verts[i])
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
            
            w = math_max(rawW, minSize)
            h = math_max(rawH, minSize)
            x = cx - w * 0.5
            y = cy - h * 0.5
        end
    end

    if anyVisible and x then
        return true, x, y, w, h
    end
    return false
end

function ESPLibrary:Add(instance, customSettings)
    if not instance then return end
    if self.Objects[instance] then return self.Objects[instance] end 
    
    local settings = MergeSettings(self.DefaultSettings, customSettings)
    
    local espObject = {
        Instance = instance,
        Settings = settings,
        Drawings = {},         
        CustomData = {}
    }
    
    for _, entry in ipairs(self.ModuleOrder) do
        local modName = entry.Name
        local module = entry.Module
        if settings[module.SettingsKey] and module.Init then
            local ok, err = pcall(module.Init, espObject)
            if not ok then
                warn(string.format("[ESP Core] Инициализация модуля '%s' упала на '%s': %s", modName, instance.Name, tostring(err)))
            end
        end
    end
    
    function espObject:UpdateSettings(newSettings)
        for k, v in pairs(newSettings) do self.Settings[k] = v end
    end
    
    function espObject:Remove()
        for _, entry in ipairs(ESPLibrary.ModuleOrder) do
            local module = entry.Module
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

function ESPLibrary:Start()
    if self.Connections.Render then
        self.Connections.Render:Disconnect()
        self.Connections.Render = nil
    end

    self.Connections.Render = RS.RenderStepped:Connect(function()
        if not Camera then Camera = Workspace.CurrentCamera return end
        local camPos = Camera.CFrame.Position

        for instance, espObj in pairs(self.Objects) do
            local settings = espObj.Settings

            if not instance or not instance.Parent or not settings.Enabled then
                dispatchHide(espObj)
                continue
            end

            local cf, size = GetTargetCFAndSize(instance, settings)
            if not cf then continue end

            if settings.CFrameOffset then cf = cf * settings.CFrameOffset end
            if settings.SizeOverride then size = settings.SizeOverride end

            local distance = (cf.Position - camPos).Magnitude
            if distance > settings.MaxDistance then
                dispatchHide(espObj)
                continue
            end

            local isStatic = (settings.DynamicSize == 0)
            local success, x, y, w, h = ProjectVolume(Camera, cf, size, isStatic, settings.MinBoxSize)

            if success then
                local renderData = {
                    OnScreen = true,
                    Distance = distance,
                    X = x,
                    Y = y,
                    W = w,
                    H = h
                }

                for _, entry in ipairs(self.ModuleOrder) do
                    local modName = entry.Name
                    local module = entry.Module
                    if settings[module.SettingsKey] and module.Update then
                        local ok, err = pcall(module.Update, espObj, renderData)
                        if not ok then warn(string.format("[ESP Module Error] %s: %s", modName, tostring(err))) end
                    end
                end
            else
                dispatchHide(espObj)
            end
        end
    end)
end

function ESPLibrary:Destroy()
    if self.Connections.Render then
        self.Connections.Render:Disconnect()
        self.Connections.Render = nil
    end
    for _, conn in ipairs(self.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    self.Connections = {}
    for instance, _ in pairs(self.Objects) do
        self:Remove(instance)
    end
    self.Objects = {}
    self.Modules = {}
    self.ModuleOrder = {}
end

ESPLibrary:Start()

return ESPLibrary
