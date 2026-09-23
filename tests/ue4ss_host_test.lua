package.path = 'Scripts/?.lua;' .. package.path

local hooks, notifications = {}, {}
local mapPost
FindAllOf = function() return {} end
StaticFindObject = function() return nil end
StaticConstructObject = function() return nil end
FName = function(value) return value end
RegisterHook = function(path, before, after)
    assert(type(before) == 'function' and type(after) == 'function')
    hooks[path] = true
end
NotifyOnNewObject = function(path, callback)
    assert(type(callback) == 'function')
    notifications[path] = callback
end
RegisterLoadMapPostHook = function(callback) mapPost=callback end

local host = require('te.player_actions.ue4ss_host').new(function(callback) callback() end, function() end)
assert(type(host.sync) == 'function', 'expected Enhanced Input host')
for _, path in ipairs({
    '/Script/EnhancedInput.EnhancedInputSubsystemInterface:AddMappingContext',
    '/Script/EnhancedInput.EnhancedInputSubsystemInterface:RemoveMappingContext',
    '/Script/EnhancedInput.EnhancedInputSubsystemInterface:ClearAllMappings',
    '/Script/Engine.PlayerController:ClientRestart',
    '/Script/Engine.PlayerController:ClientRetryClientRestart',
    '/Script/Engine.Controller:OnRep_Pawn',
}) do
    assert(hooks[path], 'missing lifecycle hook: ' .. path)
end
assert(notifications['/Script/Engine.PlayerController'], 'missing PlayerController creation wake')
assert(notifications['/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem'],
    'missing Enhanced Input subsystem creation wake')
assert(notifications['/Script/EnhancedInput.EnhancedInputComponent'],
    'missing pawn input component creation wake')
assert(type(mapPost)=='function', 'missing map-load completion wake')
print('UE4SS host: 9 checks passed')
