package.path='Scripts/?.lua;'..package.path
local Native=require('ket.native_events')
local checks=0
local function check(value) assert(value);checks=checks+1 end
local registered,queued,delivered
local api={NotifyOnNewObject=function(path,callback) registered={path=path,callback=callback} end}
local host=Native.new(api,function(callback) queued=callback end)
local class='/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C'
local stop=host.subscribe('npc.attacks',{name='created',path=class,contexts={'combat'}},function(target) delivered=target end)
check(registered.path==class and delivered==nil)
local indicator={id='indicator'}
registered.callback({get=function() return indicator end})
check(type(queued)=='function' and delivered==nil)
queued();check(delivered==indicator)
stop();delivered=nil;queued=nil;registered.callback(indicator)
check(delivered==nil and queued==nil)
print('native events: '..checks..' checks passed')
