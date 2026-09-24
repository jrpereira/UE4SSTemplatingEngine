package.path = 'Scripts/?.lua;' .. package.path

local calls, callback, closed, commits = {}, nil, 0, 0
local function object(fullName)
    return {IsValid=function() return true end, GetFullName=function() return fullName end}
end
local component = object('EnhancedInputComponent /Game/Pawn.InputComponent')
local pawn = object('Pawn /Game/Pawn')
pawn.InputComponent = component
local input = object('PlayerInput /Game/PlayerInput')
input.AppliedInputContexts = {[object('InputMappingContext /Game/IMC_OW.Instance')] = -1}
local controller = object('BP_PlayerController_C /Game/BP_PlayerController_C.Instance')
controller.PlayerInput, controller.AcknowledgedPawn = input, pawn
local subsystem = object('EnhancedInputLocalPlayerSubsystem /Game/Subsystem')
local directControllerLookup=true
FindAllOf = function(class)
    if class == 'BP_PlayerController_C' then return directControllerLookup and {controller} or {} end
    if class == 'PlayerController' then return {controller} end
    if class == 'EnhancedInputLocalPlayerSubsystem' then return {subsystem} end
    return {}
end
StaticFindObject = function() return nil end
StaticConstructObject = function() return nil end
FName = function(value) return value end
RegisterHook = function() end
local notifications={}
NotifyOnNewObject = function(path, fn) notifications[path]=fn end
local bridgeApiVersion = 4
KEngineBridge = {API_VERSION=5,GetCapabilities=function() return {api=bridgeApiVersion,enhanced_input=true,
    explicit_target=true,detailed_errors=true,target_ue4ss_commit='97b7e501'} end,
    OpenInputComponent=function() end, BindAction=function() end, CloseInputComponent=function() end}

local plan = {actions={
    {id='IA_GroupSlot1',groupIndex=1,type='ability',binding={key=0,mode=-1}},
    {id='IA_GroupSlot2',groupIndex=2,type='consumable',binding={key=164,mode=0}},
    {id='IA_SharedSlot1',shared=true,slot=1,binding={key=49,mode=0}},
}}
package.loaded['ket.player_actions.runtime'] = function()
    return {
        prepare=function() return {},plan end,
        commit=function(_,kind)
            assert(callback ~= nil, 'bridge must bind before native input is gated')
            assert(kind == 'OW')
            commits = commits + 1
        end,
        deactivate=function() end,
    }
end
package.loaded['ket.player_actions.dispatch'] = function()
    return {
        bind=function(_,_,_,_,fn) callback=fn;return true end,
        close=function() closed=closed+1;return true end,
    }
end
local category = {contexts={'openworld'},actions={}}
local host = require('ket.player_actions.ue4ss_host').new(function(fn) fn() end,
    function(message) error(message) end, category)
local service = {
    activateQuickslot=function(_,kind,slot) calls[#calls+1]=kind..':'..slot;return true end,
    selectQuickslotGroup=function(_,index) calls[#calls+1]='group:'..index;return true end,
}
local accepted, reason = host:apply({category='player.quickslots'}, {PrimaryWheel=1}, service)
assert(not accepted and reason=='KEngineBridge lacks the required Enhanced Input API 5')
assert(commits==0 and callback==nil, 'API 4 must not bind or gate native input')
bridgeApiVersion=5
assert(host:apply({category='player.quickslots'}, {PrimaryWheel=1}, service))
assert(commits == 1)
local activeCallback = callback
activeCallback(plan.actions[3], 'Triggered')
activeCallback(plan.actions[2], 'Triggered')
activeCallback(plan.actions[3], 'Triggered')
activeCallback(plan.actions[2], 'Triggered')
activeCallback(plan.actions[3], 'Triggered')
assert(table.concat(calls, ',') == 'ability:1,group:2,consumable:1,group:1,ability:1')
assert(host:deactivate() and closed == 1)
activeCallback(plan.actions[3], 'Triggered')
assert(#calls == 5, 'stale bridge callbacks must not dispatch after deactivation')
directControllerLookup=false
pawn.InputComponent=nil
local later = require('ket.player_actions.ue4ss_host').new(function(fn) fn() end,
    function(message) error(message) end, category)
local ready,why=later:apply({category='player.quickslots'}, {PrimaryWheel=1}, service)
assert(not ready and why=='gameplay Enhanced Input stack unavailable')
pawn.InputComponent=component
notifications['/Script/EnhancedInput.EnhancedInputComponent'](component)
assert(commits==2, 'pawn input component creation must retry pending context activation')
assert(later:deactivate())
print('PASS input host delivery: bound before gate, shared group routing, stale callback guard')
