package.path = './Scripts/?.lua;' .. package.path
local Handoff = require('mct.menu_handoff')
local Extension = require('mct.dmm_extension')
local NativeStartup = require('mct.native_startup')
local passed = 0
local function test(name, body)
    local ok, why=pcall(body)
    assert(ok,name..': '..tostring(why)); passed=passed+1
end
local function shared()
    local values={}
    return {GetSharedVariable=function(_,key) return values[key] end,
        SetSharedVariable=function(_,key,value) values[key]=value end}
end
local function eventLoop()
    local env={print=function() end,MCTNativeTakeRegisteredTemplates=function() return '' end,
        MCTNativeLifetimeSession=function() return 1 end}; setmetatable(env,{__index=_G})
    local fire=assert(loadfile('Scripts/mct/loop_start.lua','t',env))()
    return env.MCTNative,fire
end
local function options()
    local object={}
    local count={find=0,attach=0,update=0}
    local category={name='player.quickslots',single=true,targets={root={object='widget'}}}
    local template={id='template',name='Template',category=category.name,
        attach=function() count.attach=count.attach+1 end,update=function() end,detach=function() end}
    local opts={categoryFiles={'category'},templateFiles={'template'},
        execute=function(path) return path=='category' and category or template end,
        selections={[category.name]={template={}}},
        host={valid=function(o) return o==object end,ready=function() return true end,
            identity=function() return 'instance:1' end,parent=function() end,matches=function() return true end,
            find=function() count.find=count.find+1; return {object} end,
            subscribe=function() return function() end end,onError=function(e) error(e.message) end}}
    return opts,count
end

test('Loop Start fires once; cancelled callbacks and repeated signals are ignored',function()
    local native,fire=eventLoop()
    local count=0
    native.onLoopStart(function() count=count+1 end)
    native.onLoopStart(function() error('isolated callback') end)
    local stop=native.onLoopStart(function() count=count+100 end)
    native.onLoopStart(function() count=count+1 end)
    stop(); assert(count==0)
    fire(); fire(); assert(count==2)
    assert(not pcall(native.onLoopStart,function() end))
end)

test('all-modules barrier loads templates before game-thread object discovery',function()
    local native,fire=eventLoop()
    local opts,count=options()
    local gameThread={}
    local boot=NativeStartup.start(opts,{MCTNative=native,ExecuteInGameThread=function(fn) gameThread[#gameThread+1]=fn end})
    assert(boot.phase=='registering' and boot.menu==nil and count.find==0)
    fire()
    assert(boot.phase=='starting' and boot.menu~=nil and count.find==0 and #gameThread==1)
    gameThread[1]()
    assert(boot.phase=='running' and count.find==1 and count.attach==1)
end)

test('stopped startup cannot run its already-queued game-thread callback',function()
    local native,fire=eventLoop()
    local opts,count=options(); local queued
    local boot=NativeStartup.start(opts,{MCTNative=native,ExecuteInGameThread=function(fn) queued=fn end})
    fire(); boot:stop(); queued()
    assert(boot.phase=='stopped' and count.find==0 and count.attach==0)
end)

test('native helper is required instead of substituting a timer',function()
    assert(not pcall(NativeStartup.start,{}, {ExecuteInGameThread=function() end}))
end)

test('menu reader does no file access until publication completes',function()
    local state=shared(); local publisher=Handoff.publisher(state); local reads=0
    local reader=Handoff.reader('/mod',state,function(path)
        reads=reads+1
        return path:match('menu%-pages') and 'return {version=1,pages={}}' or 'manifest'
    end)
    assert(reader()==nil and reads==0)
    publisher:begin(); assert(reader()==nil and reads==0)
    publisher:ready(); assert(reader().aggregate.manifest=='manifest' and reads==2)
    reader(); assert(reads==2)
    publisher:stop(); assert(reader()==nil)
end)

test('old publisher cannot publish or stop a newer generation',function()
    local state=shared()
    local old,new=Handoff.publisher(state),Handoff.publisher(state)
    old:begin(); old:ready(); new:begin()
    assert(not pcall(old.ready,old))
    new:ready(); old:stop()
    local reader=Handoff.reader('/mod',state,function(path)
        return path:match('menu%-pages') and 'return {version=1,pages={}}' or 'current'
    end)
    assert(reader().aggregate.manifest=='current')
end)

test('reader rejects a reload that starts midway through reading files',function()
    local state=shared(); local publisher=Handoff.publisher(state)
    publisher:begin(); publisher:ready()
    local reads=0
    local reader=Handoff.reader('/mod',state,function(path)
        reads=reads+1
        if reads==2 then publisher:begin() end
        return path:match('menu%-pages') and 'return {version=1,pages={}}' or 'manifest'
    end)
    assert(reader()==nil)
end)

test('DMM can load before MCT and later discover fresh pages without stale providers',function()
    local current
    local extension=Extension.new('/mod',function() return current end)
    local api={choices={parse=function(value) return {{id=value}} end},
        pages={build=function(_,providers) return providers end}}
    extension.install(api)
    local providers={{id='Other',name='Other',testOnly=false},
        {id='ModCoreTemplates',name='Stale',testOnly=false},
        {id='ModCoreTemplates.old',name='Old',testOnly=false}}
    api.pages.build({},providers,{},{}); assert(#providers==1)
    current={aggregate={manifest='fresh'},pages={{id='ModCoreTemplates.player.quickslots',name='Quickslots',
        category='player.quickslots',manifest='quickslots'}}}
    api.pages.build({},providers,{},{}); assert(#providers==3)
    current={aggregate={manifest='new'},pages={}}
    api.pages.build({},providers,{},{}); assert(#providers==2)
    for _,p in ipairs(providers) do if p.id=='ModCoreTemplates' then assert(p.choices[1].id=='new') end end
end)

test('native lifetime closures keep their original session across reloads',function()
    local session, calls=1,{}
    local env={print=function() end,
        MCTNativeLifetimeSession=function() return session end,
        MCTNativeCapture=function(id,address) calls[#calls+1]={id,address}; return 'token' end,
        MCTNativeValid=function(id,address,token) return id==session and address==100 and token=='token' end,
        MCTNativeTakeLost=function(id) return id==session and 'token' or nil end}
    setmetatable(env,{__index=_G})
    assert(loadfile('Scripts/mct/loop_start.lua','t',env))()
    local old=env.MCTNative.lifetimes
    assert(old.capture(100)=='token' and old.valid(100,'token'))
    session=2
    assert(loadfile('Scripts/mct/loop_start.lua','t',env))()
    assert(not old.valid(100,'token') and old.takeLost()==nil)
    old.capture(100); env.MCTNative.lifetimes.capture(100)
    assert(calls[2][1]==1 and calls[3][1]==2)
end)
test('other modules register template files before Loop Start closes the set',function()
    local native,fire=eventLoop()
    local opts=options()
    local external={id='external',name='External',category='player.quickslots',
        attach=function() end,update=function() end,detach=function() end}
    local original=opts.execute
    opts.execute=function(path) if path=='external' then return external end; return original(path) end
    local consumed=0
    native.registeredTemplates=function() consumed=consumed+1; return {'external'} end
    local jobs={}
    local boot=NativeStartup.start(opts,{MCTNative=native,ExecuteInGameThread=function(fn) jobs[#jobs+1]=fn end})
    assert(boot.phase=='registering' and consumed==0)
    fire()
    assert(consumed==1 and boot.menu.definitions['player.quickslots']~=nil)
    assert(not pcall(boot.registerTemplate,boot,'late'))
    jobs[1](); assert(boot.phase=='running')
end)
print('PASS: '..passed..' MCT startup and cross-state menu tests')
