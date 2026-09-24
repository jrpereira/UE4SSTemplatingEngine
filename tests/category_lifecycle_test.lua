package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('ket.categories')
local Registry = require('ket.registry')
local Lifecycle = require('ket.lifecycle')

local calls = {}
local deferCategory, failTemplate, failMode = false, false, nil
local categories = Categories.new()
categories:registerCategory('demo', {'feature'})
categories:setCategory('demo.feature', {
    attach=function(self, service, target, settings, previous, template)
        calls[#calls+1]='category:attach:'..template.name
        assert(service == target.service and settings.value == 3)
        if deferCategory then return nil, 'not_ready' end
        local handle = previous or {reference=target.reference}
        handle.mode = settings.mode
        return handle
    end,
    detach=function(self, service, handle, reason)
        calls[#calls+1]='category:detach:'..reason
        assert(handle.reference == service.reference)
        return true
    end,
})
local function template(name)
    return {name=name, category='demo.feature', settings={target='templates',enabled=true},
        attach=function(self, service, target, settings, previous, shared)
            calls[#calls+1]=name..':attach'
            assert(shared and shared.reference == service.reference)
            if failTemplate or (failMode ~= nil and settings.mode == failMode) then
                return nil, 'template failure'
            end
            return previous or {name=name}
        end,
        render=function(self, service, handle, target, reason, shared)
            assert(shared and shared.reference == service.reference)
            return 'applied'
        end,
        detach=function(self, service, handle, reason, shared)
            calls[#calls+1]=name..':detach:'..reason
            assert(shared and shared.reference == service.reference)
            return true
        end}
end
local registry = Registry.new(categories, {execute=function() return {template('A'),template('B')} end})
registry:registerTemplate('demo.lua')
assert(registry:loadTemplatesFromRegister() == 2)
local runtime = Lifecycle.new(registry)
local service = {reference={}}
local context = {services={['demo.feature']=service},targets={['demo.feature']={service=service,
    reference=service.reference}}}
local a,b = registry.templates[1].id,registry.templates[2].id
assert(runtime:apply('demo.feature',a,{value=3},context))
local shared = runtime.categoryHandles['demo.feature'].handle
assert(runtime:render('demo.feature',context,{},'test') == 'applied')
assert(runtime:apply('demo.feature',b,{value=3},context))
assert(runtime.categoryHandles['demo.feature'].handle == shared)
assert(table.concat(calls,',') == 'category:attach:A,A:attach,A:detach:switch,category:attach:B,B:attach')
assert(runtime:apply('demo.feature',nil,{},context))
assert(runtime.categoryHandles['demo.feature'] == nil)
assert(calls[#calls-1] == 'B:detach:none' and calls[#calls] == 'category:detach:none')
deferCategory = true
local deferred, why = runtime:apply('demo.feature', a, {value=3}, context)
assert(deferred and why == 'not_ready' and runtime.categoryHandles['demo.feature'] == nil)
deferCategory = false
failTemplate = true
local attached, errorMessage = runtime:retry('demo.feature', context)
assert(not attached and errorMessage == 'template failure'
    and runtime.categoryHandles['demo.feature'] == nil
    and calls[#calls] == 'category:detach:attach_failed')
failTemplate = false
assert(runtime:apply('demo.feature', a, {value=3,mode=1}, context))
local original = runtime.active['demo.feature'].handle
failMode = 2
local reapplied, why = runtime:apply('demo.feature', a, {value=3,mode=2}, context)
assert(not reapplied and why == 'template failure')
assert(runtime.active['demo.feature'].handle == original
    and runtime.active['demo.feature'].settings.mode == 1
    and runtime.categoryHandles['demo.feature'].handle.mode == 1)
print('category lifecycle: direct hooks, shared handle, switch and cleanup passed')
