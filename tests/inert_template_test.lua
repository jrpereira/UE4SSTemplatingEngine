package.path='Scripts/?.lua;'..package.path
local C,R,L=require('te.categories'),require('te.registry'),require('te.lifecycle')
local checks=0
local function check(value) assert(value);checks=checks+1 end
local categories=C.new();categories:registerCategory('menu',{'fixes'})
local template={collection='Adaptive Mod Menu',name='Dawnwalker Settings Page Fixes',category='menu.fixes',
    createCallbacks=function() error('inert template callback must not run') end}
local registry=R.new(categories,{execute=function() return template end})
registry:registerTemplate('fixes.lua');registry:loadTemplatesFromRegister()
local runtime=L.new(registry)
local identity=registry.templates[1].id
check(runtime:apply('menu.fixes',identity,{},{}))
check(runtime:selection('menu.fixes')==identity)
check(runtime:render('menu.fixes',{},nil,'anything')=='ignored')
check(runtime:detach('menu.fixes',{},'disable'))
check(runtime:selection('menu.fixes')==nil)
print('inert template: '..checks..' checks passed')
