package.path = './Scripts/?.lua;' .. package.path
local Handoff = require('mc.menu_handoff')
local Extension = require('mc.dmm_extension')
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

test('DMM entry point does not pass assert message as the menu loader',function()
    local oldShared, oldHandoff = _G.ModRef, package.loaded['mc.menu_handoff']
    local shared = {}
    local captured
    package.loaded['mc.menu_handoff'] = {reader=function(root, value, loader)
        captured={root=root,shared=value,loader=loader}
        return function() end
    end}
    _G.ModRef=shared
    local root=assert(debug.getinfo(1,'S').source:match('^@(.+)/tests/mc/startup_test%.lua$'))
    local ok,extension=pcall(dofile,root..'/Scripts/dmm_extension.lua')
    _G.ModRef,package.loaded['mc.menu_handoff']=oldShared,oldHandoff
    assert(ok,extension)
    assert(type(extension)=='table' and captured.shared==shared and captured.loader==nil)
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

print('PASS: '..passed..' MCT cross-state menu tests')
