package.path = 'Scripts/?.lua;' .. package.path

local Categories = require('ket.categories')
local Registry = require('ket.registry')
local Menu = require('ket.menu')

local categories = Categories.new()
categories:addCategory(dofile('Scripts/categories/player_quickslots.lua'))
local template = {name='Quickslots', category='player.quickslots',
    settings={target='templates', enabled=false}}
local registry = Registry.new(categories, {execute=function() return {template} end})
registry:registerTemplate('fixture.lua')
registry:loadTemplatesFromRegister()
local menu = Menu.generate(registry, {externalQuickslotControls=true})
local ids, values = {}, {}
for _, row in ipairs(menu.rows) do
    ids[row.Id] = true
    values[row.Id] = tonumber(row.Default)
end
assert(not ids.KET_PlayerQuickslotsAccessMode)
assert(not ids.KET_PlayerQuickslotsSharedSlot1)
assert(not ids.KET_PlayerQuickslotsGroupAbility)
assert(ids.KET_Template)
local selected = assert(next(menu.selectors['player.quickslots'].byValue))
values.KET_Template = selected
local decoded = menu.decode(values)['player.quickslots']
assert(decoded.id and decoded.settings.AccessMode == nil)
assert(decoded.settings.access == nil and decoded.settings.direct == nil)
print('KET menu leaves quickslot Access Method and slots to KEC')
