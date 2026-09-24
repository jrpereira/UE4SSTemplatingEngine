package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local Plan = require('ket.player_actions.plan')

local function check(value, message) assert(value, message) end
local template = {
    name = 'Quickslots++', category = 'player.quickslots',
    actions = {
        {name = 'Abilities', type = 'ability', slots = 4},
        {name = 'Consumables', type = 'consumable', slots = 4},
    },
}

local direct = Plan.build(template, {access = 0, PrimaryWheel=1, direct = {
    ['1'] = {{key=49,mode=0},{key=50,mode=1},{key=51,mode=0},{key=52,mode=1}},
    ['2'] = {{key=49,mode=0},{key=50,mode=1},{key=51,mode=0},{key=52,mode=1}},
}})
check(#direct.actions == 8)
for slot = 1, 4 do
    check(direct.actions[slot].id == 'IA_ActionSlot' .. slot and direct.actions[slot].type == 'ability')
    check(direct.actions[slot + 4].id == 'IA_ActionSlot' .. (slot + 4) and direct.actions[slot + 4].type == 'consumable')
end
local consumableFirst = Plan.build(template, {access = 0, PrimaryWheel=0, direct = {
    ['1'] = {{key=49,mode=0},{key=50,mode=1},{key=51,mode=0},{key=52,mode=1}},
    ['2'] = {{key=49,mode=0},{key=50,mode=1},{key=51,mode=0},{key=52,mode=1}},
}})
check(consumableFirst.actions[1].type == 'consumable' and consumableFirst.actions[5].type == 'ability')

local groups = Plan.build(template, {access = 1, groups = {
    ['1'] = {key=164,mode=0}, ['2'] = {key=0,mode=-1},
}, shared = {{key=49,mode=0},{key=50,mode=0},{key=51,mode=1},{key=52,mode=1}}})
check(#groups.actions == 6)
check(groups.actions[1].id == 'IA_GroupSlot1' and groups.actions[1].binding.key == 164)
check(groups.actions[2].id == 'IA_GroupSlot2' and groups.actions[2].binding.mode == -1)
check(groups.actions[3].id == 'IA_SharedSlot1' and groups.actions[3].shared
    and groups.actions[3].binding.key == 49)
print('PASS input plan: stable QSF direct and group action identities')
