package.path = 'Scripts/?.lua;' .. package.path

local Categories = require('te.categories')
local Registry = require('te.registry')
local Menu = require('te.menu')
local Plan = require('te.player_actions.plan')

local category = dofile('Scripts/categories/player_quickslots.lua')
local categories = Categories.new()
categories:addCategory(category)
local templates = {
    {name='Bottom', category='player.quickslots', settings={target='templates',enabled=false}},
    {name='Vertical', category='player.quickslots', settings={target='templates',enabled=false}},
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

local rows, values, accessIndex = {}, {}, nil
for index, row in ipairs(menu.rows) do
    assert(not rows[row.Id], 'duplicate menu setting ID')
    rows[row.Id] = index
    values[row.Id] = tonumber(row.Default)
    if row.Id == bottom.access then accessIndex = index end
end
assert(accessIndex and rows[bottom.direct['1'][1].key] > accessIndex)
values[bottom.access] = 2
values[bottom.direct['1'][1].key] = 77
values[bottom.advanced['1'][1].key] = 78
for _, selected in ipairs(choices) do
    values[selector.id] = selected
    local result = menu.decode(values)['player.quickslots']
    assert(result.id == selector.byValue[selected])
    local config = result.configuration
    assert(config.access == 2 and config.categorySettings.AccessMode == 2)
    assert(config.categorySettings.Advanced == category.settings.fields[2].default)
    assert(config.direct['1'][1].key == 77 and config.advanced['1'][1].key == 78)
    local plan = Plan.build(templates[1], config, category)
    assert(#plan.actions == 16)
    local groupKeys = 0
    for _, action in ipairs(plan.actions) do
        if action.targetSlot then groupKeys = groupKeys + 1 end
    end
    assert(groupKeys == 8)
end

print('category menu: shared IDs, category-first settings and Advanced bindings passed')
