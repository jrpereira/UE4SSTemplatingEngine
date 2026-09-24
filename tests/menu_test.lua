package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('ket.categories')
local Registry = require('ket.registry')
local Menu = require('ket.menu')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local function rejects(fn, fragment)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(fragment, 1, true), tostring(err))
    checks = checks + 1
end
local dmmPath = assert(os.getenv('KET_DMM_CHOICES'), 'KET_DMM_CHOICES required for actual parser integration tests')
local mcPath = assert(os.getenv('KET_AMM_PRESENTATION'), 'KET_AMM_PRESENTATION required for actual decorator tests')
local Choices, Presentation = dofile(dmmPath), dofile(mcPath)
local function fixture(last, name)
    return {name = name or 'Quickslots++', category = 'player.quickslots',
        settings={target='templates',enabled=false}, actions = {
        {name = 'Consumables', slots = 4, type = 'consumables'},
        {name = 'Abilities', slots = 4, type = 'abilities'},
        {name = 'Extra', slots = last, type = 'any'},
    }}
end
local function registryFor(templates)
    local categories = Categories.new()
    categories:registerCategory('player', {'quickslots', 'stats'})
    categories:setCategory('player.quickslots', {single=true})
    categories:setCategory('player.stats', {single=true})
    local registry = Registry.new(categories, {execute = function() return templates end})
    registry:registerTemplate('fixture.lua'); registry:loadTemplatesFromRegister()
    return registry
end
local function modelFor(result, category)
    local provider = category and assert(result.pageByCategory[category]) or result.aggregate
    local parsed = Choices.parse(provider.manifest)
    Presentation.parse(provider.manifest, parsed)
    local model = Choices.open({id = 'KET-test', choices = parsed, testOnly = true})
    assert(not model.error, model.error)
    local indices = {}; for i, item in ipairs(parsed) do indices[item.id] = i end
    return model, indices
end
local firstResult
for _, last in ipairs({2, 5}) do
    local result = Menu.generate(registryFor(fixture(last)))
    firstResult = firstResult or result
    check(#result.aggregate.rows == 1 and #result.pages == 1
        and result.pageByCategory['player.quickslots'].category == 'player.quickslots'
        and #result.pageByCategory['player.quickslots'].rows == #result.rows
        and result.pageByCategory['player.stats'] == nil)
    check(result.aggregate.rows[1].Label == 'Quickslots' and result.aggregate.rows[1].Group == 'Player'
        and result.aggregate.rows[1].mcType == nil
        and result.aggregate.rows[1].mcTabsWidth == nil)
    local quickslotsManifest = result.pageByCategory['player.quickslots'].manifest
    check(not result.manifest:find('Deco', 1, true) and not quickslotsManifest:find('Deco', 1, true))
    for _, key in ipairs({'mcType','mcLevel','mcHeading','mcLabelWhen','mcLabels'}) do
        check(quickslotsManifest:find(key, 1, true), 'missing AMM metadata key '..key)
    end
    local model, indices = modelFor(result, 'player.quickslots')
    local rowsById = {}; for _, item in ipairs(result.rows) do rowsById[item.Id] = item end
    local selector = result.selectors['player.quickslots']
    check(result.aggregate.rows[1].mcLevel == 1
        and result.pageByCategory['player.quickslots'].rows[1].mcLevel == 1)
    check(model.items[indices[selector.id]].mcHeader
        and not model.items[indices[selector.id]].mcTabs)
    local selected = next(selector.byValue)
    local definition = result.definitions['player.quickslots'][selected]
    local scopePrefix = 'KET_'
    check(definition.scope == nil)
    check(selector.id == 'KET_Template' and definition.access == scopePrefix .. 'AccessMethod'
        and definition.firstDefault == nil and rowsById.KET_FirstGroupDefault == nil)
    check(definition.groups['1'].key == scopePrefix .. 'Group1'
        and definition.groups['2'].key == scopePrefix .. 'Group2')
    check(rowsById.KET_Group1Mode.PresetValues == '0|2|-1'
        and rowsById.KET_Group1Mode.PresetLabels == 'Tap|Hold|Default')
    check(rowsById.KET_Group2Mode.PresetValues == '0|2'
        and rowsById.KET_Group2Mode.PresetLabels == 'Tap|Hold')
    for slot = 1, 4 do
        check(definition.direct['1'][slot].key == scopePrefix .. 'Slot' .. slot
            and definition.direct['1'][slot].mode == scopePrefix .. 'Slot' .. slot .. 'Mode')
        check(definition.direct['2'][slot].key == scopePrefix .. 'Slot' .. (slot + 4)
            and definition.direct['2'][slot].mode == scopePrefix .. 'Slot' .. (slot + 4) .. 'Mode')
    end
    for _, slots in pairs(definition.direct) do
        for _, pair in ipairs(slots) do
            check(rowsById[pair.key].Pair == nil and rowsById[pair.key].mcType == 'keybind')
            check(rowsById[pair.mode].Pair == pair.key and rowsById[pair.mode].mcType == 'tab')
            check(rowsById[pair.mode].Label == rowsById[pair.key].Label)
        end
    end
    check(model.items[indices[selector.id]].default==0 and definition.enabled==false)
    check(model.items[indices[definition.access]].default == 1
        and model.items[indices[definition.access]].label == 'Input Method'
        and model.items[indices[definition.access]].mcTabsWidth == 440)
    check(model.items[indices[definition.groups['2'].key]].default == 164)
    for slot = 1, 4 do
        check(model.items[indices[definition.direct['1'][slot].key]].default == 48 + slot)
        check(model.items[indices[definition.direct['1'][slot].mode]].default == 0)
        check(model.items[indices[definition.direct['2'][slot].key]].default == 48 + slot)
        check(model.items[indices[definition.direct['2'][slot].mode]].default == 1)
    end
    check(model.items[indices[selector.id]].mcFont == 1)
    check(model.items[indices[definition.access]].mcFont == 2)
    check(model.items[indices[selector.id]].mcGroup.heading == false)
    check(model.items[indices[definition.access]].mcGroup.heading == false)
    local activationGroup = model.items[indices[definition.groups['1'].key]].group
    local blocks, previous = 0, nil
    for _, item in ipairs(model.items) do
        if item.group == activationGroup and previous ~= activationGroup then blocks = blocks + 1 end
        previous = item.group
    end
    check(blocks == 1)
    check(model.items[indices[definition.direct['1'][1].key]].label == 'Slot 1')
    check(model.items[indices[definition.direct['2'][1].key]].label == 'Slot 1')
    check(model.items[indices[definition.shared[1].key]].label == 'Slot 1')
    local function visibleKeys()
        local visibility, count = model:visibility(), 0
        for i, item in ipairs(model.items) do
            if visibility[i] and item.kind == 'slider' then count = count + 1 end
            if item.kind == 'slider' then
                check(item.mcPairIndex ~= nil and visibility[i] == visibility[item.mcPairIndex])
            end
        end
        return count
    end
    check(visibleKeys() == 0)
    model:set(indices[selector.id], selected)
    check(visibleKeys() == 3 + math.max(4, last))
    local visible = model:visibility()
    check(visible[indices[definition.groups['1'].key]])
    check(visible[indices[definition.groups['2'].key]])
    model:set(indices[definition.access], 0)
    check(visibleKeys() == 8 + last)
    for _, slots in pairs(definition.direct) do
        check(model.items[indices[slots[1].key]].mcGroup.font == 5)
    end
    model:set(indices[definition.access], 1)
    check(visibleKeys() == 3 + math.max(4, last))
    local values = {}; for i, item in ipairs(model.items) do values[item.id] = model.pending[i] end
    local decoded = result.decode(values)['player.quickslots']
    check(decoded.id == selector.byValue[selected] and not decoded.settings.firstGroupDefault)
    check(#decoded.settings.shared == math.max(4, last))
    values[selector.id] = 0
    check(result.decode(values)['player.quickslots'].id == nil)
    values[definition.shared[1].key] = 255
    rejects(function() result.decode(values) end, 'invalid key')
end
local baseRegistry = registryFor(fixture(2))
local initial = Menu.generate(baseRegistry)
local more = Menu.generate(registryFor({fixture(2, 'AAA'), fixture(2)}), {catalog = initial.catalog})
local originalId = baseRegistry.templates[1].id
local function valueFor(result, identity)
    for value, id in pairs(result.selectors['player.quickslots'].byValue) do if id == identity then return value end end
end
check(valueFor(initial, originalId) == valueFor(more, originalId))
local originalDef = initial.definitions['player.quickslots'][valueFor(initial, originalId)]
local moreDef = more.definitions['player.quickslots'][valueFor(more, originalId)]
check(originalDef.shared[1].key == moreDef.shared[1].key)
check(initial.catalog.next < more.catalog.next)
local removed = Menu.generate(registryFor(fixture(2, 'AAA')), {catalog = more.catalog})
local restored = Menu.generate(baseRegistry, {catalog = removed.catalog})
check(valueFor(initial, originalId) == valueFor(restored, originalId))
local many = {}
for i = 1, 8 do many[i] = {category = 'player.stats', name = 'Stats ' .. i,
    settings={target='templates',enabled=false}} end
local ordinary = Menu.generate(registryFor(many))
local model, indices = modelFor(ordinary, 'player.stats')
check(not model.items[indices[ordinary.selectors['player.stats'].id]].mcTabs
    and ordinary.aggregate.rows[1].mcTabsWidth == nil)
local overrideFixture=fixture(2,'Override');overrideFixture.single=false
local overrideMenu=Menu.generate(registryFor(overrideFixture))
check(overrideMenu.selectors['player.quickslots']==nil
    and #overrideMenu.multiSelectors['player.quickslots']==1)
local multiCategories = Categories.new()
multiCategories:registerCategory('other', {'unknown'})
local multiRegistry = Registry.new(multiCategories, {execute=function() return {
    {name='First Attack',category='other.unknown',settings={target='templates',enabled=false}},
    {name='Second Attack',category='other.unknown',settings={target='templates',enabled=false}},
    {name='Third Attack',category='other.unknown',settings={target='templates',enabled=false}},
} end})
multiRegistry:registerTemplate('multi.lua'); multiRegistry:loadTemplatesFromRegister()
local multi = Menu.generate(multiRegistry)
check(multi.selectors['other.unknown'] == nil and #multi.multiSelectors['other.unknown'] == 3)
local multiById = {}
for _, item in ipairs(multi.multiSelectors['other.unknown']) do multiById[item.id] = item end
check(multiById.KET_CategorySeparator_FirstAttack ~= nil
    and multiById.KET_CategorySeparator_SecondAttack ~= nil
    and multiById.KET_CategorySeparator_ThirdAttack ~= nil)
local multiModel, multiIndices = modelFor(multi, 'other.unknown')
check(multiModel.items[multiIndices['KET_CategorySeparator_FirstAttack']].label == 'First Attack')
local multiValues = {}; for i, item in ipairs(multiModel.items) do multiValues[item.id] = multiModel.pending[i] end
check(#multi.decode(multiValues)['other.unknown'] == 0)
multiValues.KET_CategorySeparator_FirstAttack = 1
local activeMulti = multi.decode(multiValues)['other.unknown']
check(#activeMulti == 1 and activeMulti[1].id == multiById.KET_CategorySeparator_FirstAttack.definition.id)
local empty = Menu.generate(registryFor({}))
check(#empty.rows == 0 and #empty.pages == 0 and #empty.warnings == 2
    and next(empty.pageByCategory) == nil and next(empty.selectors) == nil)
local groupedCategories = Categories.new()
groupedCategories:registerCategory('player', {'quickslots', 'stats', 'charges'})
for _, category in ipairs({'quickslots','stats','charges'}) do
    groupedCategories:setCategory('player.' .. category, {single=true})
end
groupedCategories:registerCategory('menu', {'controls', 'fixes', 'templates'})
local groupedTemplates = {
    fixture(2),
    {name='Stats+',category='player.stats',settings={target='templates',enabled=false}},
    {name='Menu Fix',category='menu.fixes',settings={target='templates',enabled=false}},
}
local groupedRegistry = Registry.new(groupedCategories, {execute=function() return groupedTemplates end})
groupedRegistry:registerTemplate('grouped.lua'); groupedRegistry:loadTemplatesFromRegister()
local grouped = Menu.generate(groupedRegistry)
check(#grouped.aggregate.rows == 3 and #grouped.pages == 3)
check(grouped.aggregate.rows[1]._category == 'menu.fixes'
    and grouped.aggregate.rows[1].Id == 'KET_CategorySeparator_MenuFix'
    and grouped.aggregate.rows[1].Label == 'Menu Fix' and grouped.aggregate.rows[1].Group == 'Menu'
    and grouped.aggregate.rows[1].mcTabsWidth == 440)
check(grouped.aggregate.rows[2]._category == 'player.quickslots'
    and grouped.aggregate.rows[2].Label == 'Quickslots' and grouped.aggregate.rows[2].Group == 'Player'
    and grouped.aggregate.rows[2].mcLevel == 1
    and grouped.aggregate.rows[2].mcType == nil
    and grouped.aggregate.rows[2].mcTabsWidth == nil)
check(grouped.aggregate.rows[3]._category == 'player.stats'
    and grouped.aggregate.rows[3].Label == 'Stats' and grouped.aggregate.rows[3].Group == 'Player'
    and grouped.aggregate.rows[3].mcTabsWidth == 440)
check(grouped.pageByCategory['menu.controls'] == nil and grouped.pageByCategory['menu.templates'] == nil
    and grouped.pageByCategory['player.charges'] == nil)
check(grouped.manifest:find('[Category.Menu]', 1, true)
    and grouped.manifest:find('[Category.Player]', 1, true)
    and grouped.manifest:find('mcTabsWidth=440', 1, true)
    and not grouped.manifest:find('[Category.Templates]', 1, true))
local groupedModel = modelFor(grouped)
check(groupedModel.items[1].group == 'Menu' and groupedModel.items[1].mcGroup.heading
    and groupedModel.items[2].group == 'Player' and groupedModel.items[2].mcGroup.heading
    and groupedModel.items[3].group == 'Player' and groupedModel.items[3].mcGroup.heading)
local routedCategories = Categories.new()
routedCategories:registerCategory('player', {'quickslots'})
routedCategories:setCategory('player.quickslots', {single=true})
routedCategories:registerCategory('npc', {'attacks'})
local routedTemplates = {}
local function routedQuick(module, number)
    local item=fixture(1, module .. ' Quickslots ' .. number)
    item.settings.target = 'module'
    return item
end
local function routedAttack(module, number)
    return {name=module..' Attack '..number,category='npc.attacks',
        settings={target='module',enabled=false},subscribe={{
            path='/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C',
            events={'created'},contexts={'combat'}}}}
end
routedTemplates[#routedTemplates+1]=routedQuick('Module One',1)
for i=1,2 do routedTemplates[#routedTemplates+1]=routedAttack('Module One',i) end
for i=1,4 do routedTemplates[#routedTemplates+1]=routedQuick('Other Modules',i) end
for i=1,4 do routedTemplates[#routedTemplates+1]=routedAttack('Other Modules',i) end
local routedRegistry=Registry.new(routedCategories,{execute=function()return routedTemplates end})
routedRegistry:registerTemplate('ExampleModule/Scripts/routed.lua');routedRegistry:loadTemplatesFromRegister()
local routed=Menu.generate(routedRegistry)
check(#routed.aggregate.rows==7 and #routed.pages==1 and next(routed.pageByCategory)==nil)
check(#routed.multiSelectors['npc.attacks']==6)
local routedSelector=routed.selectors['player.quickslots']
local routedSelectorRow
for _,item in ipairs(routed.aggregate.rows) do if item.Id==routedSelector.id then routedSelectorRow=item end end
local choices=0 for _ in routedSelectorRow.PresetValues:gmatch('[^|]+') do choices=choices+1 end
check(choices==6)
local quickslots=assert(routed.pageByModule.ExampleModule)
check(quickslots.name=='ExampleModule' and quickslots.module=='ExampleModule')
local controls, details=0, 0
for _,item in ipairs(quickslots.rows) do
    if item._control then controls=controls+1
    elseif not item._routeHidden then details=details+1 end
end
check(controls==7 and details>0)
local legacyRegistry=Registry.new(routedCategories,{execute=function()
    return routedQuick('Module One',1)
end})
legacyRegistry:registerTemplate('ExampleModule/templates/routed.lua')
legacyRegistry:loadTemplatesFromRegister()
local legacy=Menu.generate(legacyRegistry,{catalog=routed.catalog})
check(legacy.pageByModule.ExampleModule~=nil)
local migratedRegistry=Registry.new(routedCategories,{execute=function()
    return routedQuick('Module One',1)
end})
migratedRegistry:registerTemplate('ExampleModule/Scripts/routed.lua')
migratedRegistry:loadTemplatesFromRegister()
local migrated=Menu.generate(migratedRegistry,{catalog=routed.catalog})
check(migrated.pageByModule.ExampleModule~=nil
    and migrated.selectors['player.quickslots'].id==legacy.selectors['player.quickslots'].id)
local nestedRegistry=Registry.new(routedCategories,{execute=function()
    return routedQuick('Module One',1)
end})
nestedRegistry:registerTemplate('ExampleModule/Scripts/templates/main.lua')
nestedRegistry:loadTemplatesFromRegister()
local nested=Menu.generate(nestedRegistry,{catalog=routed.catalog})
check(nested.pageByModule.ExampleModule~=nil
    and nested.selectors['player.quickslots'].id==legacy.selectors['player.quickslots'].id)
local bad = fixture(2); bad.name = 'Injected\n[Setting.Bad]'
rejects(function() Menu.generate(registryFor(bad)) end, 'unsupported separators')
bad = fixture(2); bad.actions = {Only = bad.actions[1]}
rejects(function() Menu.generate(registryFor(bad)) end, 'explicit group order required')
local mappedRegistry = registryFor(bad)
check(#Menu.generate(mappedRegistry, {groupOrders = {[mappedRegistry.templates[1].id] = {'Only'}}}).rows > 0)
rejects(function() Menu.generate(registryFor(fixture(125))) end, '256 settings')
rejects(function() Menu.generate(baseRegistry, {catalog = {version = 1, next = 3, entries = {a = 1, b = 1}}}) end, 'invalid catalog entry')
local tooMany = {}
for i = 1, 64 do tooMany[i] = {category = 'player.stats', name = 'Stats ' .. i,
    settings={target='templates',enabled=false}} end
rejects(function() Menu.generate(registryFor(tooMany)) end, '63 templates')
local tooLarge = fixture(2); tooLarge.actions = {}
for i = 1, 25 do
    tooLarge.actions[i] = {name = string.rep('X', 4000) .. i, slots = 1, type = 'any'}
end
rejects(function() Menu.generate(registryFor(tooLarge)) end, '256 KiB')
local file = assert(io.open('outputs/example-mod_settings.ini', 'wb'))
file:write(firstResult.manifest); file:close()
print('menu: ' .. checks .. ' checks passed using actual DMM/AMM parsers')
