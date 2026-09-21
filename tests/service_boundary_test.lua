package.path = 'Scripts/?.lua;' .. package.path
local C,R,L = require('te.categories'),require('te.registry'),require('te.lifecycle')
local makeService = dofile('tests/support/service.lua')
local checks, calls = 0, {}
local function check(value) assert(value); checks=checks+1 end
local categories=C.new(); categories:registerCategory('player',{'quickslots'})
local a,b=makeService({id='a'}),makeService({id='b'})
local expected=a
local function template(name)
    return {collection='Boundary',name=name,category='player.quickslots',
        settings={enabled=false},
        actions={{name='Group',slots=1,type='ability'}},
        attach=function(self,service,target,spec,previous)
            check(service==expected and service.playerActions==nil)
            check(target~=nil)
            calls[#calls+1]='attach:'..name
            return previous or {}
        end,
        detach=function(self,service,handle,reason)
            check(service==expected and service.playerActions==nil)
            calls[#calls+1]='detach:'..name..':'..reason
            return true
        end,
        render=function(self,service,handle,target,reason)
            check(service==expected and service.playerActions==nil)
            calls[#calls+1]='render:'..name
            return 'applied'
        end}
end
local registry=R.new(categories,{execute=function() return {template('A'),template('B')} end})
registry:registerTemplate('boundary.lua');registry:loadTemplatesFromRegister()
local first,second=registry.templates[1].id,registry.templates[2].id
local runtime=L.new(registry)
local context={playerActions=a,hostOnly=true,targets={['player.quickslots']={}}}
check(not runtime:apply('player.quickslots',first,{},{}))
check(#calls==0 and runtime:selection('player.quickslots')==nil)
check(runtime:apply('player.quickslots',first,{},context))
local handle=runtime.active['player.quickslots'].handle
local before=#calls
for _, invalid in ipairs({false,'bad',{}, {valid=true}}) do
    context.playerActions=invalid
    check(not runtime:apply('player.quickslots',second,{},context))
    check(not runtime:render('player.quickslots',context,{},'event'))
    check(not runtime:detach('player.quickslots',context,'none'))
    check(#calls==before and runtime.active['player.quickslots'].handle==handle)
end
for _, method in ipairs({'valid','same','identity','parent'}) do
    local service=makeService();service[method]=nil;context.playerActions=service
    local result,why=runtime:render('player.quickslots',context,{},'event')
    check(result==nil and why:find('requires '..method,1,true))
end
context.playerActions=b;expected=b
check(runtime:render('player.quickslots',context,{},'event')=='applied')
check(runtime:apply('player.quickslots',first,{},context))
check(runtime.active['player.quickslots'].handle==handle)
check(runtime:apply('player.quickslots',second,{},context))
check(calls[#calls-1]=='detach:A:switch' and calls[#calls]=='attach:B')
-- Validation inspects method types only; dead-world cleanup must not call engine methods.
for _, method in ipairs({'valid','same','identity','parent'}) do b[method]=function() error('dead world') end end
before=#calls
check(runtime:detach('player.quickslots',nil,'world_invalidated'))
check(#calls==before)
check(runtime:selection('player.quickslots')==nil)

local overridden=L.new(registry,{resolveService=function(category, supplied)
    check(category=='player.quickslots' and supplied.token=='host')
    return a
end})
expected=a
local hostContext={token='host',targets={['player.quickslots']={}}}
check(overridden:apply('player.quickslots',first,{},hostContext))
check(overridden:detach('player.quickslots',hostContext,'none'))
check(overridden:apply('player.quickslots',first,{},hostContext))
before=#calls
check(overridden:detach('player.quickslots',nil,'world_invalidated'))
check(#calls==before and overridden:selection('player.quickslots')==nil)
check(overridden:detach('player.quickslots',nil,'world_invalidated'))

local attacks=C.new();attacks:registerCategory('npc',{'attacks'})
local class='/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C'
local attackTemplate={collection='Boundary',name='Attacks',category='npc.attacks',settings={enabled=false},subscribe={{path=class,
    events={'created'},contexts={'combat'}}},
    attach=function(self,service,target) check(target.kind=='hud');return {} end,
    detach=function() return true end,render=function() return 'applied' end}
local attackRegistry=R.new(attacks,{execute=function() return attackTemplate end})
attackRegistry:registerTemplate('attacks.lua');attackRegistry:loadTemplatesFromRegister()
local attackService={}
for _,method in ipairs({'valid','visible','transition','cancelTransitions','isA','createWidget',
    'viewportSize','viewportScale','nativeBrush','destroyWidget'}) do attackService[method]=function() return true end end
local attackContext={services={['npc.attacks']=attackService},targets={['npc.attacks']={kind='hud'}}}
local attackRuntime=L.new(attackRegistry)
check(attackRuntime:apply('npc.attacks',attackRegistry.templates[1].id,{},attackContext))
attackService.destroyWidget=nil
local attackStatus,attackWhy=attackRuntime:render('npc.attacks',attackContext,{},'created')
check(attackStatus==nil and attackWhy:find('attacks service requires destroyWidget',1,true))
print('service boundary: '..checks..' checks passed')
