package.path = 'Scripts/?.lua;' .. package.path

local Dispatch = require('ket.player_actions.dispatch')
local calls, closed, failedAt = {}, 0, nil
local bridge = {
    OpenInputComponent = function(path)
        assert(path == '/Game/InputComponent')
        return 'target'
    end,
    BindAction = function(target, action, phase, callback)
        assert(target == 'target')
        if #calls + 1 == failedAt then return nil, 'injected binding failure' end
        calls[#calls + 1] = {action=action, phase=phase, callback=callback}
        return #calls
    end,
    CloseInputComponent = function(target)
        assert(target == 'target')
        closed = closed + 1
        return true
    end,
}
local function action(name)
    return {GetFullName=function() return 'InputAction /Game/' .. name end}
end
local actions = {
    IA_GroupSlot1=action('IA_GroupSlot1'),
    IA_GroupSlot2=action('IA_GroupSlot2'),
    IA_SharedSlot1=action('IA_SharedSlot1'),
    IA_SharedSlot2=action('IA_SharedSlot2'),
}
local plan = {actions={
    {id='IA_GroupSlot1',binding={key=0,mode=-1}},
    {id='IA_GroupSlot2',binding={key=164,mode=2}},
    {id='IA_SharedSlot1',binding={key=49,mode=0}},
    {id='IA_SharedSlot2',binding={key=0,mode=0}},
}}
local delivered = {}
local dispatch = Dispatch({bridge=bridge,fullName=function(value) return value:GetFullName() end,
    componentPath=function() return '/Game/InputComponent' end})
assert(dispatch:bind({},actions,plan,function(definition,phase,event)
    delivered[#delivered + 1] = {definition.id,phase,event}
end))
assert(#calls == 4, 'group hold phases and enabled shared slot must be bound')
assert(calls[1].phase == 'Started' and calls[2].phase == 'Completed'
    and calls[3].phase == 'Canceled' and calls[4].phase == 'Triggered')
calls[4].callback('event')
assert(delivered[1][1] == 'IA_SharedSlot1' and delivered[1][3] == 'event')
assert(dispatch:close() and closed == 1)

calls, failedAt = {}, 2
local ok, why = dispatch:bind({},actions,plan,function() end)
assert(ok == false and why == 'injected binding failure' and closed == 2,
    'partial bridge bindings must close before native input can be gated')
print('PASS input dispatch: shared actions and partial binding rollback')
