# Universal ESP Framework — руководство

Модульный ESP-фреймворк для Roblox-эксплойтов. Три слоя, строго разделённых:

| Слой       | Файл                | Ответственность                                                        |
|------------|---------------------|------------------------------------------------------------------------|
| **Ядро**   | `main.luau`         | Жизненный цикл целей, реестр модулей, геометрия, единственный render-loop |
| **Модуль** | `modules/*.luau`    | Что и как рисовать (бокс, трассер, текст…). Получает готовый `renderData` |
| **Лоадер** | `exampleLoader*.luau` | Кого трекать (игроки/объекты), тимчек, цвета, шаблоны настроек         |

Ядро не знает про конкретные модули и не содержит предметной логики; модуль не знает про
других модулей и про игроков; лоадер не лезет в потроха ядра. Связь между слоями — только
через публичный API и контракты, описанные ниже.

---

## Оглавление

1. [Быстрый старт](#быстрый-старт)
2. [Архитектура и поток кадра](#архитектура-и-поток-кадра)
3. [Контракт модуля](#контракт-модуля)
4. [Контракт `renderData`](#контракт-renderdata)
5. [Поля `espObj`, доступные модулю](#поля-espobj-доступные-модулю)
6. [Написание модуля с нуля](#написание-модуля-с-нуля)
7. [Публичный API ядра](#публичный-api-ядра)
8. [Справочник настроек ядра](#справочник-настроек-ядра)
9. [Использование модуля в лоадере](#использование-модуля-в-лоадере)
10. [Жизненный цикл, очистка, утечки](#жизненный-цикл-очистка-утечки)
11. [Производительность](#производительность)

---

## Быстрый старт

```lua
-- 1. Загрузка ядра (грузить через loadstring — так оно остаётся НАТИВНЫМ кодом,
--    даже если лоадер обфусцирован/виртуализирован).
local ESP = loadstring(game:HttpGet(".../main.luau"))()

-- 2. Подключение модулей (из RepoURL ядра)
ESP:Import("CornerBox")
ESP:Import("Tracer")

-- 3. Навешивание ESP на цель
ESP:Add(someModelOrPart, {
    CornerBox    = true,                    -- включить модуль (ключ == SettingsKey)
    BoxColor     = Color3.fromRGB(0,255,120),
    DynamicSize  = 1,
    MaxDistance  = 5000,
})
```

Render-loop стартует автоматически при загрузке ядра (`ESPLibrary:Start()` в конце `main.luau`).

---

## Архитектура и поток кадра

Каждый кадр (`RunService.RenderStepped`) ядро проходит по `ActiveList` и для каждой цели:

1. **Жива?** `instance.Parent` есть и `settings.Enabled` — иначе гасим (`HideObject`).
2. **Опорный CFrame** — `cheapRefCF` (HRP/PrimaryPart/первый парт) без прохода по всем партам.
3. **Пре-куллинг** по квадрату дистанции от опорной точки (далёкие цели отсекаются ДО тяжёлой геометрии).
4. **Мотион-кэш**: если опорный CFrame не изменился с прошлого кадра и набор партов тот же —
   переиспользуем готовый мировой трансформ (минуя `bodyBounds`/рецентровку). Иначе пересчитываем.
5. **Точная дистанция** + финальный куллинг.
6. **Проекция** мирового объёма в экранный прямоугольник (`ProjectVolume`).
7. **`CallUpdates`** — вызывает `Update` каждого активного модуля цели, передавая `renderData`.

Проекция (п.6) и отрисовка (п.7) выполняются **каждый кадр всегда** — даже для неподвижной
цели, потому что её положение на экране меняется при движении камеры. Кэшируется только
мировой трансформ (п.4), не экранные координаты.

---

## Контракт модуля

Модуль — это `table`, возвращаемый из `return`. Поля:

| Поле          | Тип       | Обяз. | Назначение                                                                 |
|---------------|-----------|-------|----------------------------------------------------------------------------|
| `Priority`    | number    | нет   | Порядок вызова/отрисовки (z-order). Меньше = раньше = «под». По умолч. `100`. |
| `SettingsKey` | string    | нет   | Ключ в настройках, который включает модуль. По умолч. = имя из `Import`.     |
| `Init`        | function  | да*   | `Init(espObj)` — создать Drawing-объекты. Зовётся один раз при включении.    |
| `Update`      | function  | да    | `Update(espObj, renderData)` — кадровая логика: позиция/стиль/видимость.     |
| `Destroy`     | function  | да*   | `Destroy(espObj)` — снять Drawing-объекты, обнулить неймспейсы. Идемпотентно.|

\* формально опциональны, но реальный визуальный модуль реализует все три.

**Соглашения по именованию (важно):** ключ, под которым модуль кладёт свои Drawing-объекты
в `espObj.Drawings`, **должен совпадать с именем из `ESP:Import`** — ядро использует
`espObj.Drawings[Name]` как метку «уже проинициализирован» (см. `EnsureInit`). На практике
держи `Name == SettingsKey == ключ в Drawings/CustomData` одинаковыми (`"CornerBox"`).

**Соглашения по поведению:**
- Свой приватный кэш храни в `espObj.CustomData[Name]` (dirty-check, флаг `Shown` и т.п.).
- `Visible` переключай только на **переходах** (через флаг `Shown`), а не каждый кадр.
- Свойства Drawing (`Color`/`Thickness`/`Transparency`) пиши только при изменении (dirty-check
  против `Last*` в кэше) — записи в Drawing дороже сравнения.
- Контур-подложку (outline) рисуй отдельным Drawing с меньшим `ZIndex`, core — с большим.

---

## Контракт `renderData`

Ядро передаёт `Update` один переиспользуемый стол (не аллоцируется в кадре). Поля:

| Поле        | Тип     | Когда валидно                | Смысл                                              |
|-------------|---------|------------------------------|----------------------------------------------------|
| `OnScreen`  | bool    | всегда                       | Цель спроецировалась на экран (не за камерой/краем) |
| `Distance`  | number  | при `OnScreen`/в радиусе     | Дистанция до центра цели (студы)                    |
| `X`, `Y`    | number  | при `OnScreen`               | Левый-верхний угол экранного бокса (px)             |
| `W`, `H`    | number  | при `OnScreen`               | Ширина/высота экранного бокса (px)                  |
| `WorldCF`   | CFrame  | пока цель в радиусе          | Разрешённый мировой трансформ цели (даже off-screen)|
| `WorldSize` | Vector3 | пока цель в радиусе          | Мировой размер цели                                 |

**Скрытое состояние.** Когда цель гасится (оффскрин-куллинг, выключена, вне радиуса), ядро
передаёт общий стол `HIDDEN = { OnScreen = false }` — там нет ни `X/Y`, ни `WorldCF`.

Поэтому в `Update` **первым делом проверяй видимость**:
- 2D-модулям (бокс по экранному прямоугольнику) хватает `if not renderData.OnScreen then …гаснем…`.
- 3D-модулям и off-screen индикаторам (трассер, стрелки), которым нужен мировой трансформ,
  проверяй `WorldCF`: `local cf = renderData.WorldCF; if not cf then …гаснем… end`.
  `WorldCF` отдаётся даже когда `OnScreen == false` (цель за спиной, но в радиусе) — именно
  так трассер рисует индикатор к краю экрана.

---

## Поля `espObj`, доступные модулю

| Поле               | Назначение                                                              |
|--------------------|-------------------------------------------------------------------------|
| `espObj.Settings`  | Слитые настройки (дефолты ядра + кастом). Модуль читает свои ключи отсюда.|
| `espObj.Drawings`  | Сюда модуль кладёт свои Drawing-хэндлы под ключом `Name`.                |
| `espObj.CustomData`| Приватный неймспейс модуля под ключом `Name` (кэш/флаги).               |
| `espObj.Instance`  | Сам таргет (Model/BasePart).                                            |
| `espObj.IsModel`   | `true`, если таргет — `Model`.                                          |
| `espObj.IsPart`    | `true`, если таргет — `BasePart`.                                       |

Остальные поля (`BodyParts`, `RenderData`, `CachedCF`, `_index`, …) — внутренние, модулю
трогать их не нужно.

---

## Написание модуля с нуля

Полный минимальный модуль — прямоугольный бокс на одном Drawing `"Square"`. Демонстрирует
все точки контракта: `Init`/`Update`/`Destroy`, обработку `OnScreen`, dirty-check, флаг `Shown`.

```lua
--!nocheck
-- Module: Box.luau — простой прямоугольный бокс (одна Drawing "Square")

local Box = {
    Priority    = 10,        -- рисуется рано (под трассером с Priority=20)
    SettingsKey = "Box",     -- включается ключом settings.Box == true
}

local DRAWING = Drawing.new
local V2 = Vector2.new
local DEFAULT_COLOR = Color3.fromRGB(0, 255, 120)

-- Создаём Drawing-объекты один раз. Ключ в Drawings == имя модуля ("Box").
function Box.Init(espObj)
    local s = espObj.Settings

    local square = DRAWING("Square")
    square.Visible      = false
    square.Filled       = false
    square.Thickness    = s.BoxThickness or 2
    square.Color        = s.BoxColor or DEFAULT_COLOR
    square.Transparency = s.BoxTransparency or 1

    espObj.Drawings.Box = square
    espObj.CustomData.Box = {            -- приватный кэш модуля
        Shown         = false,
        LastColor     = square.Color,
        LastThickness = square.Thickness,
    }
end

-- Кадровая логика. renderData уже посчитан ядром.
function Box.Update(espObj, renderData)
    local square = espObj.Drawings.Box
    if not square then return end
    local cache = espObj.CustomData.Box

    -- 1) Видимость: гасим один раз на переходе в скрытое состояние.
    if not renderData.OnScreen then
        if cache.Shown then
            square.Visible = false
            cache.Shown = false
        end
        return
    end

    -- 2) Геометрия: берём готовый экранный прямоугольник из renderData.
    square.Size     = V2(renderData.W, renderData.H)
    square.Position = V2(renderData.X, renderData.Y)

    -- 3) Свойства: пишем только при изменении (dirty-check).
    local s = espObj.Settings
    local color = s.BoxColor or DEFAULT_COLOR
    if color ~= cache.LastColor then
        square.Color = color
        cache.LastColor = color
    end
    local thick = s.BoxThickness or 2
    if thick ~= cache.LastThickness then
        square.Thickness = thick
        cache.LastThickness = thick
    end

    -- 4) Показываем один раз на переходе в видимое состояние.
    if not cache.Shown then
        square.Visible = true
        cache.Shown = true
    end
end

-- Снять Drawing-объекты и обнулить неймспейсы. Идемпотентно (guard через `if`).
function Box.Destroy(espObj)
    local square = espObj.Drawings.Box
    if square then
        square:Remove()
        espObj.Drawings.Box = nil
        espObj.CustomData.Box = nil
    end
end

return Box
```

**3D-модуль / трассер** отличается только тем, что в `Update` опирается на `renderData.WorldCF`
(а не на `X/Y/W/H`) и сам проецирует мировые точки через `Camera:WorldToViewportPoint`.
Образцы — `modules/CornerBox3D.luau` и `modules/Tracer.luau`.

**Контур (outline)** — отдельные Drawing-объекты с `ZIndex = 0`, core с `ZIndex = 1`; контур
копирует координаты core, толщина больше на `OutlineThickness`. Образец — `modules/CornerBox.luau`.

---

## Публичный API ядра

### `ESP:Import(moduleName, customUrlOrModule?) -> module | nil`
Подключает модуль. Третий аргумент:
- **нет** → грузит `RepoURL .. moduleName .. ".luau"` через `HttpGet`;
- **string** → грузит с этого URL;
- **table** → берёт готовую таблицу модуля (локальный модуль без сети).

Доустанавливает `Priority`/`SettingsKey` по умолчанию, сортирует порядок отрисовки, доинициализирует
уже добавленные объекты. Повторный `Import` того же имени — no-op (возвращает закэшированный).

```lua
ESP:Import("Box")                                 -- из RepoURL
ESP:Import("Box", "https://my.host/Box.luau")     -- кастомный URL
ESP:Import("Box", require(script.Box))            -- готовая таблица
```

### `ESP:Add(instance, customSettings?) -> espObject`
Навешивает ESP на `Model`/`BasePart`. Сливает настройки с `DefaultSettings`, инициализирует
включённые модули, вешает авто-очистку на уничтожение инстанса. Повторный `Add` той же цели
возвращает существующий объект.

### `ESP:Remove(instance)` / `espObject:Remove()`
Снимает ESP: `Destroy` всех модулей, дисконнект подписок, удаление из реестров. Идемпотентно.

### `espObject:UpdateSettings(newSettings)`
Сливает новые настройки в существующие, пере-компилирует активные модули (только что выключенные
гасит один раз), сбрасывает мотион-кэш. Используется лоадером на лету (смена цвета команды,
вкл/выкл трассера, и т.п.).

```lua
esp:UpdateSettings({ BoxColor = Color3.fromRGB(255,0,0), Tracer = false })
```

### `ESP:Start()` / `ESP:Destroy()`
`Start` — (пере)подключает render-loop (зовётся автоматически при загрузке). `Destroy` —
полностью гасит либу: дисконнект всего, удаление всех целей, очистка реестров.

### Поля
- `ESP.SafeUpdate` (bool) — `true` оборачивает `Update` в `pcall+warn` (отладка падающих модулей),
  `false` (по умолч.) — прямой вызов (максимальная скорость).
- `ESP.RepoURL` (string) — база для `Import` без явного URL.

---

## Справочник настроек ядра

Это **общие** ключи (`DefaultSettings`). Модульные ключи (`BoxColor`, `TracerOrigin`,
`Outline`, …) определяет и читает сам модуль — см. его исходник.

| Ключ             | Тип / по умолч.   | Назначение                                                                 |
|------------------|-------------------|----------------------------------------------------------------------------|
| `Enabled`        | bool / `true`     | Глобальный вкл/выкл этой цели.                                              |
| `MaxDistance`    | number / `10000`  | Радиус отсечения (студы).                                                   |
| `MinBoxSize`     | number / `4`      | Минимальный размер экранного бокса (px), чтобы не схлопывался вдали.        |
| `DynamicSize`    | number / `0`      | `0` = статичная форма (верт. размер, аспект `h/1.6` — под гуманоида); `≠0` = проекция 8 углов AABB (реальный силуэт). |
| `UsePrimaryPart` | bool / `false`    | Брать `PrimaryPart`/HRP как референс (дёшево) вместо AABB по партам тела.   |
| `SizeOverride`   | Vector3 / `nil`   | Жёсткий размер бокса вместо измеренного.                                    |
| `CFrameOffset`   | CFrame / `nil`    | Доп. смещение трансформа цели.                                              |

Для цели-гуманоида типовой дешёвый профиль: `UsePrimaryPart = true` + `SizeOverride = Vector3.new(4, 6.9, 4)`.
Для произвольного объекта по реальной форме: `DynamicSize = 1`, без `SizeOverride`.

---

## Использование модуля в лоадере

### Минимум

```lua
local ESP = loadstring(game:HttpGet(".../main.luau"))()
ESP:Import("Box")

ESP:Add(workspace.SomeModel, {
    Box          = true,                  -- == SettingsKey модуля Box
    BoxColor     = Color3.fromRGB(0,255,120),
    BoxThickness = 2,
    DynamicSize  = 1,
    MaxDistance  = 5000,
})
```

### Полноценный лоадер: трекинг игроков + тимчек + очистка

Шаблон (сжатая версия `exampleLoader.luau`). Каждому игроку — своя копия настроек; цвет/видимость
обновляются на лету при смене команды; всё чистится при выходе и при выгрузке скрипта.

```lua
local storage = (getgenv and getgenv()) or shared
if storage.ESP_Cleanup then pcall(storage.ESP_Cleanup); storage.ESP_Cleanup = nil end

local ESP = loadstring(game:HttpGet(".../main.luau"))()
ESP:Import("CornerBox")
ESP:Import("Tracer")

local BASE = {                              -- шаблон на каждого игрока
    CornerBox       = true,
    DynamicSize     = 0,
    UsePrimaryPart  = true,
    SizeOverride    = Vector3.new(4, 6.9, 4),
    BoxColor        = Color3.fromRGB(0,255,120),
    BoxThickness    = 2.5,
    TracerOrigin    = "mouse",
    Outline         = true,
    MaxDistance     = 10000,
}

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local tracked, conns = {}, {}

local function copy(t) local c={} for k,v in pairs(t) do c[k]=v end return c end
local function isAlly(plr) return plr.Team ~= nil and plr.Team == LP.Team end
local function colorFor(plr) return plr.Team and plr.TeamColor.Color or Color3.fromRGB(255,60,60) end

local function apply(tr, plr)
    if not tr.esp then return end
    tr.esp:UpdateSettings({                 -- цвет/трассер подхватятся dirty-check'ом модулей
        BoxColor = colorFor(plr),
        Tracer   = not isAlly(plr),
    })
end

local function addPlayer(plr)
    if plr == LP or tracked[plr] then return end
    local tr = {} tracked[plr] = tr

    local function onChar(char)
        if tr.esp then pcall(function() tr.esp:Remove() end) end
        tr.esp = ESP:Add(char, copy(BASE))  -- НЕ обязательно ловить Destroy вручную:
        apply(tr, plr)                      -- ядро само снимет ESP на уничтожении char
    end

    tr.charConn = plr.CharacterAdded:Connect(function(c) task.spawn(onChar, c) end)
    tr.teamConn = plr:GetPropertyChangedSignal("Team"):Connect(function() apply(tr, plr) end)
    if plr.Character then task.spawn(onChar, plr.Character) end
end

local function removePlayer(plr)
    local tr = tracked[plr]; if not tr then return end
    if tr.charConn then tr.charConn:Disconnect() end
    if tr.teamConn then tr.teamConn:Disconnect() end
    if tr.esp then pcall(function() tr.esp:Remove() end) end
    tracked[plr] = nil
end

for _, p in ipairs(Players:GetPlayers()) do pcall(addPlayer, p) end
conns[#conns+1] = Players.PlayerAdded:Connect(addPlayer)
conns[#conns+1] = Players.PlayerRemoving:Connect(removePlayer)

storage.ESP_Cleanup = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for p in pairs(tracked) do pcall(removePlayer, p) end
    pcall(function() ESP:Destroy() end)
end
```

Готовые рабочие лоадеры: `exampleLoader.luau` (2D-бокс) и `exampleLoader3D.luau` (3D-бокс).

---

## Жизненный цикл, очистка, утечки

- **Авто-очистка цели.** В `Add` на инстанс вешается `instance.Destroying` → при уничтожении
  (респаун/выход/`:Destroy()`) ядро само зовёт `espObject:Remove()`: снимает Drawing-объекты,
  дисконнектит подписки, удаляет записи из `Objects`/`ActiveList`. **Утечки Drawing-объектов нет**,
  даже если лоадер забыл позвать `:Remove()`.
- **Идемпотентность.** Повторный `:Remove()` (например, лоадер снял на респауне, а потом сработал
  `Destroying`) безопасен: модульные `Destroy` проверяют `if drawing then`, `Disconnect` повторно
  безопасен, индекс в `ActiveList` уже сброшен.
- **`Parent == nil` без `Destroy`.** Render-loop просто прячет цель (на случай временного
  раз-парента). Освобождение — по `Destroying` или явному `:Remove()`.
- **Выгрузка скрипта.** Держи cleanup в `getgenv().ESP_Cleanup` и вызывай его в начале лоадера —
  иначе старый инстанс продолжит жить со своим render-loop (двойные боксы/трассеры).

---

## Производительность

- **Обфускация лоадера.** Лоадер — cold-path (события спавна/смены команды), его виртуализация
  на FPS не влияет. Весь горячий код — в ядре. **Грузи ядро и модули через `loadstring(HttpGet)`**,
  чтобы они оставались нативным Luau-байткодом; НЕ прогоняй их через виртуализатор — иначе
  render-loop пойдёт через VM и это убьёт кадр.
- **Мотион-кэш.** Неподвижная цель не пересчитывает мировой трансформ (минует `bodyBounds`):
  читается один опорный CFrame и сравнивается с прошлым кадром. Проекция и отрисовка — каждый кадр.
- **Пре-куллинг по дистанции** идёт ДО тяжёлой геометрии: далёкие цели не считают `bodyBounds`.
- **Dirty-check** в модулях: свойства Drawing пишутся только при изменении.
- **`ActiveList`** — перебор в кадре по упакованному массиву; `Objects` (хэш) — для O(1) lookup.
- **`SafeUpdate = false`** по умолчанию — прямой вызов `Update` без `pcall`. Включай только для отладки.
```
