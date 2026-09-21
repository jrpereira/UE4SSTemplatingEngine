local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate TE Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate TE module')
local definitions = assert(loadfile(root .. '/menu-pages.lua', 't', {}))()

assert(type(definitions) == 'table' and definitions.version == 1
    and type(definitions.pages) == 'table', 'invalid TE menu page definitions')

return {
    id = 'UE4SSTemplatingEngine.CategoryPages',
    apiVersion = 1,
    install = function(api)
        assert(type(api) == 'table' and type(api.pages) == 'table'
            and type(api.pages.build) == 'function', 'DMM pages API unavailable')
        assert(type(api.choices) == 'table' and type(api.choices.parse) == 'function',
            'DMM choices API unavailable')
        local build = api.pages.build
        api.pages.build = function(tree, providers, status, hostApi)
            local ids = {}
            for _, provider in ipairs(providers) do ids[provider.id] = true end
            for _, page in ipairs(definitions.pages) do
                assert(type(page.id) == 'string' and not ids[page.id], 'duplicate TE category provider')
                local choices = api.choices.parse(page.manifest)
                providers[#providers + 1] = {
                    id = page.id,
                    name = page.name,
                    author = page.author or 'Templating Engine',
                    version = page.version or '0.0.17',
                    description = page.description or ('Templates and settings for ' .. page.name .. '.'),
                    choices = choices,
                    settingsCount = #choices,
                    path = root .. '/mod_settings.ini',
                    testOnly = false,
                    logoFile = '',
                    logoAsset = '',
                }
                ids[page.id] = true
            end
            table.sort(providers, function(a, b)
                if a.testOnly ~= b.testOnly then return not a.testOnly end
                local an, bn = a.name:lower(), b.name:lower()
                if an ~= bn then return an < bn end
                return a.id < b.id
            end)
            return build(tree, providers, status, hostApi)
        end
    end,
}
