package.path = 'Scripts/?.lua;' .. package.path

local Delivery = require('ket.player_actions.delivery')
local selected, activated = {}, {}
local service = {}
function service:selectQuickslotGroup(index)
    selected[#selected + 1] = index
    return true
end
function service:activateQuickslot(kind, slot)
    activated[#activated + 1] = {kind, slot}
    return true
end
local state = {defaultGroup=1, selectedGroup=1, settings={access=2},
    groupTypes={[1]='ability',[2]='consumable'}}
local groupKey = {groupIndex=2, targetSlot=3, binding={mode=0}}
local direct = {type='consumable', slot=3, groupIndex=2, binding={mode=0}}

assert(Delivery.deliver({detachSecondaryWheel=true}, state, direct, 'Triggered', service))
assert(#activated == 0)
assert(Delivery.deliver({detachSecondaryWheel=true}, state, groupKey, 'Triggered', service))
assert(state.selectedGroup == 2 and #selected == 0)
assert(Delivery.deliver({detachSecondaryWheel=true}, state, direct, 'Triggered', service))
assert(#activated == 1 and activated[1][1] == 'consumable' and activated[1][2] == 3)

state.selectedGroup = 1
assert(Delivery.deliver({}, state, groupKey, 'Triggered', service))
assert(state.selectedGroup == 2 and selected[1] == 2)

print('Advanced delivery: detached wheel stays untouched; direct slot still activates')
