package.path = 'Scripts/?.lua;' .. package.path
local KET=require('ket.init')
local category=dofile('Scripts/categories/player_quickslots.lua')
assert(category.attach==nil and category.detach==nil and category.resolveTarget==nil)
assert(category.settings==nil and category.actions==nil)
local target={}
local fixture={name='Visual',category='player.quickslots',settings={target='module',enabled=true}}
function fixture:attach(_,actual) assert(actual==target); return {} end
function fixture:detach() return true end
function fixture:render() return 'applied' end
local te=KET.new({listFiles=function() return {} end,execute=function() return fixture end})
te:registerTemplate('Fixture/Scripts/main.lua')
te:loadTemplatesFromRegister()
local service={valid=function(_,v) return v~=nil end,same=function(_,a,b) return a==b end,
    identity=function() return 'target' end,parent=function() return nil end,
    findObject=function(_,path) assert(path==category.paths.switcher);return target end}
assert(te.runtime:apply(category.name,te.registry.templates[1].id,{}, {playerActions=service}))
assert(te.runtime:detach(category.name,{playerActions=service}))
print('Quickslots category declares a target; generic discovery resolves it')
