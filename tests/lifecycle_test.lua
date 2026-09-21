package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('te.categories')
local Registry = require('te.registry')
local Lifecycle = require('te.lifecycle')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local categories = Categories.new(); categories:registerCategory('player', {'quickslots'})
local calls, failAttach, failDetach, deferAttach = {}, false, false, false
local function template(name)
    return {collection = 'Tests', category = 'player.quickslots', name = name,
        events = name == 'A' and {'GroupSelected'} or {'SlotActivated'},
        actions = {{name = 'Group', slots = 1, type = 'any'}},
        attach = function(self, context, target, spec, previous)
            check(target ~= nil)
            calls[#calls + 1] = self.name .. ':attach'
            if deferAttach then return nil, 'not_ready' end
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
local target = {}
local context = {playerActions = dofile('tests/support/service.lua')({original = 123}),
    target=target,targets={['player.quickslots']=target}}
check(runtime:render('player.quickslots', context, {}, 'created') == 'ignored')
local spec = {value = 7}
check(runtime:apply('player.quickslots', a, spec, context))
local firstHandle = runtime.active['player.quickslots'].handle
check(spec.value == 7)
local id, config = runtime:selection('player.quickslots'); check(id == a and config.value == 7)
config.value = 99; check(select(2, runtime:selection('player.quickslots')).value == 7)
check(runtime:apply('player.quickslots', a, {value = 8}, context))
check(runtime.active['player.quickslots'].handle == firstHandle and firstHandle.original == 123)
failAttach = true
check(not runtime:apply('player.quickslots', a, {value = 9}, context))
check(select(2, runtime:selection('player.quickslots')).value == 8 and firstHandle.value == 8)
failAttach = false; failDetach = true
check(not runtime:apply('player.quickslots', b, {}, context))
check(runtime:selection('player.quickslots') == a)
failDetach = false
check(runtime:apply('player.quickslots', b, {}, context))
check(calls[#calls - 1] == 'A:detach:switch' and calls[#calls] == 'B:attach')
check(context.playerActions.restored == 123)
check(runtime:render('player.quickslots', context, {}, 'created') == 'not_ready')
local before = #calls
check(runtime:render('player.quickslots', context, {ready = true}, 'ready') == 'applied')
check(runtime:apply('player.quickslots', nil, {}, context))
check(runtime:selection('player.quickslots') == nil and calls[#calls] == 'B:detach:none')
before = #calls
check(runtime:detach('player.quickslots', context, 'disable') and #calls == before)
local function decode(values) return {['player.quickslots'] = {id = a, configuration = values}} end
check(runtime:commit({revision = 1, values = {value = 10}}, decode, context))
before = #calls
check(runtime:commit({revision = 1, values = {value = 11}}, decode, context) and #calls == before)
failAttach = true
check(not runtime:commit({revision = 2, values = {value = 12}}, decode, context))
check(runtime.revision == 1 and select(2, runtime:selection('player.quickslots')).value == 10)
failAttach = false
check(runtime:commit({revision = 2, values = {value = 12}}, decode, context))
before = #calls
check(runtime:detach('player.quickslots', nil, 'world_invalidated'))
check(#calls == before and runtime:selection('player.quickslots') == nil)
check(not runtime:apply('player.quickslots', 'missing', {}, context))
failAttach = true
check(not runtime:apply('player.quickslots', a, {}, context) and runtime:selection('player.quickslots') == nil)
failAttach = false; deferAttach = true
local deferred, state = runtime:apply('player.quickslots', a, {value=13}, context)
check(deferred and state == 'not_ready' and runtime.active['player.quickslots'] == nil
    and runtime.pending['player.quickslots'] ~= nil)
check(select(2, runtime:selection('player.quickslots')).value == 13)
check(runtime:render('player.quickslots', context, {}, 'created') == 'ignored')
check(select(2, runtime:retry('player.quickslots', context)) == 'not_ready')
deferAttach = false
check(runtime:retry('player.quickslots', context) and runtime.pending['player.quickslots'] == nil
    and runtime.active['player.quickslots'] ~= nil)
check(runtime:dispatch('player.quickslots','SlotActivated',context,{ready=true})=='ignored')
check(runtime:dispatch('player.quickslots','GroupSelected',context,{ready=true})=='applied')
check(calls[#calls]=='A:render:GroupSelected')
deferAttach=true
check(runtime:detach('player.quickslots',context,'switch'))
check(select(2,runtime:apply('player.quickslots',a,{value=14},context))=='not_ready')
check(runtime:dispatch('player.quickslots','SlotActivated',context,{ready=true})=='ignored')
check(runtime.pending['player.quickslots']~=nil)
deferAttach=false
check(runtime:dispatch('player.quickslots','GroupSelected',context,{ready=true})=='applied')
check(runtime.pending['player.quickslots']==nil and calls[#calls]=='A:render:GroupSelected')
local eventResult,eventWhy=runtime:dispatch('player.quickslots','Unknown',context,{})
check(eventResult==nil and eventWhy:find('unsupported player.quickslots event Unknown',1,true))
print('lifecycle: ' .. checks .. ' checks passed')
