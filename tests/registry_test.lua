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
for _, path in ipairs(require('te.category_files').list('Scripts/categories')) do
    categories:addCategory(assert(loadfile(path))())
end
check(table.concat(categories:list(), ',') == 'menu.controls,menu.fixes,menu.templates,npc.attacks,npc.intent,npc.level,npc.melee,npc.pawn,other.unknown,player.charges,player.compass,player.notifications,player.quickslots,player.self,player.stats,player.wheel')
check(not categories:contains('player') and not categories:contains('npc') and not categories:contains('other'))
check(categories._categories.player.quickslots.visible == 0)
check(categories._categories.player.quickslots.count == 0)
for _, category in ipairs({'quickslots','stats','charges','self','compass','notifications','wheel'}) do
    check(categories._categories.player[category].single == true)
    check(categories._categories.player[category].max == nil)
end
check(type(categories._categories.player.quickslots.templates) == 'table'
    and next(categories._categories.player.quickslots.templates) == nil)
check(categories._categories.npc.intent.visible == 0)
check(categories._categories.npc.intent.single == nil)
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
check(V.template({name='Unknown',category='other.unknown',settings={target='templates',enabled=false}}, categories, 'unknown.lua').category == 'other.unknown')
rejects(function() V.template({name='Missing Settings',category='other.unknown'},
    categories,'missing.lua') end,'settings must be a table')
rejects(function() V.template({name='Missing Target',category='other.unknown',
    settings={enabled=false}},categories,'missing-target.lua') end,'settings.target must be templates or module')
rejects(function() V.template({name='Bad Target',category='other.unknown',
    settings={target='modules',enabled=false}},categories,'bad-target.lua') end,'settings.target must be templates or module')
check(V.template({name='Enabled',category='other.unknown',
    settings={target='templates',enabled=true}},categories,'enabled.lua').settings.enabled == true)
rejects(function() V.template({name='Invalid Enabled',category='other.unknown',
    settings={target='templates',enabled=1}},categories,'enabled.lua') end,'settings.enabled must be boolean')
check(V.template({name='Single',category='other.unknown',single=true,
    settings={target='templates',enabled=false}},categories,'single.lua').single == true)
rejects(function() V.template({name='Invalid Single',category='other.unknown',single=1,
    settings={target='templates',enabled=false}},categories,'single.lua') end,'single: expected boolean or nil')
rejects(function() categories:registerCategory('player', {'quickslots'}) end, 'duplicate category')
rejects(function() categories:registerCategory('custom', {'a', 'a'}) end, 'duplicate category')
check(not categories:contains('custom'))
check(V.template({name='Notice',category='player.notifications',settings={target='templates',enabled=false}}, categories, 'notice.lua').category == 'player.notifications')
check(V.template({name='Fixes',category='menu.fixes',settings={target='templates',enabled=false}},categories,'fixes.lua',true).category=='menu.fixes')
local indicator='/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C'
check(V.template({name='Attacks',category='npc.attacks',settings={target='templates',enabled=false},subscribe={{path=indicator,
    events={'created'},contexts={'combat'}}}},categories,'attacks.lua').category=='npc.attacks')
local Events=require('te.event_contracts')
check(Events.active({contexts={'combat'}},{contexts={combat=true}}))
check(not Events.active({contexts={'combat'}},{contexts={'openworld'}}))
rejects(function() V.template({name='Attacks',category='npc.attacks',settings={target='templates',enabled=false},subscribe={{path='Bad',
    events={'created'},contexts={'combat'}}}},categories,'attacks.lua') end,'unsupported npc.attacks path Bad')
check(not categories:contains('player.actions') and not categories:contains('quickslots'))
-- Keep the following legacy validation cases isolated from the bundled action object.
categories = Categories.new()
categories:registerCategory('player', {'quickslots'})
categories:setCategory('player.quickslots', {single=true})
local function template(name)
    return {name = name or 'First', category = 'player.quickslots',
        settings={target='templates',enabled=false},
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
check(registry.templates[1].single == true and registry.templates[1].template.single == true)
check(U.identity(template()) ~= U.identity(template('Second')))
rejects(function() V.flatten({category = 'player.quickslots'}, categories, 'bad.lua') end, 'bad.lua.name')
rejects(function() V.flatten({category='player.quickslots',name='Bad',
    settings={target='templates',enabled=false},actions={{name='Group',slots=1,type='any'}},events={'Unknown'}},categories,'bad.lua') end,
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
local function modeRegistry(categorySingle, templates)
    local modeCategories=Categories.new()
    modeCategories:registerCategory('custom',{'mode'})
    if categorySingle~=nil then modeCategories:setCategory('custom.mode',{single=categorySingle}) end
    local modeRegistry=Registry.new(modeCategories,{execute=function() return templates end})
    modeRegistry:registerTemplate('mode.lua')
    return modeRegistry
end
local fallback=modeRegistry(true,{{name='Fallback',category='custom.mode',settings={target='templates',enabled=false}}})
check(fallback:loadTemplatesFromRegister()==1 and fallback.templates[1].template.single==true)
local override=modeRegistry(true,{{name='Override',category='custom.mode',single=false,settings={target='templates',enabled=false}}})
check(override:loadTemplatesFromRegister()==1 and override.templates[1].template.single==false)
local conflict=modeRegistry(nil,{
    {name='First mode',category='custom.mode',single=true,settings={target='templates',enabled=false}},
    {name='Second mode',category='custom.mode',single=false,settings={target='templates',enabled=false}},
})
rejects(function() conflict:loadTemplatesFromRegister() end,'templates disagree on single')
sources['c.lua'] = template('Third'); sources['d.lua'] = template('First')
registry:registerTemplate('c.lua'); registry:registerTemplate('d.lua')
rejects(function() registry:loadTemplatesFromRegister() end, 'duplicate template identity')
check(#registry.templates == 2 and quickslots.count == 2 and #quickslots.templates == 2
    and not registry.loaded['c.lua'])
sources['d.lua'] = template('Fourth')
check(registry:loadTemplatesFromRegister() == 2 and #registry.templates == 4
    and quickslots.count == 4 and #quickslots.templates == 4)
local returnCategories = Categories.new()
returnCategories:registerCategory('custom', {'samples'})
local header = {category='custom.samples', settings={target='templates', enabled=false}, tag='shared'}
local headerTemplate = {name='Header single', tag='local'}
local headerArray = {{name='Header array one'}, {name='Header array two'}}
local returns = {
    ['single.lua'] = function()
        return {name='Single', category='custom.samples', settings={target='templates', enabled=false}}
    end,
    ['array.lua'] = function()
        return {
            {name='Array one', category='custom.samples', settings={target='templates', enabled=false}},
            {name='Array two', category='custom.samples', settings={target='templates', enabled=false}},
        }
    end,
    ['header-single.lua'] = function() return header, headerTemplate end,
    ['header-array.lua'] = function() return header, headerArray end,
}
local returnRegistry = Registry.new(returnCategories, {execute=function(path) return returns[path]() end})
for _, path in ipairs({'single.lua', 'array.lua', 'header-single.lua', 'header-array.lua'}) do
    check(returnRegistry:registerTemplate(path))
end
check(returnRegistry:loadTemplatesFromRegister() == 6)
local loaded = returnRegistry.templates
check(loaded[1].template.name == 'Single' and loaded[2].template.name == 'Array one'
    and loaded[3].template.name == 'Array two')
check(loaded[4].template.name == 'Header single' and loaded[4].template.category == header.category)
check(loaded[4].template.tag == 'local' and loaded[5].template.tag == 'shared'
    and loaded[6].template.tag == 'shared')
check(loaded[5].template.settings ~= header.settings
    and loaded[5].template.settings ~= loaded[6].template.settings)
check(headerTemplate.category == nil and headerArray[1].category == nil)
returns['bad-header.lua'] = function() return 'bad', {name='Bad'} end
returnRegistry:registerTemplate('bad-header.lua')
rejects(function() returnRegistry:loadTemplatesFromRegister() end, 'expected header table')
print('registry: ' .. checks .. ' checks passed')
