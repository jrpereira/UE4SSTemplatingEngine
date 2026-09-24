package.path = 'Scripts/?.lua;Scripts/?/init.lua;' .. package.path
local Runtime = require('ket.player_actions.runtime')
local objects = {}
local function object(name)
    local value = {name=name, valid=true, Mappings={}, Triggers={}}
    function value:UnmapAll() self.Mappings={} end
    function value:MapKey(action,key) self.Mappings[#self.Mappings+1]={Action=action,Key=key} end
    objects[name]=value; return value
end
local function check(value,message) assert(value,message) end
local native = {}
for _, name in ipairs({'Left','Top','Right','Bottom','CombatToggle','OWToggle'}) do native[#native+1]=object('Native:'..name) end
local context=object('subsystem')
function context:AddMappingContext(mapping,priority) self.mapping,self.priority=mapping,priority end
function context:RemoveMappingContext(mapping) if self.mapping==mapping then self.mapping=nil end end
local rebuilds=0
local runtime=Runtime({
    nativeTargets={'a','b','c','d','e','f'}, resolve=function(path) return native[({a=1,b=2,c=3,d=4,e=5,f=6})[path]] end,
    valid=function(v)return v and v.valid end,path=function(v)return v and v.name end,unwrap=function(v)return v end,same=function(a,b)return a==b end,
    each=function(values,fn) for i,v in ipairs(values or {}) do fn(i,v) end end,
    retainInactive=function() return objects.inactive or object('inactive') end,
    constructGate=function(action,marker)return object(action.name..':'..marker) end,
    chord=function(trigger)return trigger.ChordAction end,setChord=function(trigger,action)trigger.ChordAction=action end,
    setTriggers=function(action,triggers)action.Triggers=triggers end,rebuild=function() rebuilds=rebuilds+1;return true end,
    input={valid=function(v)return v and v.valid end,retain=function(_,name)return objects[name] or object(name) end,
        initializeIdentity=function()end,retainTrigger=function(action,kind)return object(action.name..':'..kind) end,
        key=function(value)return value==49 and 'One' or nil end,name=function(value)return value end},
})
local template={name='Quickslots++',category='player.quickslots',actions={{name='Abilities',type='ability',slots=4},{name='Consumables',type='consumable',slots=4}}}
local direct={access=0,direct={['1']={{key=49,mode=0},{key=0,mode=0},{key=0,mode=0},{key=0,mode=0}},['2']={{key=0,mode=0},{key=0,mode=0},{key=0,mode=0},{key=0,mode=0}}}}
local _,_,state=runtime:activate(template,direct,context,'OW',-1,false)
check(state=='bindings_pending' and #native[1].Triggers==0 and context.mapping==nil,
    'pending handlers do not expose their context or suppress native actions')
runtime:deactivate('OW')
local _,_,applied=runtime:activate(template,direct,context,'OW',-1,true)
check(applied=='applied' and rebuilds==1 and #native[1].Triggers==1,'all verified native actions receive gates')
runtime:deactivate('OW')
check(rebuilds==2 and #native[1].Triggers==0 and context.mapping==nil,'deactivation restores native actions and removes the mapping context')
print('PASS input runtime: ready-only gating and exact restoration')
