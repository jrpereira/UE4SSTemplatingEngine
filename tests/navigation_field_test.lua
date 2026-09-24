package.path = 'Scripts/?.lua;' .. package.path

local Categories = require('ket.categories')
local Registry = require('ket.registry')
local Menu = require('ket.menu')
local Provider = require('ket.provider_settings')

local template = {
    name='Wheels', category='player.quickslots', single=true,
    actions={{name='Abilities',slots=1,type='abilities'}},
    settings={target='module',enabled=true,
        groups={{id='Options',label='Options'}},
        fields={
            {id='View',type='navigation',group='Options',label='View',
                values={0,1},labels={'Main','Details'},default=0,tab=true,tabNavigation=1},
            {id='Size',type='integer',group='Options',label='Size',
                min=25,max=200,step=5,default=100,visibleWhen='View',visibleValues={1}},
        }},
}
local categories=Categories.new()
categories:registerCategory('player',{'quickslots'})
categories:setCategory('player.quickslots',{single=true})
local registry=Registry.new(categories,{execute=function()return template end})
registry:registerTemplate('ActionFangdango/Scripts/templates/main.lua')
registry:loadTemplatesFromRegister()
local menu=Menu.generate(registry)
local page=assert(menu.pageByModule.ActionFangdango)
local nav, size, selector
for _, row in ipairs(page.rows) do
    if row.Label=='View' then nav=row
    elseif row.Label=='Size' then size=row
    elseif row.Id=='KET_Template' then selector=row end
end
assert(nav and nav.Type=='picker' and nav.mcNavigation==1 and nav.mcType=='tab'
    and nav.tabNavigation==1 and page.manifest:find('tabNavigation=1',1,true))
assert(nav.ConfigFile==nil and nav.ConfigSection==nil and nav.ConfigKey==nil)
local definition=assert(menu.definitions['player.quickslots'][next(menu.selectors['player.quickslots'].byValue)])
assert(definition.navigation.View==nav.Id and definition.settings.View==nil)
assert(size and size.VisibleWhen==nav.Id and size.VisibleValues=='1')
assert(selector and selector.mcLevel==1 and selector.mcType==nil
    and selector.mcTabsWidth==nil)
local values={}
for _, row in ipairs(page.rows) do
    if row~=nav then values[row.Id]=tonumber(row.Default) end
end
values[selector.Id]=next(menu.selectors['player.quickslots'].byValue)
local selected=page.decode(values)['player.quickslots']
assert(selected.id and selected.settings.Size==100 and selected.settings.View==nil)
assert(Provider.validate(template.settings,{Size=100}))
local ok=pcall(Provider.validate,template.settings,{Size=100,View=1})
assert(not ok,'navigation value must not be delivered as a template setting')
print('navigation field: display-only picker, visibility source and omitted Apply value passed')
