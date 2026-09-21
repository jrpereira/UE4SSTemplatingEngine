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
check(table.concat(categories:list(), ',') == 'menu.controls,menu.fixes,menu.templates,npc.attacks,npc.intent,npc.level,npc.melee,npc.pawn,other.unknown,player.charges,player.compass,player.notifications,player.quickslots,player.self,player.stats,player.wheel')
check(not categories:contains('player') and not categories:contains('npc') and not categories:contains('other'))
check(categories._categories.player.quickslots.visible == 0)
check(categories._categories.player.quickslots.count == 0)
check(type(categories._categories.player.quickslots.templates) == 'table'
    and next(categories._categories.player.quickslots.templates) == nil)
check(categories._categories.npc.intent.visible == 0)
check(categories._categories.npc.attacks.visible == 0)
check(categories._categories.other.unknown.visible == 0)
check(categories._categories.menu.controls.visible == 0
    and categories._categories.menu.controls.count == 0
    and next(categories._categories.menu.controls.templates) == nil)
check(categories._categories.menu.templates.visible == 0
    and categories._categories.menu.templates.count == 0
    and next(categories._categories.menu.templates.templates) == nil)
check(categories._categories.menu.fixes.visible == 0
    and categories._categories.menu.fixes.count == 0
    and next(categories._categories.menu.fixes.templates) == nil)
check(categories:setCategory('player.quickslots', {visible=1}).visible == 1)
check(categories._categories.player.quickslots.visible == 1)
check(categories:setCategory('other.unknown', {visible=1, count=2}).visible == 1)
check(categories._categories.other.unknown.count == 2 and categories:contains('other.unknown'))
rejects(function() categories:setCategory('missing', {visible=1}) end, 'unregistered category')
check(V.template({collection='Tests',name='Unknown',category='other.unknown'}, categories, 'unknown.lua').category == 'other.unknown')
rejects(function() categories:registerCategory('player', {'quickslots'}) end, 'duplicate category')
rejects(function() categories:registerCategory('custom', {'a', 'a'}) end, 'duplicate category')
check(not categories:contains('custom'))
check(V.template({collection='Tests',name='Notice',category='player.notifications'}, categories, 'notice.lua').category == 'player.notifications')
check(V.template({collection='Tests',name='Fixes',category='menu.fixes'},categories,'fixes.lua',true).category=='menu.fixes')
local indicator='/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C'
check(V.template({collection='Tests',name='Attacks',category='npc.attacks',subscribe={{path=indicator,
    events={'created'},contexts={'combat'}}}},categories,'attacks.lua').category=='npc.attacks')
local Events=require('te.event_contracts')
check(Events.active({contexts={'combat'}},{contexts={combat=true}}))
check(not Events.active({contexts={'combat'}},{contexts={'openworld'}}))
rejects(function() V.template({collection='Tests',name='Attacks',category='npc.attacks',subscribe={{path='Bad',
    events={'created'},contexts={'combat'}}}},categories,'attacks.lua') end,'unsupported npc.attacks path Bad')
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
local quickslots = categories._categories.player.quickslots
check(quickslots.count == 2 and #quickslots.templates == 2)
check(quickslots.templates[1] == registry.templates[1].template
    and quickslots.templates[2] == registry.templates[2].template)
check(U.identity(template()) ~= U.identity(template('Second')))
rejects(function() V.flatten({category = 'player.quickslots'}, categories, 'bad.lua') end, 'bad.lua.collection')
rejects(function() V.flatten({collection='Tests',category='player.quickslots',name='Bad',
    actions={{name='Group',slots=1,type='any'}},events={'Unknown'}},categories,'bad.lua') end,
    'unsupported player.quickslots event Unknown')
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
check(#registry.templates == 2 and quickslots.count == 2 and #quickslots.templates == 2
    and not registry.loaded['c.lua'])
sources['d.lua'] = template('Fourth')
check(registry:loadTemplatesFromRegister() == 2 and #registry.templates == 4
    and quickslots.count == 4 and #quickslots.templates == 4)
print('registry: ' .. checks .. ' checks passed')
