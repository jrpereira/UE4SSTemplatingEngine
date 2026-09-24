package.path = 'Scripts/?.lua;' .. package.path
local Paths = require('ket.object_paths')

local declared = 'WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher'
local objects = {
    {full='WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher'},
    {full='WidgetSwitcher /Engine/Transient.GameEngine_1.WBP_GameHUD_C_2.WidgetTree_3.OtherSwitcher'},
    {full='WidgetSwitcher /Engine/Transient.GameEngine_1.WBP_GameHUD_C_2.WidgetTree_3.QuickslotsSwitcher'},
}
for _, object in ipairs(objects) do
    function object:IsValid() return true end
    function object:GetFullName() return self.full end
end
local class
local found = Paths.findLive(declared, function(name) class=name; return objects end)
assert(class == 'WidgetSwitcher' and found == objects[3])
assert(Paths.findLive(declared, function() return {objects[1], objects[2]} end) == nil)
assert(Paths.findLive(declared, function() error('world unavailable') end) == nil)
print('object paths: live category target resolved from stable declaration')
