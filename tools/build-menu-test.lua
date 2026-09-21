package.path = 'Scripts/?.lua;' .. package.path
local TE = require('te.init')
local quickslotsPath, fixesPath, destination, existing = assert(arg[1]), assert(arg[2]), assert(arg[3]), arg[4]
local description = 'Menu test: settings are saved, but new gameplay bindings and template visuals are not active.'
local te=TE.new({listFiles=function() return {} end})
te:registerTemplate('templates/default.lua');te:registerTemplate(quickslotsPath)
te:registerTemplate(fixesPath);te:loadTemplatesFromRegister()
assert(#te.registry.templates == 3, 'expected TE, Quickslots and AMM templates')
local consumer
for _,entry in ipairs(te.registry.templates) do
    if entry.template.category=='player.quickslots' then consumer=entry.template end
end
assert(consumer and not consumer.widgetRenderingEnabled, 'expected rendering-disabled consumer template')
local fixes
for _,entry in ipairs(te.registry.templates) do
    if entry.template.category=='menu.fixes' then fixes=entry.template end
end
assert(fixes and fixes.events==nil and fixes.subscribe==nil and fixes.attach==nil,
    'expected inert menu.fixes template')
local catalog
if existing then catalog=assert(loadfile(existing,'t',{}))() end
local menu=te:generateMenu({catalog=catalog,description=description})
local function write(name, content)
    local file=assert(io.open(destination..'/'..name,'wb'));file:write(content);file:close()
end
write('mod_settings.ini',menu.aggregate.manifest)
local pageLines={'return {version=1,pages={'}
for _,page in ipairs(menu.pages) do
    local category=page.category and string.format('%q',page.category) or 'nil'
    local module=page.module and string.format('%q',page.module) or 'nil'
    pageLines[#pageLines+1]=string.format('{id=%q,name=%q,category=%s,module=%s,version=%q,manifest=%q},',
        page.id,page.name,category,module,'0.0.17',page.manifest)
end
pageLines[#pageLines+1]='}}\n';write('menu-pages.lua',table.concat(pageLines,'\n'))
local lines={'return {version=1,next='..menu.catalog.next..',entries={'}
local keys={};for key in pairs(menu.catalog.entries) do keys[#keys+1]=key end;table.sort(keys)
for _,key in ipairs(keys) do lines[#lines+1]=string.format('[%q]=%d,',key,menu.catalog.entries[key]) end
lines[#lines+1]='}}\n';write('identity-catalog.lua',table.concat(lines,'\n'))
write('menu-profile.lua','return {mode="menu-test",templates={"templates/default.lua","../QuickslotsForever/templates/quickslots.lua","../AdaptiveModMenu/templates/fixes.lua"},description='..string.format('%q',description)..'}\n')
write('enabled.txt','')
print('Built '..#menu.rows..' settings across Templates and '..#menu.pages..' routed pages')
