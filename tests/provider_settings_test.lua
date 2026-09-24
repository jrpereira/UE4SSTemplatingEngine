package.path = 'Scripts/?.lua;' .. package.path
local U, P = require('ket.util'), require('ket.provider_settings')
local KET = require('ket.init')
local checks = 0
local function check(v) assert(v); checks=checks+1 end
local function rejects(fn, text)
    local ok, err=pcall(fn)
    assert(not ok and tostring(err):find(text,1,true),tostring(err)); checks=checks+1
end
local declaration={target='templates',enabled=true,groups={
    {id='Secondary',label='Secondary',level=4,order=3},
    {id='Primary',label='Primary Visuals',level=4,order=2},
    {id='Visuals',label='Visuals',level=4,order=1,heading=false},
},fields={
    {id='WheelsDisplayed',type='picker',values={1,2},labels={'One','Two'},default=2,
        label='Wheels Displayed',group='Visuals',order=1,tab=true,level=1,after='AccessMethod'},
    {id='PrimaryWheel',type='picker',values={0,1},labels={'Consumables','Abilities'},default=0,
        label='Primary Wheel',group='Visuals',order=2,tab=true,level=4},
}}
local defaults={PrimaryX=20,PrimaryY=40,PrimarySize=100,PrimaryOpacity=100,
    SecondaryX=40,SecondaryY=-420,SecondarySize=70,SecondaryOpacity=80}
for _, role in ipairs({'Primary','Secondary'}) do
    for i, name in ipairs({'X','Y','Size','Opacity'}) do
        local min,max,step=-1000,1000,1
        if name=='Size' then min,max,step=25,200,5 end
        if name=='Opacity' then min,max,step=0,100,5 end
        local id=role..name
        declaration.fields[#declaration.fields+1]={id=id,type='integer',min=min,max=max,step=step,
            default=defaults[id],label=name,group=role,order=i,suffix=step==5 and '%' or nil,
            visibleWhen=id=='SecondaryX' and 'WheelsDisplayed' or nil,
            visibleValues=id=='SecondaryX' and {2} or nil}
    end
end
local template={name='Visuals',category='player.quickslots',
    actions={{name='Actions',slots=1,type='any'}},settings=declaration}
local attaches=0
function template:attach(_,target,spec,previous)
    check(target~=nil)
    attaches=attaches+1
    return previous or {}
end
function template:detach() return true end
function template:render() return 'applied' end
local ket=KET.new({listFiles=function() return {'fixture.lua'} end,execute=function() return template end})
ket:loadTemplatesFromRegister()
local menu=ket:generateMenu()
local Choices=dofile(assert(os.getenv('KET_DMM_CHOICES')))
local Presentation=dofile(assert(os.getenv('KET_AMM_PRESENTATION')))
local page=assert(menu.pageByCategory['player.quickslots'])
local items=Presentation.parse(page.manifest,Choices.parse(page.manifest))
local model=Choices.open({id='provider-test',choices=items,testOnly=true}); assert(not model.error,model.error)
local index={}; for i,item in ipairs(items) do index[item.id]=i end
local selector=menu.selectors['player.quickslots']; local value=next(selector.byValue)
check(page.rows[index[selector.id]].ammLevel==2
    and page.rows[index[selector.id]].ammType==nil
    and page.rows[index[selector.id]].ammTabsWidth==nil)
local def=menu.definitions['player.quickslots'][value]
local provider=def.settings
check(index[provider.WheelsDisplayed]>index[def.access])
check(index[provider.WheelsDisplayed]<index[provider.PrimaryWheel])
check(index[provider.PrimaryOpacity]<index[provider.SecondaryX])
check(items[index[provider.WheelsDisplayed]].ammTabs and items[index[provider.PrimaryX]].ammGroup.font==4)
check(items[index[provider.WheelsDisplayed]].ammHeader
    and items[index[provider.WheelsDisplayed]].ammFont==1)
check(items[index[provider.WheelsDisplayed]].ammGroup.heading==false
    and items[index[provider.PrimaryWheel]].ammGroup.heading==false)
check(items[index[provider.PrimarySize]].suffix=='%')
model:set(index[selector.id],value)
model:set(index[provider.WheelsDisplayed],1)
local visibility=model:visibility()
for name, settingId in pairs(provider) do
    check(visibility[index[settingId]] == (name~='SecondaryX'))
end
local secondaryX=assert(page.rows[index[provider.SecondaryX]])
check(secondaryX.VisibleWhen==provider.WheelsDisplayed and secondaryX.VisibleValues=='2')
model:set(index[provider.WheelsDisplayed],2)
check(model:visibility()[index[provider.SecondaryX]])
model:set(index[provider.WheelsDisplayed],1)
local values={}; for i,item in ipairs(items) do values[item.id]=model.pending[i] end
local spec=menu.decode(values)['player.quickslots'].settings
check(spec.WheelsDisplayed==1 and spec.PrimaryWheel==0)
for id, expected in pairs(defaults) do check(spec[id]==expected) end
spec.SecondaryX=900
check(menu.decode(values)['player.quickslots'].settings.SecondaryX==40)
local context={playerActions=dofile('tests/support/service.lua')(),targets={['player.quickslots']={}}}
local invalidSpec=U.copy(spec);invalidSpec.PrimaryX=1001
check(not ket.runtime:apply('player.quickslots',menu.definitions['player.quickslots'][value].id,invalidSpec,context))
invalidSpec=U.copy(spec);invalidSpec.Unexpected=1
check(not ket.runtime:apply('player.quickslots',menu.definitions['player.quickslots'][value].id,invalidSpec,context))
check(ket.runtime:commit({revision=1,values=values},menu.decode,context))
local handle=ket.runtime.active['player.quickslots'].handle
values[provider.SecondaryX]=75
check(ket.runtime:commit({revision=2,values=values},menu.decode,context))
check(attaches==2 and ket.runtime.active['player.quickslots'].handle==handle)
local _, committed=ket.runtime:selection('player.quickslots')
check(committed.SecondaryX==75)
check(committed.shared[1].key==spec.shared[1].key and committed.access==spec.access)
values[provider.PrimarySize]=201
rejects(function() menu.decode(values) end,'invalid integer')
local saved=menu.catalog
declaration.fields[1].order=3
local changed=ket:generateMenu({catalog=saved})
check(changed.definitions['player.quickslots'][value].settings.WheelsDisplayed==provider.WheelsDisplayed)
local function invalid(change, message)
    local bad=U.copy(declaration); change(bad)
    rejects(function() P.normalize(bad) end,message)
end
invalid(function(d) d.fields[1].id=d.fields[2].id end,'duplicate provider field')
invalid(function(d) d.groups[1].id=d.groups[2].id end,'duplicate provider group')
invalid(function(d) d.groups[1].heading=0 end,'provider group heading must be boolean')
invalid(function(d) d.fields[1].group='Missing' end,'undeclared provider group')
invalid(function(d) d.fields[1].default=3 end,'default must match')
invalid(function(d) d.fields[1].values={1,1} end,'duplicate provider choice')
invalid(function(d) d.fields[1].labels={'One|Two','Two'} end,'unsupported metadata text')
invalid(function(d) d.fields[3].step=0 end,'range/step')
invalid(function(d) d.fields[3].default=1001 end,'outside range')
invalid(function(d) d.fields[3].min=-math.huge end,'integer min required')
invalid(function(d) d.fields[3].type='custom' end,'unsupported provider field type')
invalid(function(d) d.fields[1].visibleWhen='PrimaryWheel' end,'requires both')
invalid(function(d) d.fields[1].visibleWhen='Missing';d.fields[1].visibleValues={1} end,
    'source must be a picker')
invalid(function(d) d.fields[1].visibleWhen='WheelsDisplayed';d.fields[1].visibleValues={2} end,
    'cannot hide itself')
invalid(function(d) d.fields[3].visibleWhen='SecondaryX';d.fields[3].visibleValues={40} end,
    'source must be a picker')
invalid(function(d) d.fields[3].visibleWhen='WheelsDisplayed';d.fields[3].visibleValues={} end,
    'must not be empty')
invalid(function(d) d.fields[3].visibleWhen='WheelsDisplayed';d.fields[3].visibleValues={3} end,
    'distinct source choice')
invalid(function(d) d.fields[3].visibleWhen='WheelsDisplayed';d.fields[3].visibleValues={1,1} end,
    'distinct source choice')
invalid(function(d) d.fields[3].level=1 end,'level 1 requires a picker')
invalid(function(d) d.fields[2].level=1 end,'only one level-1 picker')
invalid(function(d) d.enabled='yes' end,'settings.enabled must be boolean')
local file=assert(io.open('outputs/example-provider-mod_settings.ini','wb'))
file:write(menu.manifest);file:close()
print('provider settings: '..checks..' checks passed')
