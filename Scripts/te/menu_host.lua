-- Explicit menu-testing host. No input mapping, native discovery or visual hooks.
local TE = require('te.init')
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
                present[setting] = true
            end
        end
    end
    assert(sections <= 1, 'duplicate Templates config section')
    if section == 'Templates' and not finish then finish = #lines + 1 end
    local missing = {}
    for _, row in ipairs(rows) do
        if not present[row.Id] then
            missing[#missing + 1] = row.Id .. '=' .. string.format('%.17g', tonumber(row.Default))
        end
    end
    if #missing == 0 then return false end
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
function M.start(root, settings, queue, log)
    local profile = assert(loadfile(root .. '/menu-profile.lua', 't', {}))()
    assert(profile.mode == 'menu-test', 'unsupported installed profile')
    local te = TE.new({categoriesPath=root..'/categories.lua',templatesFolder=root..'/templates',
        listFiles=function() return {} end})
    for _, path in ipairs(profile.templates) do te:registerTemplate(root .. '/' .. path) end
    te:loadTemplatesFromRegister()
    for _, entry in ipairs(te.registry.templates) do
        if entry.template.category == 'player.quickslots' then
            assert(entry.template.widgetRenderingEnabled == false, 'menu-test requires provider rendering disabled')
        end
    end
    local catalog = assert(loadfile(root .. '/identity-catalog.lua', 't', {}))()
    local menu = te:generateMenu({catalog=catalog,description=profile.description})
    assert(menu.aggregate.manifest == read(root .. '/mod_settings.ini'), 'template/schema changed; rebuild TE menu before restart')
    local pageDefinitions = assert(loadfile(root .. '/menu-pages.lua', 't', {}))()
    assert(pageDefinitions.version == 1 and #pageDefinitions.pages == #menu.pages,
        'category page definitions changed; rebuild TE menu before restart')
    for index, page in ipairs(menu.pages) do
        local saved = pageDefinitions.pages[index]
        assert(saved.id == page.id and saved.category == page.category and saved.manifest == page.manifest,
            'category page changed; rebuild TE menu before restart')
    end
    if ensureConfig(root .. '/config.ini', menu.rows) then log('Added defaults for new template settings.') end
    local service = {}
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
    local routed = {subscribe=function(provider, callback)
        return settings.subscribe(provider, function(event) queue(function() callback(event) end) end)
    end}
    te:subscribeApplied(routed, menu, function()
        return {playerActions=service, services={['menu.templates']={}}}
    end, function(ok, errors)
        if ok then log('Committed template settings received; gameplay binding/visual cutover is disabled.')
        elseif type(errors)=='table' then
            for category, message in pairs(errors) do log(category .. ': ' .. tostring(message)) end
        else log('Apply failed: ' .. tostring(errors)) end
    end)
    log('Menu-testing runtime ready. Settings persist through AMM; change a setting and Apply to exercise callbacks.')
    return te, menu
end
return M
