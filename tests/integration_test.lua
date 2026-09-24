package.path = 'Scripts/?.lua;' .. package.path
local KET = require('ket.init')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local template = {category = 'player.quickslots', name = 'Integrated',
    settings = {target='templates',enabled=true}}
local attaches, detached, rendered = 0, 0, nil
function template:attach(context, target, spec, previous)
    check(target and target.kind=='switcher')
    attaches = attaches + 1
    check(spec.access == 1)
    return previous or {}
end
function template:detach() detached = detached + 1; return true end
function template:render(_,_,payload,event) rendered={payload=payload,event=event};return 'applied' end
local executions = 0
local switcher = {kind='switcher', GetChildrenCount=function() return 0 end}
local ket = KET.new({listFiles = function(folder)
    check(folder == 'Scripts'); return {'Scripts/fixture.lua'}
end, execute = function() executions = executions + 1; return template end})
check(#ket.registry.files == 1 and #ket.registry.templates == 0)
local hook, loads = nil, {}
ket:bindInitHook(function(callback) hook = callback end, function(_, count) loads[#loads + 1] = count end)
hook({}); hook({})
check(executions == 1 and loads[1] == 1 and loads[2] == 0)
check(attaches == 0)
local menu = ket:generateMenu()
local values = {}; for _, row in ipairs(menu.rows) do values[row.Id] = tonumber(row.Default) end
local selector = menu.selectors['player.quickslots']
values[selector.id] = next(selector.byValue)
local callbacks, unsubscribed, outcomes = {}, 0, {}
local stop = ket:subscribeApplied({subscribe = function(provider, fn)
    check(provider == 'ModCoreTemplates' or provider:match('^ModCoreTemplates%.[%w_.]+$'))
    callbacks[provider] = fn
    return function() unsubscribed = unsubscribed + 1 end
end}, menu, function() return {playerActions = dofile('tests/support/service.lua')(),
    targets={['player.quickslots']=switcher}} end,
function(ok, errors) outcomes[#outcomes + 1] = {ok = ok, errors = errors} end)
local callback = assert(callbacks.ModCoreTemplates)
check(callbacks['ModCoreTemplates.player.quickslots'] ~= nil)
check(callbacks['ModCoreTemplates.player.stats'] == nil)
check(attaches == 0) -- Editing values locally has no runtime effect.
local eventCallbacks,eventStops,eventOutcomes={},0,{}
local stopEvents=ket:subscribeEvents({subscribe=function(category,event,fn)
    check(category=='player.quickslots' and (event.name=='GroupSelected' or event.name=='SlotActivated')
        and event.path==nil)
    eventCallbacks[event.name]=fn
    return function() eventStops=eventStops+1 end
end},function() return {playerActions=dofile('tests/support/service.lua')(),
    targets={['player.quickslots']=switcher}} end,
function(status,detail,category,event)
    eventOutcomes[#eventOutcomes+1]={status=status,detail=detail,category=category,event=event}
end)
eventCallbacks.GroupSelected({group=1})
check(eventOutcomes[#eventOutcomes].status=='ignored')
callback({providerId = 'SomeoneElse', revision = 1, values = values})
check(attaches == 0)
callback({providerId = 'ModCoreTemplates', revision = 1, values = values})
check(attaches == 1 and outcomes[1].ok)
eventCallbacks.GroupSelected({group=2})
check(eventOutcomes[#eventOutcomes].status=='applied' and rendered.event=='GroupSelected'
    and rendered.payload.group==2)
callback({providerId = 'ModCoreTemplates', revision = 1, values = values})
check(attaches == 1)
values[selector.id] = 0
callback({providerId = 'ModCoreTemplates', revision = 2, values = values})
check(detached == 1 and ket.runtime:selection('player.quickslots') == nil)
callback({providerId = 'ModCoreTemplates', revision = 3, values = {}})
check(not outcomes[#outcomes].ok and ket.runtime.revision == 2)
stop(); stop(); check(unsubscribed == #menu.pages + 1)
stopEvents();stopEvents();check(eventStops==2)

-- Exercise the actual text loader with a real file and a restricted environment.
local path = 'work/loader-fixture.lua'
local file = assert(io.open(path, 'wb'))
file:write('return {name="Loaded",category="player.stats",settings={target="templates",enabled=false},render=function() return token end}')
file:close()
local actual = KET.new({listFiles = function() return {path} end, environment = function() return {token = 17} end})
check(actual:loadTemplatesFromRegister() == 1)
check(actual.registry.templates[1].template.render() == 17)
check(actual.categories._categories.player.stats.count == 1
    and actual.categories._categories.player.stats.templates[1] == actual.registry.templates[1].template)
os.remove(path)
print('integration: ' .. checks .. ' checks passed')
