package.path = 'Scripts/?.lua;' .. package.path

local Categories = require('ket.categories')
local Registry = require('ket.registry')
local Menu = require('ket.menu')
local Plan = require('ket.player_actions.plan')
local Layout = require('ket.quickslot_layout')

local category = dofile('Scripts/categories/player_quickslots.lua')
local categories = Categories.new()
categories:addCategory(category)
local templates = {
    {name='Bottom', category='player.quickslots', settings={target='templates',enabled=false}},
    {name='Vertical', category='player.quickslots', settings={target='templates',enabled=false,
        groups={{id='Layout',label='Layout'}}, fields={{id='Advanced',label='Override',
            group='Layout',type='integer',min=0,max=10,default=3}}}},
}
local registry = Registry.new(categories, {execute=function() return templates end})
registry:registerTemplate('fixture.lua')
registry:loadTemplatesFromRegister()
local menu = Menu.generate(registry)
local selector = assert(menu.selectors['player.quickslots'])
local choices = {}
for value in pairs(selector.byValue) do choices[#choices + 1] = value end
table.sort(choices)
assert(#choices == 2)
local bottom = menu.definitions['player.quickslots'][choices[1]]
local vertical = menu.definitions['player.quickslots'][choices[2]]
assert(bottom.access == vertical.access)
assert(bottom.direct['1'][1].key == vertical.direct['1'][1].key)
assert(bottom.advanced['1'][1].key == vertical.advanced['1'][1].key)
for _, sectionId in ipairs({'KET_PlayerQuickslotsShared', 'KET_PlayerQuickslotsAbilities',
    'KET_PlayerQuickslotsConsumables', 'KET_PlayerQuickslotsGroups'}) do
    local section = assert(menu.fullManifest:match('%[Category%.' .. sectionId .. '%]([^[]+)'))
    for _, choice in ipairs(choices) do
        assert(section:find(tostring(choice) .. ':', 1, true),
            sectionId .. ' lacks label for template value ' .. choice)
    end
end
local sharedSection = assert(menu.fullManifest:match('%[Category%.KET_PlayerQuickslotsShared%]([^[]+)'))
assert(sharedSection:find('ammHeading=0', 1, true))

local rows, values, accessIndex = {}, {}, nil
for index, row in ipairs(menu.rows) do
    assert(not rows[row.Id], 'duplicate menu setting ID')
    rows[row.Id] = index
    values[row.Id] = tonumber(row.Default)
    if row.Id == bottom.access then accessIndex = index end
end
assert(accessIndex and rows[bottom.direct['1'][1].key] > accessIndex)
assert(menu.rows[rows[bottom.direct['1'][1].key]].Label == 'Slot 1')
assert(menu.rows[rows[bottom.direct['2'][1].key]].Label == 'Slot 1')
values[bottom.access] = 2
values[bottom.direct['1'][1].key] = 77
values[bottom.advanced['1'][1].key] = 78
local textId = assert(next(menu.textSettings))
assert(textId == 'KET_PlayerQuickslotsAdvanced')
values[textId] = '1|10,-20,1.2,0.9|30,40,0.8,0.7'
local layout = Layout.parse(values[textId])
assert(layout.defaultWheel == 1 and layout.first.x == 10 and layout.second.opacity == 0.7)
for _, selected in ipairs(choices) do
    values[selector.id] = selected
    local result = menu.decode(values)['player.quickslots']
    assert(result.id == selector.byValue[selected])
    local config = result.settings
    assert(config.access == 2 and config.AccessMode == 2)
    assert(config.Advanced == (selected == choices[2] and 3 or values[textId]))
    assert(config.AccessMode == 2)
    assert(config.direct['1'][1].key == 77 and config.advanced['1'][1].key == 78)
    local plan = Plan.build(templates[1], config, category)
    assert(#plan.actions == 16)
    local groupKeys = 0
    for _, action in ipairs(plan.actions) do
        if action.targetSlot then groupKeys = groupKeys + 1 end
        if action.slot then assert(action.groupIndex == 1 or action.groupIndex == 2) end
    end
    assert(groupKeys == 8)
end

print('category menu: shared IDs, category-first settings and Advanced bindings passed')
