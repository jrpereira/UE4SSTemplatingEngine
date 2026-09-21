local root=assert(arg[1])
package.path=root..'/Scripts/?.lua;'..package.path
local checks=0
local function check(v) assert(v);checks=checks+1 end
local callbacks,queued,logs={}, {}, {}
local runtime,menu=require('te.menu_host').start(root,{subscribe=function(id,fn)
    callbacks[id]=fn;return function() callbacks[id]=nil end
end},function(fn) queued[#queued+1]=fn end,function(message) logs[#logs+1]=message end)
check(runtime.runtime:selection('player.quickslots')==nil)
local provider=assert(callbacks.UE4SSTemplatingEngine)
local values={};for _,row in ipairs(menu.aggregate.rows) do values[row.Id]=tonumber(row.Default) end
local selector=menu.selectors['player.quickslots'];values[selector.id]=next(selector.byValue)
provider({providerId='UE4SSTemplatingEngine',revision=1,values=values})
check(#queued==1 and runtime.runtime:selection('player.quickslots')==nil)
queued[1]();queued={}
check(runtime.runtime:selection('player.quickslots')==selector.byValue[values[selector.id]])
local quickslots
for _,entry in ipairs(runtime.registry.templates) do
    if entry.template.category=='player.quickslots' then quickslots=entry.template end
end
check(quickslots and quickslots.widgetRenderingEnabled==false)
values[selector.id]=0
provider({providerId='UE4SSTemplatingEngine',revision=2,values=values});queued[1]()
check(runtime.runtime:selection('player.quickslots')==nil)

-- Exercise the installed entry point and vendored real AMM notification client.
local shared,handlers={},{}
ModRef={GetSharedVariable=function(_,key) return shared[key] end,
    SetSharedVariable=function(_,key,value) shared[key]=value end}
RegisterConsoleCommandHandler=function(command,fn) handlers[command]=fn;return true end
ExecuteInGameThread=function(fn) fn() end
dofile(root..'/Scripts/main.lua')
check(next(handlers)~=nil)
local command='DMM_SettingsApplied_v1_'..('UE4SSTemplatingEngine'):gsub('.',function(c)
    return string.format('%02x',c:byte())
end)
local handler=assert(handlers[command])
local lines={'1'}
for _,row in ipairs(menu.aggregate.rows) do
    local encoded=row.Id:gsub('.',function(c) return string.format('%02x',c:byte()) end)
    local new=values[row.Id]
    lines[#lines+1]=encoded..' '..row.Default..' '..new
end
shared[command..'.data']=table.concat(lines,'\n')
check(handler()==true)

local dmm=assert(os.getenv('TE_DMM_CHOICES'))
local dir=assert(dmm:match('^(.*)[/\\][^/\\]+$'))
package.path=dir..'/?.lua;'..package.path
local parsed,err=dofile(dir..'/providers.lua').parse(menu.manifest)
check(parsed and not parsed.choiceError and parsed.settingsCount==#menu.aggregate.rows)
check(parsed.id=='UE4SSTemplatingEngine' and not parsed.testOnly)
dofile(assert(os.getenv('TE_AMM_PRESENTATION'))).parse(menu.manifest,parsed.choices)
check(#parsed.choices==#menu.aggregate.rows)
local definitions=assert(loadfile(root..'/menu-pages.lua','t',{}))()
check(definitions.version==1 and #definitions.pages==#menu.pages)
for i,page in ipairs(definitions.pages) do
    local categoryParsed,why=dofile(dir..'/providers.lua').parse(page.manifest)
    check(categoryParsed and not categoryParsed.choiceError and categoryParsed.id==menu.pages[i].id
        and categoryParsed.settingsCount==#menu.pages[i].rows,why)
    dofile(assert(os.getenv('TE_AMM_PRESENTATION'))).parse(page.manifest,categoryParsed.choices)
end
local injected
local extension=dofile(root..'/Scripts/dmm_extension.lua')
local extensionApi={version=1,choices=dofile(dmm),pages={build=function(_,providers) injected=providers;return providers end}}
extension.install(extensionApi)
extensionApi.pages.build({},{{id=parsed.id,name=parsed.name,testOnly=false}},nil,{})
check(#injected==1+#definitions.pages)
for _,provider in ipairs(injected) do
    if provider.id~=parsed.id then
        check(provider.path==root..'/mod_settings.ini' and #provider.choices==provider.settingsCount)
    end
end
print('menu stage: '..checks..' checks passed; '..#menu.aggregate.rows..' aggregate settings and '..#menu.pages..' category pages verified')
