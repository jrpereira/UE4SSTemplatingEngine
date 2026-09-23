package.path = 'Scripts/?.lua;' .. package.path
local codes=require('te.player_actions.key_codes')
assert(codes.toName(49)=='One')
assert(codes.toName(81)=='Q')
assert(codes.toName(53)=='Five')
assert(codes.toName(54)=='Six')
assert(codes.toName(0)=='None')
assert(codes.toName(255)==nil)
print('Player-action key codes: 6 checks passed')
