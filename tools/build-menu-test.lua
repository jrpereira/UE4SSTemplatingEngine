package.path = 'Scripts/?.lua;' .. package.path
local KET = require('ket.init')
local CategoryFiles = require('ket.category_files')
local quickslotsPath, destination, existing = assert(arg[1]), assert(arg[2]), arg[3]
local description = 'Menu test: Action Fandango quickslot layouts and input activate after Apply.'
local ket=KET.new({listFiles=function() return {} end})
ket:registerTemplate('Scripts/default.lua');ket:registerTemplate(quickslotsPath)
ket:loadTemplatesFromRegister()
assert(#ket.registry.templates == 2, 'expected KET Default and Action Fandango Wheels++ templates')
local consumers = {}
for _,entry in ipairs(ket.registry.templates) do
    if entry.template.category=='player.quickslots' then consumers[entry.template.name]=true end
end
assert(consumers['Wheels++'], 'expected Action Fandango Wheels++ template')
local catalog
if existing then catalog=assert(loadfile(existing,'t',{}))() end
local menu=ket:generateMenu({catalog=catalog,description=description})
local function write(name, content)
    local file=assert(io.open(destination..'/'..name,'wb'));file:write(content);file:close()
end
write('mod_settings.ini',menu.aggregate.manifest)
local pageLines={'return {version=1,pages={'}
for _,page in ipairs(menu.pages) do
    local category=page.category and string.format('%q',page.category) or 'nil'
    local module=page.module and string.format('%q',page.module) or 'nil'
    pageLines[#pageLines+1]=string.format('{id=%q,name=%q,category=%s,module=%s,version=%q,manifest=%q},',
        page.id,page.name,category,module,'0.0.20',page.manifest)
end
pageLines[#pageLines+1]='}}\n';write('menu-pages.lua',table.concat(pageLines,'\n'))
local lines={'return {version=1,next='..menu.catalog.next..',entries={'}
local keys={};for key in pairs(menu.catalog.entries) do keys[#keys+1]=key end;table.sort(keys)
for _,key in ipairs(keys) do lines[#lines+1]=string.format('[%q]=%d,',key,menu.catalog.entries[key]) end
lines[#lines+1]='}}\n';write('identity-catalog.lua',table.concat(lines,'\n'))
local categoryPaths = CategoryFiles.list('Scripts/categories')
local categories = {}
for _, path in ipairs(categoryPaths) do categories[#categories + 1] = string.format('%q', path) end
write('menu-profile.lua','return {mode="menu-test",categories={'..table.concat(categories,',')..'},templates={"Scripts/default.lua","../ActionFandango/Scripts/templates/main.lua"},description='..string.format('%q',description)..'}\n')
write('enabled.txt','')
print('Built '..#menu.rows..' settings across Templates and '..#menu.pages..' routed pages')
