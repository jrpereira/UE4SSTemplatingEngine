package.path = 'Scripts/?.lua;' .. package.path
local TE = require('te.init')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local template = {collection = 'Integration', category = 'player.quickslots', name = 'Integrated',
    actions = {{name = 'Actions', slots = 2, type = 'any'}}}
local attaches, detached = 0, 0
function template:attach(context, spec, previous)
    attaches = attaches + 1
    check(spec.access == 0)
    return previous or {}
end
function template:detach() detached = detached + 1; return true end
function template:render() return 'applied' end
local executions = 0
local te = TE.new({listFiles = function(folder)
    check(folder == 'templates'); return {'templates/fixture.lua'}
end, execute = function() executions = executions + 1; return template end})
check(#te.registry.files == 1 and #te.registry.templates == 0)
local hook, loads = nil, {}
te:bindInitHook(function(callback) hook = callback end, function(_, count) loads[#loads + 1] = count end)
hook({}); hook({})
check(executions == 1 and loads[1] == 1 and loads[2] == 0)
check(attaches == 0)
local menu = te:generateMenu()
local values = {}; for _, row in ipairs(menu.rows) do values[row.Id] = tonumber(row.Default) end
local selector = menu.selectors['player.quickslots']
values[selector.id] = next(selector.byValue)
local callbacks, unsubscribed, outcomes = {}, 0, {}
local stop = te:subscribeApplied({subscribe = function(provider, fn)
    check(provider == 'UE4SSTemplatingEngine' or provider:match('^UE4SSTemplatingEngine%.[%w_.]+$'))
    callbacks[provider] = fn
    return function() unsubscribed = unsubscribed + 1 end
end}, menu, function() return {playerActions = dofile('tests/support/service.lua')()} end,
function(ok, errors) outcomes[#outcomes + 1] = {ok = ok, errors = errors} end)
local callback = assert(callbacks.UE4SSTemplatingEngine)
check(callbacks['UE4SSTemplatingEngine.player.quickslots'] ~= nil)
check(callbacks['UE4SSTemplatingEngine.player.stats'] ~= nil)
check(attaches == 0) -- Editing values locally has no runtime effect.
callback({providerId = 'SomeoneElse', revision = 1, values = values})
check(attaches == 0)
callback({providerId = 'UE4SSTemplatingEngine', revision = 1, values = values})
check(attaches == 1 and outcomes[1].ok)
callback({providerId = 'UE4SSTemplatingEngine', revision = 1, values = values})
check(attaches == 1)
values[selector.id] = 0
callback({providerId = 'UE4SSTemplatingEngine', revision = 2, values = values})
check(detached == 1 and te.runtime:selection('player.quickslots') == nil)
callback({providerId = 'UE4SSTemplatingEngine', revision = 3, values = {}})
check(not outcomes[#outcomes].ok and te.runtime.revision == 2)
stop(); stop(); check(unsubscribed == #menu.pages + 1)

-- Exercise the actual text loader with a real file and a restricted environment.
local path = 'work/loader-fixture.lua'
local file = assert(io.open(path, 'wb'))
file:write('return {collection="Loader",name="Loaded",category="player.stats",render=function() return token end}')
file:close()
local actual = TE.new({listFiles = function() return {path} end, environment = function() return {token = 17} end})
check(actual:loadTemplatesFromRegister() == 1)
check(actual.registry.templates[1].template.render() == 17)
check(actual.categories._categories.player.stats.count == 1
    and actual.categories._categories.player.stats.templates[1] == actual.registry.templates[1].template)
os.remove(path)
print('integration: ' .. checks .. ' checks passed')
