local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate KET Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate KET module')
package.path = scripts .. '/?.lua;' .. package.path
local _, menu = require('ket.menu_boot').prepare(root)
local definitions = {version=1, pages=menu.pages}

assert(type(definitions) == 'table' and definitions.version == 1
    and type(definitions.pages) == 'table', 'invalid KET menu page definitions')

return {
    id = 'ModCoreTemplates.CategoryPages',
    apiVersion = 1,
    install = function(api)
        assert(type(api) == 'table' and type(api.pages) == 'table'
            and type(api.pages.build) == 'function', 'DMM pages API unavailable')
        assert(type(api.choices) == 'table' and type(api.choices.parse) == 'function',
            'DMM choices API unavailable')
        if api.pages._ketCategoryPagesInstalled then return false end
        api.pages._ketCategoryPagesInstalled = true
        local build = api.pages.build
        api.pages.build = function(tree, providers, status, hostApi)
            local generatedIds = {}
            for _, page in ipairs(definitions.pages) do generatedIds[page.id] = true end
            local previousPositions = {}
            for index = #providers, 1, -1 do
                if generatedIds[providers[index].id] then
                    previousPositions[providers[index].id] = index
                    table.remove(providers, index)
                end
            end
            local ids = {}
            for _, provider in ipairs(providers) do ids[provider.id] = true end
            local aggregate
            for _, provider in ipairs(providers) do
                if provider.id == 'ModCoreTemplates' then
                    local ownsPages = true
                    for _, page in ipairs(definitions.pages) do
                        ownsPages = ownsPages and type(page.id) == 'string'
                            and page.id:sub(1, #provider.id + 1) == provider.id .. '.'
                            and ((type(page.category) == 'string') ~= (type(page.module) == 'string'))
                    end
                    if ownsPages then
                        assert(aggregate == nil, 'duplicate KET aggregate provider')
                        aggregate = provider
                    end
                end
            end
            assert(aggregate ~= nil, 'KET aggregate provider unavailable')
            local categoryProviders, moduleProviders = {}, {}
            for _, page in ipairs(definitions.pages) do
                assert(type(page.id) == 'string' and not ids[page.id], 'duplicate KET category provider')
                local choices = api.choices.parse(page.manifest)
                local generated = {
                    id = page.id,
                    name = page.name,
                    author = page.author or 'ModCoreTemplates',
                    version = page.version or '0.0.20',
                    description = page.description or ('Templates and settings for ' .. page.name .. '.'),
                    choices = choices,
                    settingsCount = #choices,
                    path = root .. '/mod_settings.ini',
                    testOnly = false,
                    logoFile = '',
                    logoAsset = '',
                }
                if page.category then
                    generated.mcBrowserLevel, generated.mcBrowserIndent = 4, 20
                    categoryProviders[#categoryProviders + 1] = generated
                else
                    generated._ketModule = assert(page.module, 'generated page needs category or module')
                    moduleProviders[#moduleProviders + 1] = generated
                end
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
            assert(aggregateIndex ~= nil, 'KET aggregate provider lost during ordering')
            for index, provider in ipairs(categoryProviders) do
                table.insert(providers, aggregateIndex + index, provider)
            end
            for _, generated in ipairs(moduleProviders) do
                local wanted, match = generated._ketModule:lower(), nil
                generated._ketModule = nil
                for index, provider in ipairs(providers) do
                    local id, name = tostring(provider.id or ''):lower(), tostring(provider.name or ''):lower()
                    if name == wanted or id == wanted or id == 'detected:ue4ss:' .. wanted then
                        assert(match == nil, 'duplicate module provider: ' .. generated.name)
                        match = index
                    end
                end
                if match and providers[match].noSettings then
                    table.remove(providers, match)
                    table.insert(providers, match, generated)
                elseif match then
                    generated.mcBrowserLevel, generated.mcBrowserIndent = 4, 20
                    table.insert(providers, match + 1, generated)
                elseif previousPositions[generated.id] then
                    table.insert(providers, math.min(previousPositions[generated.id], #providers + 1), generated)
                else
                    providers[#providers + 1] = generated
                end
            end
            return build(tree, providers, status, hostApi)
        end
    end,
}
