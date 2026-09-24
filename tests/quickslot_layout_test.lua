package.path = 'Scripts/?.lua;' .. package.path

local Layout = require('ket.quickslot_layout')
local value = Layout.parse('0|20,40,1.0,1.0|40,-420,0.8,0.7')
assert(value.defaultWheel == 0 and value.first.x == 20 and value.first.size == 1)
assert(value.second.y == -420 and value.second.opacity == 0.7)
for _, invalid in ipairs({
    '2|20,40,1,1|40,-420,0.8,0.7',
    '0|20,40,1,1',
    '0|20,40,0,1|40,-420,0.8,0.7',
    '0|20,40,1,1|40,-420,0.8,1.2',
    '0|20,40,1,1|40,-420,0.8,0.7;bad',
}) do
    assert(not pcall(Layout.parse, invalid), invalid .. ' should fail')
end
print('quickslot layout: boolean flag and two geometry tuples validated')
