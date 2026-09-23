package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local InputContext = require('te.player_actions.input_context')
local function check(value, message) assert(value, message) end
local objects = {}
local function object(name)
    local value = {name=name, valid=true, Mappings={}, Triggers={}}
    function value:UnmapAll() self.Mappings = {} end
    function value:MapKey(action, key) self.Mappings[#self.Mappings + 1] = {Action=action, Key=key} end
    objects[name] = value
    return value
end
local identity = 0
local input = InputContext({
    valid=function(value) return value and value.valid end,
    retain=function(_, name) return objects[name] or object(name) end,
    initializeIdentity=function() identity = identity + 1 end,
    retainTrigger=function(action, className) return object(action.name .. ':' .. className) end,
    key=function(value) return value == 49 and 'One' or value == 164 and 'LeftShift' or nil end,
    name=function(value) return value end,
    holdSeconds=.2,
})
local template = {name='Quickslots++', category='player.quickslots', actions={
    {name='Abilities',type='ability',slots=4}, {name='Consumables',type='consumable',slots=4},
}}
local direct, plan = input:configure(template, {access=0,PrimaryWheel=1,direct={
    ['1']={{key=49,mode=0},{key=0,mode=1},{key=0,mode=0},{key=0,mode=1}},
    ['2']={{key=0,mode=0},{key=0,mode=1},{key=0,mode=0},{key=0,mode=1}},
}})
check(plan.access == 0 and direct.IA_ActionSlot1.name == 'IA_ActionSlot1')
check(objects.IMC_Quickslots_OW.Mappings[1].Key.KeyName == 'One')
check(identity == 8, 'direct mode retains each QSF action once')
local groups = input:configure(template, {access=1,groups={['1']={key=164,mode=0},['2']={key=0,mode=-1}},
    shared={{key=49,mode=0},{key=0,mode=0},{key=0,mode=0},{key=0,mode=0}}})
check(groups.IA_GroupSlot1.name == 'IA_GroupSlot1' and groups.IA_GroupSlot2.name == 'IA_GroupSlot2')
check(groups.IA_SharedSlot1.name == 'IA_SharedSlot1')
check(#objects.IMC_Quickslots_OW.Mappings == 2 and objects.IMC_Quickslots_OW.Mappings[1].Key.KeyName == 'LeftShift'
    and objects.IMC_Quickslots_OW.Mappings[2].Key.KeyName == 'One')
check(identity == 14, 'group mode retains selectors and shared slot actions')
local subsystem = object('subsystem')
function subsystem:AddMappingContext(mapping, priority) self.mapping, self.priority = mapping, priority end
function subsystem:RemoveMappingContext(mapping) if self.mapping == mapping then self.mapping = nil end end
input:attach('OW', subsystem, -1)
check(subsystem.priority == 999, 'generated quickslots context adds 1000 to native priority')
print('PASS input context: persistent QSF actions and selected key mappings')
