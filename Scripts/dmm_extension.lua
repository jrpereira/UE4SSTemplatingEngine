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
        if api.pages._teCategoryPagesInstalled then return false end
        api.pages._teCategoryPagesInstalled = true
        local build = api.pages.build
        api.pages.build = function(tree, providers, status, hostApi)
            local generatedIds = {}
            for _, page in ipairs(definitions.pages) do generatedIds[page.id] = true end
            for index = #providers, 1, -1 do
                if generatedIds[providers[index].id] then table.remove(providers, index) end
            end
            local ids = {}
            for _, provider in ipairs(providers) do ids[provider.id] = true end
            local aggregate
            for _, provider in ipairs(providers) do
                if provider.name == 'Templates' then
                    local ownsPages = true
                    for _, page in ipairs(definitions.pages) do
                        ownsPages = ownsPages and type(page.id) == 'string'
                            and page.id:sub(1, #provider.id + 1) == provider.id .. '.'
                            and ((type(page.category) == 'string') ~= (type(page.module) == 'string'))
                    end
                    if ownsPages then
                        assert(aggregate == nil, 'duplicate TE aggregate provider')
                        aggregate = provider
                    end
                end
            end
            assert(aggregate ~= nil, 'TE aggregate provider unavailable')
            local categoryProviders = {}
            for _, page in ipairs(definitions.pages) do
                assert(type(page.id) == 'string' and not ids[page.id], 'duplicate TE category provider')
                local choices = api.choices.parse(page.manifest)
                categoryProviders[#categoryProviders + 1] = {
                    id = page.id,
                    name = page.name,
                    author = page.author or 'Templating Engine',
                    version = page.version or '0.0.18',
                    description = page.description or ('Templates and settings for ' .. page.name .. '.'),
                    choices = choices,
                    settingsCount = #choices,
                    path = root .. '/mod_settings.ini',
                    testOnly = false,
                    logoFile = '',
                    logoAsset = '',
                    ammBrowserLevel = 4,
                    ammBrowserIndent = 20,
                }
                ids[page.id] = true
            end
            table.sort(providers, function(a, b)
                if a.testOnly ~= b.testOnly then return not a.testOnly end
                local an, bn = a.name:lower(), b.name:lower()
                if an ~= bn then return an < bn end
                return a.id < b.id
            end)
            local aggregateIndex
            for index, provider in ipairs(providers) do
                if provider == aggregate then aggregateIndex = index; break end
            end
            assert(aggregateIndex ~= nil, 'TE aggregate provider lost during ordering')
            for index, provider in ipairs(categoryProviders) do
                table.insert(providers, aggregateIndex + index, provider)
            end
            return build(tree, providers, status, hostApi)
        end
    end,
}
