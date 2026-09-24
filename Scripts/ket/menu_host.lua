-- Installed host for menu settings, quickslot controls, and visual templates.
local Boot = require('ket.menu_boot')
local ObjectPaths = require('ket.object_paths')
local Provider = require('ket.provider_settings')
local M = {}
local function read(path)
    local file = assert(io.open(path, 'rb'), 'missing installed file: ' .. path)
    local content = file:read('*a'); file:close(); return content
end
local function ensureConfig(path, rows, textSettings)
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
        if row.ammNavigation ~= 1 then
            local index = present[row.Id]
            if not index then
                local default = tonumber(row.Default)
                missing[#missing + 1] = row.Id .. '=' .. string.format('%.17g', default)
            else
                local raw = lines[index]:match('=%s*([^;#]+)')
                local value = raw and tonumber(raw:match('^%s*(.-)%s*$'))
                if not accepted(row, value) then
                    lines[index] = row.Id .. '=' .. string.format('%.17g', tonumber(row.Default))
                    changed = true
                end
            end
        end
    end
    for settingId, spec in pairs(textSettings or {}) do
        local index = present[settingId]
        if not index then
            missing[#missing + 1] = settingId .. '=' .. spec.default
        else
            local raw = lines[index]:match('=%s*([^;#]*)')
            Provider.validateText(spec.format, raw and raw:match('^%s*(.-)%s*$'))
        end
    end
    table.sort(missing)
    if #missing == 0 and not changed then return false end
    if not first then
        if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
        lines[#lines + 1] = '[Templates]'
        for _, line in ipairs(missing) do lines[#lines + 1] = line end
    else
        for index = #missing, 1, -1 do table.insert(lines, finish, missing[index]) end
    end
    local output = table.concat(lines, '\n') .. '\n'
    local temporary = path .. '.ket.tmp'
    local stale = io.open(temporary, 'rb'); if stale then stale:close() end
    assert(not stale, 'stale temporary config file: ' .. temporary)
    local out = assert(io.open(temporary, 'wb')); assert(out:write(output)); assert(out:close())
    if existed then
        local backup = path .. '.ket.bak'
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
local function readConfigValues(path, textSettings, rows)
    local file = assert(io.open(path, 'rb'), 'missing installed config: ' .. path)
    local content = file:read('*a'); file:close()
    local values, section = {}, nil
    local known = {}
    for _, row in ipairs(rows) do known[row.Id] = true end
    for key in pairs(textSettings or {}) do known[key] = true end
    for line in (content:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section = heading
        elseif section == 'Templates' then
            local key, value = line:match('^%s*([^=;#]+)%s*=%s*([^;#]*)')
            if key and known[key] then
                key, value = key:match('^%s*(.-)%s*$'), value:match('^%s*(.-)%s*$')
                if textSettings and textSettings[key] then
                    values[key] = Provider.validateText(textSettings[key].format, value)
                else
                    value = tonumber(value)
                    assert(value ~= nil, 'invalid numeric Templates setting: ' .. key)
                    values[key] = value
                end
            end
        end
    end
    return values
end
function M.start(root, settings, queue, log)
    local service
    local ket, menu = Boot.prepare(root, {resolveTarget=function(category, context)
            if type(context)=='table' and type(context.targets)=='table' and context.targets[category]~=nil then
                return context.targets[category]
            end
        end})
    if ensureConfig(root .. '/config.ini', menu.rows, menu.textSettings) then
        log('Added defaults for new template settings.')
    end
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
    local visualHost = require('ket.quickslot_visual_host').new(ket.runtime, service)
    local initial = menu.decode(readConfigValues(root .. '/config.ini', menu.textSettings, menu.rows))['player.quickslots']
    if initial and initial.id then
        assert(ket.registry.byId[initial.id], 'persisted Quickslots template is unavailable')
        local shown, visualWhy = visualHost:select(initial)
        if not shown then log('Persisted Quickslots visuals failed: ' .. tostring(visualWhy))
        elseif visualWhy == 'not_ready' then log('Persisted Quickslots visuals are waiting for the HUD.') end
    else
        visualHost:adopt(nil)
    end
    local routed = {subscribe=function(provider, callback)
        return settings.subscribe(provider, function(event) queue(function()
            local values = {}
            for key, value in pairs(event.values) do values[key] = value end
            local current = readConfigValues(root .. '/config.ini', menu.textSettings, menu.rows)
            for settingId in pairs(menu.textSettings) do values[settingId] = current[settingId] end
            callback({providerId=event.providerId, revision=event.revision,
                values=values, changes=event.changes})
        end) end)
    end}
    local scheduleVisualRetry
    ket:subscribeApplied(routed, menu, function()
        return {playerActions=service, services={['menu.templates']={}}}
    end, function(ok, errors)
        if ok then
            local id, settings = ket.runtime:selection('player.quickslots')
            if not id then
                visualHost:adopt(nil)
                log('Quickslots visual template cleared.')
            else
                visualHost:adopt(id, settings)
                log('Committed quickslot visual template settings received.')
                if scheduleVisualRetry then scheduleVisualRetry() end
            end
        elseif type(errors)=='table' then
            for category, message in pairs(errors) do log(category .. ': ' .. tostring(message)) end
        else log('Apply failed: ' .. tostring(errors)) end
    end)
    local visualRetryScheduled, visualApplied = false, false
    local function wakeVisual(invalidate)
        if invalidate then visualApplied = false end
        local ok, ready, why = pcall(function()
            if invalidate then return visualHost:worldInvalidated() end
            return visualHost:wake()
        end)
        if not ok then log('Quickslots visual wake failed: ' .. tostring(ready))
        elseif not ready then log('Quickslots visuals failed: ' .. tostring(why))
        elseif why == 'not_ready' or ket.runtime.pending['player.quickslots'] then
            scheduleVisualRetry()
        elseif visualHost.desired and not visualApplied then
            visualApplied = true
            log('Quickslots visuals applied to the HUD.')
        end
    end
    scheduleVisualRetry = function()
        if visualRetryScheduled or not visualHost.desired
            or not ket.runtime.pending['player.quickslots']
            or type(ExecuteWithDelay) ~= 'function' then return end
        visualRetryScheduled = true
        local scheduled, why = pcall(ExecuteWithDelay, 500, function()
            local queued, queueWhy = pcall(queue, function()
                visualRetryScheduled = false
                wakeVisual(false)
            end)
            if not queued then
                visualRetryScheduled = false
                log('Quickslots visual retry queue failed: ' .. tostring(queueWhy))
            end
        end)
        if not scheduled then
            visualRetryScheduled = false
            log('Quickslots visual retry timer failed: ' .. tostring(why))
        end
    end
    scheduleVisualRetry()
    local function enqueueVisual(invalidate)
        local ok, why = pcall(queue, function() wakeVisual(invalidate) end)
        if not ok then log('Quickslots visual scheduling failed: ' .. tostring(why)) end
    end
    if type(NotifyOnNewObject) == 'function' then
        local ok, why = pcall(NotifyOnNewObject,
            '/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C',
            function() enqueueVisual(true) end)
        if not ok then log('Game HUD notification unavailable: ' .. tostring(why)) end
    end
    if type(RegisterHook) == 'function' then
        local ok, why = pcall(RegisterHook, '/Script/UMG.UserWidget:Construct',
            function() end, function()
                if visualHost.desired and ket.runtime.pending['player.quickslots'] then
                    enqueueVisual(false)
                end
            end)
        if not ok then log('Widget construction retry unavailable: ' .. tostring(why)) end
    end
    if type(RegisterLoadMapPostHook) == 'function' then
        local ok, why = pcall(RegisterLoadMapPostHook, function() enqueueVisual(true) end)
        if not ok then log('Map-load visual retry unavailable: ' .. tostring(why)) end
    end
    log('KET runtime ready. Apply commits template visuals; KEC runs quickslot controls.')
    return ket, menu
end
return M
