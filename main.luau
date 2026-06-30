--!nocheck
-- Universal ESP Framework - Core (main.luau)
--
-- Горячий путь — RenderStepped. Оптимизации под высокую нагрузку (десятки целей):
--   * парты тела кэшируются и поддерживаются подписками ChildAdded/ChildRemoved,
--     а не пере-сканируются GetChildren() каждый кадр (ноль аллокаций в кадре);
--   * renderData — один переиспользуемый стол на объект (не аллоцируется в кадре);
--   * активные модули объекта скомпилированы в UpdateList (нет перебора всего
--     ModuleOrder с проверками настроек каждый кадр);
--   * дистанция отсекается по КВАДРАТУ (sqrt только для реально видимых целей);
--   * WorldToViewportPoint вызывается как кэшированная C-функция (мимо namecall);
--   * Update вызывается напрямую (pcall — опционально через SafeUpdate).

-- ── Executor C-функции ──────────────────────────────────────────────────
local cloneref = cloneref or function(o) return o end

-- ── Сервисы ─────────────────────────────────────────────────────────────
local Workspace = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))

-- ── Кэш глобалов (локали резолвятся быстрее полей) ──────────────────────
local Vector3_new = Vector3.new
local CFrame_new = CFrame.new
local math_max = math.max
local math_huge = math.huge
local math_abs = math.abs
local math_sqrt = math.sqrt
local ipairs = ipairs
local pairs = pairs

local ESPLibrary = {
    Objects = {},       -- [instance] -> espObject
    Modules = {},       -- [name] -> module (прямой доступ)
    ModuleOrder = {},   -- {Name, Module}, отсортирован по Priority для детерминированного z-order
    Connections = {},

    -- false = Update вызывается напрямую (максимальная скорость).
    -- true  = Update оборачивается в pcall+warn (отладка падающих модулей).
    SafeUpdate = false,

    RepoURL = "https://raw.githubusercontent.com/RATWareLua/ESPlib/refs/heads/main/modules/",

    DefaultSettings = {
        Enabled = true,
        MaxDistance = 10000,
        MinBoxSize = 4,
        DynamicSize = 0,
        UsePrimaryPart = false,
        SizeOverride = nil,
        CFrameOffset = nil,
    }
}

-- Общий стол «скрыто»: модули на оффскрине только гасят свои Drawing-объекты.
local HIDDEN = { OnScreen = false }

-- Знаки вершин AABB для динамической проекции (строится один раз).
local BOX_SIGNS = {
    {  1,  1,  1 }, {  1,  1, -1 }, {  1, -1,  1 }, {  1, -1, -1 },
    { -1,  1,  1 }, { -1,  1, -1 }, { -1, -1,  1 }, { -1, -1, -1 },
}

-- ════════════════════════════════════════════════════════════════════════
--  Геометрия
-- ════════════════════════════════════════════════════════════════════════

-- World-AABB «скелета» по кэшированным партам тела (без аксессуаров — их Handle
-- не прямой ребёнок модели и в parts не попадает). Возвращает (center, size) или nil.
local function bodyBounds(parts)
    if not parts then return nil end
    local n = #parts
    if n == 0 then return nil end

    local minX, minY, minZ = math_huge, math_huge, math_huge
    local maxX, maxY, maxZ = -math_huge, -math_huge, -math_huge

    for i = 1, n do
        local p = parts[i]
        local pos = p.Position
        local sz = p.Size
        local hx, hy, hz = sz.X * 0.5, sz.Y * 0.5, sz.Z * 0.5
        local px, py, pz = pos.X, pos.Y, pos.Z
        if px - hx < minX then minX = px - hx end
        if px + hx > maxX then maxX = px + hx end
        if py - hy < minY then minY = py - hy end
        if py + hy > maxY then maxY = py + hy end
        if pz - hz < minZ then minZ = pz - hz end
        if pz + hz > maxZ then maxZ = pz + hz end
    end

    return Vector3_new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5),
           Vector3_new(maxX - minX, maxY - minY, maxZ - minZ)
end

local function GetTargetCFAndSize(espObj, settings)
    local inst = espObj.Instance

    if espObj.IsModel then
        if settings.UsePrimaryPart then
            -- HumanoidRootPart как центральный референс (детерминированно, без
            -- недетерминированного FindFirstChildWhichIsA).
            local primary = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart")
            if primary then
                return primary.CFrame, primary.Size
            end
        end

        -- Скелет, а не bounding box: размер не должен зависеть от аксессуаров.
        local center, size = bodyBounds(espObj.BodyParts)
        if center then
            return CFrame_new(center), size
        end
        -- Фолбэк для моделей без партов тела (не-персонажей).
        return inst:GetBoundingBox()
    elseif espObj.IsPart then
        return inst.CFrame, inst.Size
    end

    return nil, nil
end

-- wtvp — кэшированная camera.WorldToViewportPoint (вызов мимо namecall).
local function ProjectVolume(wtvp, camera, camCF, cf, size, isStatic, minSize)
    local x, y, w, h
    local visible = false

    if isStatic then
        local camUp = camCF.UpVector
        local halfHeight = size.Y * 0.5
        local cpos = cf.Position
        local tp = wtvp(camera, cpos + camUp * halfHeight)
        local bp = wtvp(camera, cpos - camUp * halfHeight)

        if tp.Z > 0 and bp.Z > 0 then
            visible = true
            local rawH = math_abs(tp.Y - bp.Y)
            local rawW = rawH / 1.6
            h = math_max(rawH, minSize)
            w = math_max(rawW, minSize)
            x = (tp.X + bp.X) * 0.5 - w * 0.5
            y = (tp.Y + bp.Y) * 0.5 - h * 0.5
        end
    else
        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        local minX, minY = math_huge, math_huge
        local maxX, maxY = -math_huge, -math_huge

        for i = 1, 8 do
            local s = BOX_SIGNS[i]
            local p = wtvp(camera, cf * Vector3_new(s[1] * hx, s[2] * hy, s[3] * hz))
            if p.Z > 0 then
                visible = true
                if p.X < minX then minX = p.X end
                if p.X > maxX then maxX = p.X end
                if p.Y < minY then minY = p.Y end
                if p.Y > maxY then maxY = p.Y end
            end
        end

        if visible then
            local rawW = maxX - minX
            local rawH = maxY - minY
            w = math_max(rawW, minSize)
            h = math_max(rawH, minSize)
            x = (minX + maxX) * 0.5 - w * 0.5
            y = (minY + maxY) * 0.5 - h * 0.5
        end
    end

    if visible then
        return true, x, y, w, h
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
--  Управление объектами / модулями
-- ════════════════════════════════════════════════════════════════════════

local function MergeSettings(default, custom)
    local result = {}
    for k, v in pairs(default) do result[k] = v end
    if custom then for k, v in pairs(custom) do result[k] = v end end
    return result
end

-- Кэш партов тела + подписки, поддерживающие список без пере-сканов в кадре.
local function bindBodyParts(espObj)
    local inst = espObj.Instance
    local parts = {}
    espObj.BodyParts = parts

    for _, c in ipairs(inst:GetChildren()) do
        if c:IsA("BasePart") then
            parts[#parts + 1] = c
        end
    end

    local conns = espObj.Conns
    conns[#conns + 1] = inst.ChildAdded:Connect(function(c)
        if c:IsA("BasePart") then
            local bp = espObj.BodyParts
            bp[#bp + 1] = c
        end
    end)
    conns[#conns + 1] = inst.ChildRemoved:Connect(function(c)
        local bp = espObj.BodyParts
        for i = 1, #bp do
            if bp[i] == c then
                bp[i] = bp[#bp]       -- swap-remove, порядок неважен
                bp[#bp] = nil
                break
            end
        end
    end)
end

-- Инициализирует включённые модули, у которых ещё нет Drawing-объектов.
local function EnsureInit(espObj, order)
    local settings = espObj.Settings
    for i = 1, #order do
        local entry = order[i]
        local module = entry.Module
        if settings[module.SettingsKey] and module.Init and not espObj.Drawings[entry.Name] then
            local ok, err = pcall(module.Init, espObj)
            if not ok then
                warn(string.format("[ESP Core] Init '%s' упал на '%s': %s", entry.Name, espObj.Instance.Name, tostring(err)))
            end
        end
    end
end

-- Компилирует список активных Update-модулей объекта (перебор в кадре — по нему).
local function CompileModules(espObj, order)
    local list = {}
    local settings = espObj.Settings
    for i = 1, #order do
        local module = order[i].Module
        if module.Update and settings[module.SettingsKey] then
            list[#list + 1] = module
        end
    end
    espObj.UpdateList = list
end

local function HideObject(espObj)
    local list = espObj.UpdateList
    for i = 1, #list do
        list[i].Update(espObj, HIDDEN)
    end
end

-- ════════════════════════════════════════════════════════════════════════
--  Публичный API
-- ════════════════════════════════════════════════════════════════════════

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

    -- Гарантируем наличие мета-полей
    moduleTable.Priority = moduleTable.Priority or 100
    moduleTable.SettingsKey = moduleTable.SettingsKey or moduleName

    self.Modules[moduleName] = moduleTable
    table.insert(self.ModuleOrder, { Name = moduleName, Module = moduleTable })

    -- Сортировка по приоритету отрисовки (Z-Index)
    table.sort(self.ModuleOrder, function(a, b)
        return a.Module.Priority < b.Module.Priority
    end)

    -- Поздний импорт: доинициализируем и пере-компилируем уже добавленные объекты
    local order = self.ModuleOrder
    for _, espObj in pairs(self.Objects) do
        if espObj.Settings[moduleTable.SettingsKey] then
            EnsureInit(espObj, order)
            CompileModules(espObj, order)
        end
    end

    return moduleTable
end

function ESPLibrary:Add(instance, customSettings)
    if not instance then return end
    if self.Objects[instance] then return self.Objects[instance] end

    local settings = MergeSettings(self.DefaultSettings, customSettings)

    local espObject = {
        Instance = instance,
        Settings = settings,
        Drawings = {},
        CustomData = {},
        BodyParts = nil,         -- кэш партов тела (для Model)
        Conns = {},              -- подписки объекта (ChildAdded/Removed)
        UpdateList = {},          -- скомпилированные активные Update-модули
        RenderData = {            -- переиспользуемый стол кадра (без аллокаций)
            OnScreen = true, Distance = 0, X = 0, Y = 0, W = 0, H = 0,
        },
        IsModel = instance:IsA("Model"),
        IsPart = instance:IsA("BasePart"),
    }

    if espObject.IsModel then
        bindBodyParts(espObject)
    end

    local order = self.ModuleOrder
    EnsureInit(espObject, order)
    CompileModules(espObject, order)

    function espObject:UpdateSettings(newSettings)
        local s = self.Settings
        for k, v in pairs(newSettings) do s[k] = v end

        -- Пере-компиляция активных модулей; выключенные гасим один раз.
        local prev = self.UpdateList
        local ord = ESPLibrary.ModuleOrder
        EnsureInit(self, ord)
        CompileModules(self, ord)

        local active = {}
        local cur = self.UpdateList
        for i = 1, #cur do active[cur[i]] = true end
        for i = 1, #prev do
            local m = prev[i]
            if not active[m] then m.Update(self, HIDDEN) end
        end
    end

    function espObject:Remove()
        local ord = ESPLibrary.ModuleOrder
        for i = 1, #ord do
            local module = ord[i].Module
            if module.Destroy then
                pcall(module.Destroy, self)
            end
        end
        local conns = self.Conns
        for i = 1, #conns do
            conns[i]:Disconnect()
        end
        ESPLibrary.Objects[self.Instance] = nil
    end

    self.Objects[instance] = espObject
    return espObject
end

function ESPLibrary:Remove(instance)
    local obj = self.Objects[instance]
    if obj then
        obj:Remove()
    end
end

-- Запуск рендер-цикла
function ESPLibrary:Start()
    if self.Connections.Render then
        self.Connections.Render:Disconnect()
        self.Connections.Render = nil
    end

    self.Connections.Render = RunService.RenderStepped:Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        -- Кэшируем на кадр: CFrame камеры, её позицию покомпонентно и C-функцию проекции.
        local camCF = camera.CFrame
        local camPos = camCF.Position
        local camX, camY, camZ = camPos.X, camPos.Y, camPos.Z
        local wtvp = camera.WorldToViewportPoint
        local safe = self.SafeUpdate

        for _, espObj in pairs(self.Objects) do
            local instance = espObj.Instance
            local settings = espObj.Settings

            if not instance.Parent or not settings.Enabled then
                HideObject(espObj)
            else
                local cf, size = GetTargetCFAndSize(espObj, settings)
                if cf then
                    local sizeOverride = settings.SizeOverride
                    if sizeOverride then
                        size = sizeOverride
                        -- При UsePrimaryPart cf = HRP (выше центра тела) — пере-центруем.
                        if settings.UsePrimaryPart and espObj.IsModel then
                            local center = bodyBounds(espObj.BodyParts)
                            if center then
                                cf = (cf - cf.Position) + center
                            end
                        end
                    end

                    local cframeOffset = settings.CFrameOffset
                    if cframeOffset then cf = cf * cframeOffset end

                    -- Отсечение по КВАДРАТУ дистанции (sqrt только если цель видима).
                    local pos = cf.Position
                    local ox, oy, oz = pos.X - camX, pos.Y - camY, pos.Z - camZ
                    local distSq = ox * ox + oy * oy + oz * oz
                    local maxD = settings.MaxDistance

                    if distSq > maxD * maxD then
                        HideObject(espObj)
                    else
                        local isStatic = (settings.DynamicSize == 0)
                        local ok, x, y, w, h = ProjectVolume(wtvp, camera, camCF, cf, size, isStatic, settings.MinBoxSize)

                        if ok then
                            local rd = espObj.RenderData
                            rd.OnScreen = true
                            rd.Distance = math_sqrt(distSq)
                            rd.X, rd.Y, rd.W, rd.H = x, y, w, h

                            local list = espObj.UpdateList
                            if safe then
                                for i = 1, #list do
                                    local good, err = pcall(list[i].Update, espObj, rd)
                                    if not good then warn(string.format("[ESP Module Error] %s", tostring(err))) end
                                end
                            else
                                for i = 1, #list do
                                    list[i].Update(espObj, rd)
                                end
                            end
                        else
                            HideObject(espObj)
                        end
                    end
                end
            end
        end
    end)
end

function ESPLibrary:Destroy()
    -- pairs, а не ipairs: коннекты лежат по строковым ключам (Render и т.п.)
    for _, conn in pairs(self.Connections) do
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

-- Автозапуск рендера при импорте либы
ESPLibrary:Start()

return ESPLibrary
