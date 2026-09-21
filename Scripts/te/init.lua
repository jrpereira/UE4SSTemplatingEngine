local Categories = require('te.categories')
local Registry = require('te.registry')
local Lifecycle = require('te.lifecycle')
local Menu = require('te.menu')
local M = {}

-- Host supplies discovery, native scheduling/readiness and configuration storage.
-- This module deliberately performs no implicit UE4SS hook registration.
function M.new(options)
    assert(type(options) == 'table', 'host options required')
    local categories = Categories.new()
    local core = options.coreCategories or assert(loadfile(options.categoriesPath or 'categories.lua', 't'))()
    core(function(...) categories:registerCategory(...) end)
    local registry = Registry.new(categories, options)
    local runtime = Lifecycle.new(registry, {resolveService = options.resolveService})
    local self = {registry = registry, categories = categories, runtime = runtime}
    function self:registerCategory(...) return categories:registerCategory(...) end
    function self:setCategory(...) return categories:setCategory(...) end
    function self:registerTemplate(...) return registry:registerTemplate(...) end
    function self:registerTemplates(...) return registry:registerTemplates(...) end
    function self:loadTemplatesFromRegister() return registry:loadTemplatesFromRegister() end
    function self:generateMenu(settings) return Menu.generate(registry, settings) end
    function self:bindInitHook(registerHook, onLoaded)
        assert(not self.initHookBound, 'Init hook already bound')
        assert(type(registerHook) == 'function', 'hook registration adapter required')
        registerHook(function(context)
            local count = self:loadTemplatesFromRegister()
            if onLoaded then onLoaded(context, count) end
        end)
        self.initHookBound = true
    end
    function self:subscribeApplied(settingsApi, menu, getContext, onResult)
        assert(not self.unsubscribe, 'Apply subscription already active')
        assert(type(getContext) == 'function' and type(onResult) == 'function', 'context and result handlers required')
        local unsubscribers, revisions, sequence = {}, {}, 0
        local providers = menu.providers or {UE4SSTemplatingEngine={id='UE4SSTemplatingEngine',decode=menu.decode}}
        local ids = {}; for id in pairs(providers) do ids[#ids + 1] = id end; table.sort(ids)
        for _, providerId in ipairs(ids) do
            local provider = providers[providerId]
            local unsubscribe = settingsApi.subscribe(providerId, function(event)
                if event.providerId ~= providerId then return end
                if event.revision <= (revisions[providerId] or 0) then return end
                revisions[providerId] = event.revision
                sequence = sequence + 1
                local committed = {providerId=providerId, revision=sequence,
                    values=event.values, changes=event.changes}
                local ok, applied, errors = pcall(function()
                    return runtime:commit(committed, provider.decode, getContext())
                end)
                if not ok then onResult(nil, applied) else onResult(applied, errors) end
            end)
            assert(type(unsubscribe) == 'function', 'Settings API must return unsubscribe')
            unsubscribers[#unsubscribers + 1] = unsubscribe
        end
        local active = true
        local function unsubscribe()
            if not active then return end
            active = false
            for _, stop in ipairs(unsubscribers) do stop() end
        end
        self.unsubscribe = unsubscribe
        return function()
            if self.unsubscribe == unsubscribe then unsubscribe(); self.unsubscribe = nil end
        end
    end
    self:registerTemplates(options.templatesFolder or 'templates')
    return self
end

return M
