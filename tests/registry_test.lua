package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('te.categories')
local Registry = require('te.registry')
local V = require('te.validation')
local U = require('te.util')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local function rejects(fn, fragment)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(fragment, 1, true), tostring(err))
    checks = checks + 1
end
local categories = Categories.new()
dofile('categories.lua')(function(...) categories:registerCategory(...) end)
check(table.concat(categories:list(), ',') == 'npc,npc.intent,npc.level,npc.melee,npc.pawn,player,player.charges,player.compass,player.notifications,player.quickslots,player.self,player.stats,player.wheel')
check(categories:contains('player') and categories:contains('npc'))
rejects(function() categories:registerCategory('player', {'quickslots'}) end, 'duplicate category')
rejects(function() categories:registerCategory('other', {'a', 'a'}) end, 'duplicate category')
check(not categories:contains('other'))
check(V.template({collection='Tests',name='Notice',category='player.notifications'}, categories, 'notice.lua').category == 'player.notifications')
check(not categories:contains('player.actions') and not categories:contains('quickslots'))
local function template(name)
    return {collection = 'Tests', name = name or 'First', category = 'player.quickslots',
        actions = {A = {name = 'Alpha', slots = 4, type = 'any'}}}
end
local sources = {['a.lua'] = template(), ['b.lua'] = {{template('Second')}, {}}}
local calls = 0
local registry = Registry.new(categories, {
    execute = function(path) calls = calls + 1; return sources[path] end,
    listFiles = function() return {'b.lua', 'notes.txt', 'a.lua'} end,
})
check(registry:registerTemplates('templates') == 2)
check(not registry:registerTemplate('a.lua'))
check(registry:loadTemplatesFromRegister() == 2 and calls == 2)
check(registry:loadTemplatesFromRegister() == 0 and calls == 2)
check(#registry.templates == 2)
check(U.identity(template()) ~= U.identity(template('Second')))
rejects(function() V.flatten({category = 'player.quickslots'}, categories, 'bad.lua') end, 'bad.lua.collection')
local invalid = template(); invalid.category = 'npc.actions'
rejects(function() V.flatten(invalid, categories, 'bad.lua') end, 'unregistered category')
invalid = template(); invalid.actions = nil
rejects(function() V.flatten({{invalid}}, categories, 'bad.lua') end, 'bad.lua[1][1].actions')
rejects(function() V.flatten({[1] = template(), [3] = template()}, categories, 'bad.lua') end, 'sparse array')
rejects(function() V.flatten({template(), surprise = 1}, categories, 'bad.lua') end, 'dense array')
local cycle = {}; cycle[1] = cycle
rejects(function() V.flatten(cycle, categories, 'bad.lua') end, 'cyclic')
invalid = template(); invalid.actions.A.slots = 0 / 0
rejects(function() V.flatten(invalid, categories, 'bad.lua') end, 'positive integer')
rejects(function() V.orderedGroups(template()) end, 'explicit group order required')
check(V.orderedGroups(template(), {'A'})[1].value.name == 'Alpha')
local declared = template(); declared.actionOrder = {'A'}
check(V.orderedGroups(declared)[1].key == 'A')
rejects(function() V.orderedGroups(declared, {'B'}) end, 'cannot override declared actionOrder')
declared.actionOrder = {'Missing'}
rejects(function() V.template(declared, categories, 'declared', false) end, 'invalid/duplicate group order entry')
rejects(function() V.orderedGroups(template(), {'A', 'A'}) end, 'duplicate')
rejects(function() V.template(template(), categories, 'runtime', true) end, 'runtime.attach')
sources['c.lua'] = template('Third'); sources['d.lua'] = template('First')
registry:registerTemplate('c.lua'); registry:registerTemplate('d.lua')
rejects(function() registry:loadTemplatesFromRegister() end, 'duplicate template identity')
check(#registry.templates == 2 and not registry.loaded['c.lua'])
sources['d.lua'] = template('Fourth')
check(registry:loadTemplatesFromRegister() == 2 and #registry.templates == 4)
print('registry: ' .. checks .. ' checks passed')
