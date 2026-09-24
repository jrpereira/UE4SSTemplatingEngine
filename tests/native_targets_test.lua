package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local targets = require('ket.player_actions.native_targets')
assert(#targets == 6, 'exactly six verified native quickslot actions are gated')
local seen = {}
for _, name in ipairs(targets) do
    assert(type(name) == 'string' and name:match('^IA_'), 'invalid native action name')
    assert(not seen[name], 'duplicate native action target')
    seen[name] = true
end
assert(seen.IA_Quickslot_Left)
assert(seen.IA_Combat_ToggleQuickslots)
assert(seen.IA_OW_ToggleQuickslots)
print('PASS native targets: exact QSF quickslot gate allowlist')
