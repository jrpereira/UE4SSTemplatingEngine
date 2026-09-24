package.path = 'Scripts/?.lua;' .. package.path
local Categories = require('ket.categories')
local Registry = require('ket.registry')
local Menu = require('ket.menu')

local category = dofile('Scripts/categories/player_quickslots.lua')
local categories = Categories.new()
categories:addCategory(category)
local templates = {
    {name='Bottom', category='player.quickslots', settings={target='templates',enabled=false,
        groups={{id='Layout',label='Layout'}}, fields={{id='Offset',label='Offset',
            group='Layout',type='integer',min=0,max=10,default=2}}}},
    {name='Vertical', category='player.quickslots', settings={target='templates',enabled=false,
        groups={{id='Layout',label='Layout'}}, fields={{id='Offset',label='Offset',
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
local first = menu.definitions['player.quickslots'][choices[1]]
local second = menu.definitions['player.quickslots'][choices[2]]
assert(first.settings.Offset ~= second.settings.Offset, 'templates must retain independent settings')
local values, rows = {}, {}
for _, row in ipairs(menu.rows) do
    assert(not rows[row.Id], 'duplicate menu setting ID')
    rows[row.Id] = row
    if row.Default ~= nil then values[row.Id] = tonumber(row.Default) end
end
assert(not rows.KET_PlayerQuickslotsAccessMode)
assert(not rows.KET_PlayerQuickslotsSharedSlot1)
assert(not next(menu.textSettings), 'quickslot category must not supply legacy wheel layout text')
values[first.settings.Offset] = 7
values[second.settings.Offset] = 9
for index, selected in ipairs(choices) do
    local definition = menu.definitions['player.quickslots'][selected]
    assert(definition.access == nil and definition.direct == nil and definition.advanced == nil)
    values[selector.id] = selected
    local result = menu.decode(values)['player.quickslots']
    assert(result.id == selector.byValue[selected])
    assert(result.settings.Offset == (index == 1 and 7 or 9))
    assert(result.settings.AccessMode == nil and result.settings.access == nil
        and result.settings.direct == nil, 'visual settings must not inject input controls')
    local group = rows[definition.settings.Offset].Group
    local section = assert(menu.fullManifest:match('%[Category%.' .. group .. '%]([^[]+)'))
    assert(section:find('VisibleWhen=' .. selector.id, 1, true))
    assert(section:find('VisibleValues=' .. tostring(selected), 1, true))
end
-- Rebuilding preserves IDs and the shared selector without merging provider values.
local rebuilt = Menu.generate(registry, {catalog=menu.catalog})
assert(rebuilt.selectors['player.quickslots'].id == selector.id)
for _, selected in ipairs(choices) do
    assert(rebuilt.definitions['player.quickslots'][selected].settings.Offset
        == menu.definitions['player.quickslots'][selected].settings.Offset)
end
print('category menu: shared selection, independent visual settings and no input ownership passed')
