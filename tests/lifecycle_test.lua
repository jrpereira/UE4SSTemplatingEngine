package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('te.categories')
local Registry = require('te.registry')
local Lifecycle = require('te.lifecycle')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local categories = Categories.new(); categories:registerCategory('player', {'actions'})
local calls, failAttach, failDetach = {}, false, false
local function template(name)
    return {collection = 'Tests', category = 'player.actions', name = name,
        actions = {{name = 'Group', slots = 1, type = 'any'}},
        attach = function(self, context, spec, previous)
            calls[#calls + 1] = self.name .. ':attach'
            if failAttach then return nil, 'attach failure' end
            local handle = previous or {original = context.original}
            handle.value = spec.value
            spec.value = 'mutated input'
            return handle
        end,
        detach = function(self, context, handle, reason)
            calls[#calls + 1] = self.name .. ':detach:' .. reason
            if failDetach then return false, 'detach failure' end
            context.restored = handle.original
            return true
        end,
        render = function(self, context, handle, target, reason)
            calls[#calls + 1] = self.name .. ':render:' .. reason
            return target.ready and 'applied' or 'not_ready'
        end}
end
local registry = Registry.new(categories, {execute = function() return {template('A'), template('B')} end})
registry:registerTemplate('test.lua'); registry:loadTemplatesFromRegister()
local a, b = registry.templates[1].id, registry.templates[2].id
local runtime = Lifecycle.new(registry)
local context = {original = 123}
check(runtime:render('player.actions', context, {}, 'created') == 'ignored')
local spec = {value = 7}
check(runtime:apply('player.actions', a, spec, context))
local firstHandle = runtime.active['player.actions'].handle
check(spec.value == 7)
local id, config = runtime:selection('player.actions'); check(id == a and config.value == 7)
config.value = 99; check(select(2, runtime:selection('player.actions')).value == 7)
check(runtime:apply('player.actions', a, {value = 8}, context))
check(runtime.active['player.actions'].handle == firstHandle and firstHandle.original == 123)
failAttach = true
check(not runtime:apply('player.actions', a, {value = 9}, context))
check(select(2, runtime:selection('player.actions')).value == 8 and firstHandle.value == 8)
failAttach = false; failDetach = true
check(not runtime:apply('player.actions', b, {}, context))
check(runtime:selection('player.actions') == a)
failDetach = false
check(runtime:apply('player.actions', b, {}, context))
check(calls[#calls - 1] == 'A:detach:switch' and calls[#calls] == 'B:attach')
check(context.restored == 123)
check(runtime:render('player.actions', context, {}, 'created') == 'not_ready')
local before = #calls
check(runtime:render('player.actions', context, {ready = true}, 'ready') == 'applied')
check(runtime:apply('player.actions', nil, {}, context))
check(runtime:selection('player.actions') == nil and calls[#calls] == 'B:detach:none')
before = #calls
check(runtime:detach('player.actions', context, 'disable') and #calls == before)
local function decode(values) return {['player.actions'] = {id = a, configuration = values}} end
check(runtime:commit({revision = 1, values = {value = 10}}, decode, context))
before = #calls
check(runtime:commit({revision = 1, values = {value = 11}}, decode, context) and #calls == before)
failAttach = true
check(not runtime:commit({revision = 2, values = {value = 12}}, decode, context))
check(runtime.revision == 1 and select(2, runtime:selection('player.actions')).value == 10)
failAttach = false
check(runtime:commit({revision = 2, values = {value = 12}}, decode, context))
check(runtime:detach('player.actions', context, 'world_invalidated'))
check(calls[#calls] == 'A:detach:world_invalidated')
check(not runtime:apply('player.actions', 'missing', {}, context))
failAttach = true
check(not runtime:apply('player.actions', a, {}, context) and runtime:selection('player.actions') == nil)
print('lifecycle: ' .. checks .. ' checks passed')
