-- Explicit menu-testing host. No input mapping, native discovery or visual hooks.
local TE = require('te.init')
local ObjectPaths = require('te.object_paths')
local M = {}
local function read(path)
    local file = assert(io.open(path, 'rb'), 'missing installed file: ' .. path)
    local content = file:read('*a'); file:close(); return content
end
local function ensureConfig(path, rows)
    local file = io.open(path, 'rb')
    local existed = file ~= nil
    local content = file and file:read('*a') or ''
    if file then file:close() end
    content = content:gsub('\r\n', '\n'):gsub('\r', '\n')
    local lines = {}; for line in (content .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    if lines[#lines] == '' then table.remove(lines) end
    local section, first, finish, sections, present = nil, nil, nil, 0, {}
    for index, line in ipairs(lines) do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then
            if section == 'Templates' and not finish then finish = index end
            section = heading
            if heading == 'Templates' then sections = sections + 1; first = first or index end
        elseif section == 'Templates' then
            local setting = line:match('^%s*([^=;#]+)%s*=')
            if setting then
                setting = setting:match('^%s*(.-)%s*$')
                assert(not present[setting], 'duplicate Templates config key: ' .. setting)
                present[setting] = index
            end
        end
    end
    assert(sections <= 1, 'duplicate Templates config section')
    if section == 'Templates' and not finish then finish = #lines + 1 end
    local missing, changed = {}, false
    local function accepted(row, value)
        if not value or value ~= value then return false end
        if row.Type == 'integer' then
            return value % 1 == 0 and value >= row.Minimum and value <= row.Maximum
        end
        for candidate in row.PresetValues:gmatch('[^|]+') do
            if value == tonumber(candidate) then return true end
        end
        return false
    end
    for _, row in ipairs(rows) do
        local index = present[row.Id]
        if not index then
            missing[#missing + 1] = row.Id .. '=' .. string.format('%.17g', tonumber(row.Default))
        else
            local raw = lines[index]:match('=%s*([^;#]+)')
            local value = raw and tonumber(raw:match('^%s*(.-)%s*$'))
            if not accepted(row, value) then
                lines[index] = row.Id .. '=' .. string.format('%.17g', tonumber(row.Default))
                changed = true
            end
        end
    end
    if #missing == 0 and not changed then return false end
    if not first then
        if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
        lines[#lines + 1] = '[Templates]'
        for _, line in ipairs(missing) do lines[#lines + 1] = line end
    else
        for index = #missing, 1, -1 do table.insert(lines, finish, missing[index]) end
    end
    local output = table.concat(lines, '\n') .. '\n'
    local temporary = path .. '.te.tmp'
    local stale = io.open(temporary, 'rb'); if stale then stale:close() end
    assert(not stale, 'stale temporary config file: ' .. temporary)
    local out = assert(io.open(temporary, 'wb')); assert(out:write(output)); assert(out:close())
    if existed then
        local backup = path .. '.te.bak'
        stale = io.open(backup, 'rb'); if stale then stale:close() end
        assert(not stale, 'stale backup config file: ' .. backup)
        assert(os.rename(path, backup)); local ok, why = os.rename(temporary, path)
        if not ok then os.rename(backup, path); error(why) end
        assert(os.remove(backup))
    else
        assert(os.rename(temporary, path))
    end
    return true
end
local function readConfigValues(path)
    local file = assert(io.open(path, 'rb'), 'missing installed config: ' .. path)
    local content = file:read('*a'); file:close()
    local values, section = {}, nil
    for line in (content:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section = heading
        elseif section == 'Templates' then
            local key, value = line:match('^%s*([^=;#]+)%s*=%s*([^;#]+)')
            if key then
                key, value = key:match('^%s*(.-)%s*$'), tonumber(value:match('^%s*(.-)%s*$'))
                assert(value ~= nil, 'invalid numeric Templates setting: ' .. key)
                values[key] = value
            end
        end
    end
    return values
end
function M.start(root, settings, queue, log)
    local profile = assert(loadfile(root .. '/menu-profile.lua', 't', {}))()
    assert(profile.mode == 'menu-test', 'unsupported installed profile')
    local service
    local inputHost
    local categoryFiles = {}
    for _, path in ipairs(profile.categories or {}) do
        categoryFiles[#categoryFiles + 1] = root .. '/' .. path
    end
    local te = TE.new({categoriesFolder=root..'/Scripts/categories',
        categoryFiles=categoryFiles, templatesFolder=root..'/Scripts',
        listFiles=function() return {} end,
        resolveTarget=function(category, context)
            if type(context)=='table' and type(context.targets)=='table' and context.targets[category]~=nil then
                return context.targets[category]
            end
        end})
    for _, path in ipairs(profile.templates) do te:registerTemplate(root .. '/' .. path) end
    te:loadTemplatesFromRegister()
    local catalog = assert(loadfile(root .. '/identity-catalog.lua', 't', {}))()
    local menu = te:generateMenu({catalog=catalog,description=profile.description})
    assert(menu.aggregate.manifest == read(root .. '/mod_settings.ini'), 'template/schema changed; rebuild TE menu before restart')
    local pageDefinitions = assert(loadfile(root .. '/menu-pages.lua', 't', {}))()
    assert(pageDefinitions.version == 1 and #pageDefinitions.pages == #menu.pages,
        'category page definitions changed; rebuild TE menu before restart')
    for index, page in ipairs(menu.pages) do
        local saved = pageDefinitions.pages[index]
        assert(saved.id == page.id and saved.category == page.category and saved.module == page.module
            and saved.manifest == page.manifest, 'routed page changed; rebuild TE menu before restart')
    end
    if ensureConfig(root .. '/config.ini', menu.rows) then log('Added defaults for new template settings.') end
    service = {}
    function service:valid(object)
        if object == nil then return false end
        local ok, value = pcall(function() return object:IsValid() end)
        return ok and value == true
    end
    function service:identity(object)
        assert(self:valid(object), 'invalid native object')
        return object:GetFullName()
    end
    function service:same(a, b)
        return self:valid(a) and self:valid(b) and self:identity(a) == self:identity(b)
    end
    function service:parent(object)
        if not self:valid(object) then return nil end
        local parent = object:GetParent()
        return self:valid(parent) and parent or nil
    end
    function service:findObject(path)
        if type(FindAllOf) ~= 'function' then return nil end
        return ObjectPaths.findLive(path, FindAllOf, function(object) return self:valid(object) end)
    end
    function service:activateQuickslot(kind, slot)
        local field = kind == 'ability' and 'WBP_AA_Quickslots' or kind == 'consumable' and 'WBP_HUD_Quickslots' or nil
        local names = {'Left', 'Top', 'Right', 'Bottom'}
        if not field or not names[slot] or type(FindAllOf) ~= 'function' then return false end
        local ok, huds = pcall(FindAllOf, 'WBP_GameHUD_C')
        if not ok or type(huds) ~= 'table' then return false end
        for _, hud in ipairs(huds) do
            local named = self:valid(hud) and self:identity(hud) or ''
            if named:find('/Engine/Transient', 1, true) then
                local wheel = hud[field]
                local button = wheel and wheel[names[slot]]
                local unwrapped, value = pcall(function() return button:get() end)
                if unwrapped then button = value end
                if self:valid(button) then
                    local clicked = pcall(function() button:BP_OnClicked() end)
                    return clicked
                end
            end
        end
        return false
    end
    function service:selectQuickslotGroup(index)
        if index ~= 1 and index ~= 2 or type(FindAllOf) ~= 'function' then return false end
        local ok, huds = pcall(FindAllOf, 'WBP_GameHUD_C')
        if not ok or type(huds) ~= 'table' then return false end
        for _, hud in ipairs(huds) do
            if self:valid(hud) and self:identity(hud):find('/Engine/Transient', 1, true) then
                local switcher = hud.QuickslotsSwitcher
                local unwrapped, value = pcall(function() return switcher:get() end)
                if unwrapped then switcher = value end
                if self:valid(switcher) then
                    local selected = pcall(function() switcher:SetActiveWidgetIndex(index - 1) end)
                    return selected
                end
            end
        end
        return false
    end
    inputHost = require('te.player_actions.ue4ss_host').new(queue, log,
        te.categories:getCategory('player.quickslots'))
    local initial = menu.decode(readConfigValues(root .. '/config.ini'))['player.quickslots']
    if initial and initial.id then
        local template = assert(te.registry.byId[initial.id], 'persisted Quickslots template is unavailable').template
        local bound, why = inputHost:apply(template, initial.configuration, service)
        if bound then log('Persisted Quickslots template input is active.')
        else log('Persisted Quickslots template input pending: ' .. tostring(why)) end
    else
        inputHost:deactivate()
    end
    local routed = {subscribe=function(provider, callback)
        return settings.subscribe(provider, function(event) queue(function() callback(event) end) end)
    end}
    te:subscribeApplied(routed, menu, function()
        return {playerActions=service, services={['menu.templates']={}}}
    end, function(ok, errors)
        if ok then
            local id, configuration = te.runtime:selection('player.quickslots')
            if not id then inputHost:deactivate(); log('Quickslots template cleared; restored native input actions.')
            else
                local template = te.registry.byId[id].template
                local bound, why = inputHost:apply(template, configuration, service)
                if bound then log('Committed template settings received; replacement quickslots bindings are active.')
                else log('Quickslots bindings pending: ' .. tostring(why)) end
            end
        elseif type(errors)=='table' then
            for category, message in pairs(errors) do log(category .. ': ' .. tostring(message)) end
        else log('Apply failed: ' .. tostring(errors)) end
    end)
    log('Menu-testing runtime ready. Settings persist through AMM; change a setting and Apply to exercise callbacks.')
    return te, menu
end
return M
