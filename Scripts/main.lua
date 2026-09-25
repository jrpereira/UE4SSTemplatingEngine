-- _ModCore_Templates Lua entry point.
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCT Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate MCT module')
package.path = scripts .. '/?.lua;' .. package.path
local function listed(directory)
    local names = assert(loadfile(root .. '/ModCore/' .. directory .. '/index.lua'))()
    assert(type(names) == 'table', 'invalid ' .. directory .. ' source list')
    local files, seen = {}, {}
    for _, name in ipairs(names) do
        assert(type(name) == 'string' and name:match('^[%w_-]+%.lua$') and not seen[name],
            'invalid or duplicate ' .. directory .. ' filename')
        seen[name] = true
        files[#files+1] = root .. '/ModCore/' .. directory .. '/' .. name
    end
    return files
end
local bootstrap = require('mct.lua_startup').start({
    menuRoot = root,
    categoryFiles = listed('categories'),
    templateFiles = listed('templates'),
    settingsApi = require('mct.settings_api'),
})
return bootstrap
