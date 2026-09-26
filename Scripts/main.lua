-- _ModCore_Templates Lua entry point.
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCT Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate MCT module')
package.path = scripts .. '/?.lua;' .. package.path
local TemplateDiscovery = require('mc.template_discovery')
assert(type(IterateGameDirectories)=='function', 'UE4SS directory API unavailable')
local function listedCategories()
    local names = assert(loadfile(root .. '/Scripts/categories/mc.lua'))()
    assert(type(names) == 'table', 'invalid category source list')
    local files, seen = {}, {}
    for _, entry in ipairs(names) do
        assert(type(entry)=='string' and entry:match('^[%w_-]+%.lua$'),
            'invalid category filename')
        local path=root .. '/Scripts/categories/' .. entry
        assert(not seen[path], 'duplicate category file: ' .. path)
        seen[path] = true
        files[#files+1] = path
    end
    return files
end
local bootstrap = require('mc.lua_startup').start({
    menuRoot = root,
    categoryFiles = listedCategories(),
    templateFiles = TemplateDiscovery.discover(root, IterateGameDirectories()),
    settingsApi = require('mc.settings_api'),
})
return bootstrap
