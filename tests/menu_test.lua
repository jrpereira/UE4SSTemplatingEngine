package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('te.categories')
local Registry = require('te.registry')
local Menu = require('te.menu')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local function rejects(fn, fragment)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(fragment, 1, true), tostring(err))
    checks = checks + 1
end
local dmmPath = assert(os.getenv('TE_DMM_CHOICES'), 'TE_DMM_CHOICES required for actual parser integration tests')
local ammPath = assert(os.getenv('TE_AMM_PRESENTATION'), 'TE_AMM_PRESENTATION required for actual decorator tests')
local Choices, Presentation = dofile(dmmPath), dofile(ammPath)
local function fixture(last, name)
    return {collection = 'Tests', name = name or 'Quickslots++', category = 'player.quickslots', actions = {
        {name = 'Consumables', slots = 4, type = 'consumables'},
        {name = 'Abilities', slots = 4, type = 'abilities'},
        {name = 'Extra', slots = last, type = 'any'},
    }}
end
local function registryFor(templates)
    local categories = Categories.new()
    categories:registerCategory('player', {'quickslots', 'stats'})
    local registry = Registry.new(categories, {execute = function() return templates end})
    registry:registerTemplate('fixture.lua'); registry:loadTemplatesFromRegister()
    return registry
end
local function modelFor(result)
    local parsed = Choices.parse(result.manifest)
    Presentation.parse(result.manifest, parsed)
    local model = Choices.open({id = 'TE-test', choices = parsed, testOnly = true})
    assert(not model.error, model.error)
    local indices = {}; for i, item in ipairs(parsed) do indices[item.id] = i end
    return model, indices
end
local firstResult
for _, last in ipairs({2, 5}) do
    local result = Menu.generate(registryFor(fixture(last)))
    firstResult = firstResult or result
    local model, indices = modelFor(result)
    local selector = result.selectors['player.quickslots']
    local selected = next(selector.byValue)
    local definition = result.definitions['player.quickslots'][selected]
    check(model.items[indices[selector.id]].ammFont == 2)
    check(model.items[indices[definition.access]].ammFont == 2)
    check(model.items[indices[selector.id]].ammGroup.heading == false)
    check(model.items[indices[definition.access]].ammGroup.heading == false)
    local activationGroup = model.items[indices[definition.groups['1'].key]].group
    local blocks, previous = 0, nil
    for _, item in ipairs(model.items) do
        if item.group == activationGroup and previous ~= activationGroup then blocks = blocks + 1 end
        previous = item.group
    end
    check(blocks == 1)
    check(model.items[indices[definition.direct['1'][1].key]].label == 'Slot 1 (consumables)')
    check(model.items[indices[definition.direct['2'][1].key]].label == 'Slot 5 (abilities)')
    check(model.items[indices[definition.shared[1].key]].label == 'Slot 1')
    local function visibleKeys()
        local visibility, count = model:visibility(), 0
        for i, item in ipairs(model.items) do
            if visibility[i] and item.kind == 'slider' then count = count + 1 end
            if item.kind == 'slider' then
                check(item.ammPairIndex ~= nil and visibility[i] == visibility[item.ammPairIndex])
            end
        end
        return count
    end
    check(visibleKeys() == 0)
    model:set(indices[selector.id], selected)
    check(visibleKeys() == 8 + last)
    for _, slots in pairs(definition.direct) do
        check(model.items[indices[slots[1].key]].ammGroup.font == 5)
    end
    model:set(indices[definition.access], 1)
    check(visibleKeys() == 3 + math.max(4, last))
    model:set(indices[definition.firstDefault], 1)
    check(visibleKeys() == 2 + math.max(4, last))
    local visible = model:visibility()
    check(not visible[indices[definition.groups['1'].key]])
    check(visible[indices[definition.groups['2'].key]])
    local values = {}; for i, item in ipairs(model.items) do values[item.id] = model.pending[i] end
    local decoded = result.decode(values)['player.quickslots']
    check(decoded.id == selector.byValue[selected] and decoded.configuration.firstGroupDefault)
    check(#decoded.configuration.shared == math.max(4, last))
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
for i = 1, 8 do many[i] = {collection = 'Tests', category = 'player.stats', name = 'Stats ' .. i} end
local ordinary = Menu.generate(registryFor(many))
local model, indices = modelFor(ordinary)
check(not model.items[indices[ordinary.selectors['player.stats'].id]].ammTabs)
local empty = Menu.generate(registryFor({}))
check(#empty.rows == 0 and #empty.warnings == 3)
local bad = fixture(2); bad.name = 'Injected\n[Setting.Bad]'
rejects(function() Menu.generate(registryFor(bad)) end, 'unsupported separators')
bad = fixture(2); bad.actions = {Only = bad.actions[1]}
rejects(function() Menu.generate(registryFor(bad)) end, 'explicit group order required')
local mappedRegistry = registryFor(bad)
check(#Menu.generate(mappedRegistry, {groupOrders = {[mappedRegistry.templates[1].id] = {'Only'}}}).rows > 0)
rejects(function() Menu.generate(registryFor(fixture(125))) end, '256 settings')
rejects(function() Menu.generate(baseRegistry, {catalog = {version = 1, next = 3, entries = {a = 1, b = 1}}}) end, 'invalid catalog entry')
local tooMany = {}
for i = 1, 64 do tooMany[i] = {collection = 'Tests', category = 'player.stats', name = 'Stats ' .. i} end
rejects(function() Menu.generate(registryFor(tooMany)) end, '63 templates')
local tooLarge = fixture(2); tooLarge.actions = {}
for i = 1, 25 do
    tooLarge.actions[i] = {name = string.rep('X', 4000) .. i, slots = 1, type = 'any'}
end
rejects(function() Menu.generate(registryFor(tooLarge)) end, '256 KiB')
local file = assert(io.open('outputs/example-mod_settings.ini', 'wb'))
file:write(firstResult.manifest); file:close()
print('menu: ' .. checks .. ' checks passed using actual DMM/AMM parsers')
