package.path = './Scripts/?.lua;' .. package.path
local Startup = require('mct.lua_startup')
local References = require('mct.lua_references')

local object = {valid=true, id='1:100:Widget A'}
local events, epoch
local source = {
    valid=function(value) return value.valid end,
    identity=function(value) return value.id end,
    ready=function(value) return value.valid end,
    matches=function() return true end,
    parent=function() end,
    find=function() return {object} end,
    subscribe=function(callback, getEpoch)
        events, epoch = callback, getEpoch
        return function() events=nil end
    end,
    onError=function(error) error(error.message) end,
    stop=function() end,
}
local host=References.new(source)
local ref=assert(host.capture(object))
assert(host.capture(object)==ref and host.identity(ref)==object.id)
assert(host.valid(ref) and host.unwrap(ref)==object)
local seen
host.subscribe(function(event) seen=event end,function() return 1 end)
events({kind='changed',object=object,epoch=epoch()})
assert(seen.object==ref and seen.kind=='changed')
object.id='2:100:Widget A'
assert(not host.valid(ref) and host.unwrap(ref)==nil)
local newer=assert(host.capture(object))
assert(newer~=ref and host.valid(newer))

local jobs={}
local category={name='player.quickslots',targets={root={class='/Script/UMG.UserWidget'}}}
local template={id='example.template',name='Template',category='player.quickslots',
    attach=function() end,update=function() end,detach=function() end}
local opts={categoryFiles={'category'},templateFiles={'template'},
    execute=function(path) return path=='category' and category or template end,
    host={valid=function() return true end,identity=function() return 'object' end,
        ready=function() return true end,matches=function() return true end,
        parent=function() end,find=function() return {} end,
        subscribe=function() return function() end end,onError=function(error) error(error.message) end}}
local boot=Startup.start(opts,{ExecuteInGameThread=function(callback) jobs[#jobs+1]=callback end})
assert(boot.phase=='registering' and #jobs==1)
jobs[1]()
assert(boot.phase=='starting' and #jobs==2)
jobs[2]()
assert(boot.phase=='running')
boot:stop()
assert(boot.phase=='stopped')
print('PASS: Lua-only startup and map-scoped references')
