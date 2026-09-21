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
    local runtime = Lifecycle.new(registry)
    local self = {registry = registry, categories = categories, runtime = runtime}
    function self:registerCategory(...) return categories:registerCategory(...) end
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
        local unsubscribe = settingsApi.subscribe('UE4SSTemplatingEngine', function(event)
            if event.providerId ~= 'UE4SSTemplatingEngine' then return end
            local ok, applied, errors = pcall(function()
                return runtime:commit(event, menu.decode, getContext())
            end)
            if not ok then onResult(nil, applied) else onResult(applied, errors) end
        end)
        assert(type(unsubscribe) == 'function', 'Settings API must return unsubscribe')
        self.unsubscribe = unsubscribe
        return function()
            if self.unsubscribe == unsubscribe then unsubscribe(); self.unsubscribe = nil end
        end
    end
    self:registerTemplates(options.templatesFolder or 'templates')
    return self
end

return M
