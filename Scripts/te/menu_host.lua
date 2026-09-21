-- Explicit menu-testing host. No input mapping, native discovery or visual hooks.
local TE = require('te.init')
local M = {}
local function read(path)
    local file = assert(io.open(path, 'rb'), 'missing installed file: ' .. path)
    local content = file:read('*a'); file:close(); return content
end
function M.start(root, settings, queue, log)
    local profile = assert(loadfile(root .. '/menu-profile.lua', 't', {}))()
    assert(profile.mode == 'menu-test', 'unsupported installed profile')
    local te = TE.new({categoriesPath=root..'/categories.lua',templatesFolder=root..'/templates',
        listFiles=function() return {} end})
    for _, path in ipairs(profile.templates) do te:registerTemplate(root .. '/' .. path) end
    te:loadTemplatesFromRegister()
    for _, entry in ipairs(te.registry.templates) do
        assert(entry.template.widgetRenderingEnabled == false, 'menu-test requires provider rendering disabled')
    end
    local catalog = assert(loadfile(root .. '/identity-catalog.lua', 't', {}))()
    local menu = te:generateMenu({catalog=catalog,description=profile.description})
    assert(menu.manifest == read(root .. '/mod_settings.ini'), 'template/schema changed; rebuild TE menu before restart')
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
    te:subscribeApplied(routed, menu, function() return {playerActions=service} end, function(ok, errors)
        if ok then log('Committed template settings received; gameplay binding/visual cutover is disabled.')
        elseif type(errors)=='table' then
            for category, message in pairs(errors) do log(category .. ': ' .. tostring(message)) end
        else log('Apply failed: ' .. tostring(errors)) end
    end)
    log('Menu-testing runtime ready. Settings persist through AMM; change a setting and Apply to exercise callbacks.')
    return te, menu
end
return M
