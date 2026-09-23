local TE = require('te.init')

local M = {}

local function read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = file:read('*a')
    file:close()
    return content
end

local function writeChanged(path, content)
    local old = read(path)
    if old == content then return false end
    local temporary = path .. '.te.tmp'
    assert(not read(temporary), 'stale temporary menu file: ' .. temporary)
    local file = assert(io.open(temporary, 'wb'))
    assert(file:write(content))
    assert(file:close())
    local backup = path .. '.te.bak'
    if old then
        assert(not read(backup), 'stale backup menu file: ' .. backup)
        local moved, why = os.rename(path, backup)
        if not moved then os.remove(temporary); error(why) end
    end
    local renamed, why = os.rename(temporary, path)
    if not renamed then
        if old then assert(os.rename(backup, path), 'could not restore previous menu file') end
        os.remove(temporary)
        error(why)
    end
    if old then assert(os.remove(backup)) end
    return true
end

local function pagesSource(pages)
    local lines = {'return {version=1,pages={'}
    for _, page in ipairs(pages) do
        local category = page.category and string.format('%q', page.category) or 'nil'
        local module = page.module and string.format('%q', page.module) or 'nil'
        lines[#lines + 1] = string.format('{id=%q,name=%q,category=%s,module=%s,version=%q,manifest=%q},',
            page.id, page.name, category, module, '0.0.19', page.manifest)
    end
    lines[#lines + 1] = '}}\n'
    return table.concat(lines, '\n')
end

local function catalogSource(catalog)
    local lines = {'return {version=1,next=' .. catalog.next .. ',entries={'}
    local keys = {}
    for key in pairs(catalog.entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format('[%q]=%d,', key, catalog.entries[key])
    end
    lines[#lines + 1] = '}}\n'
    return table.concat(lines, '\n')
end

function M.prepare(root, options)
    options = options or {}
    local profile = assert(loadfile(root .. '/menu-profile.lua', 't', {}))()
    assert(profile.mode == 'menu-test', 'unsupported installed profile')
    local categoryFiles = {}
    for _, path in ipairs(profile.categories or {}) do categoryFiles[#categoryFiles + 1] = root .. '/' .. path end
    local te = TE.new({categoriesFolder=root .. '/Scripts/categories',
        categoryFiles=categoryFiles, templatesFolder=root .. '/Scripts',
        listFiles=function() return {} end, resolveTarget=options.resolveTarget})
    for _, path in ipairs(profile.templates) do te:registerTemplate(root .. '/' .. path) end
    te:loadTemplatesFromRegister()
    local catalogFile = root .. '/identity-catalog.lua'
    local catalog = read(catalogFile) and assert(loadfile(catalogFile, 't', {}))() or nil
    local menu = te:generateMenu({catalog=catalog, description=profile.description})
    -- Commit the identity reservation before publishing metadata that uses it.
    writeChanged(catalogFile, catalogSource(menu.catalog))
    writeChanged(root .. '/menu-pages.lua', pagesSource(menu.pages))
    writeChanged(root .. '/mod_settings.ini', menu.aggregate.manifest)
    return te, menu
end

return M
