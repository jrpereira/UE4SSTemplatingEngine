package.path = 'Scripts/?.lua;' .. package.path
local Files = require('ket.category_files')
local KET = require('ket.init')

local folder = 'work/category-discovery'
assert(os.execute('mkdir -p ' .. folder))
local function write(name, content)
    local file = assert(io.open(folder .. '/' .. name, 'wb'))
    assert(file:write(content)); assert(file:close())
end
write('demo_feature.lua', "return {name='demo.feature',single=true}\n")
write('ignored.txt', 'not a category')
local files = Files.list(folder)
assert(#files == 1 and files[1] == folder .. '/demo_feature.lua')
local ket = KET.new({categoriesFolder=folder,listFiles=function() return {} end})
assert(table.concat(ket.categories:list(), ',') == 'demo.feature')
assert(ket.categories:getCategory('demo.feature').single == true)
write('external.lua', "return {name='other.notice'}\n")
assert(ket:loadCategory('other.notice', folder .. '/external.lua'))
assert(ket.categories:contains('other.notice'))
os.remove(folder .. '/external.lua')
write('demo_other.lua', "return {name='demo.other'}\n")
ket = KET.new({categoriesFolder=folder,listFiles=function() return {} end})
assert(table.concat(ket.categories:list(), ',') == 'demo.feature,demo.other')
write('duplicate.lua', "return {name='demo.other'}\n")
local ok, why = pcall(KET.new, {categoriesFolder=folder,listFiles=function() return {} end})
assert(not ok and tostring(why):find('duplicate category',1,true))
os.remove(folder .. '/duplicate.lua')
local original = IterateGameDirectories
IterateGameDirectories = function()
    return {Game={Mods={Scripts={categories={__absolute_path=folder,__files={
        {__name='demo_feature.lua',__absolute_path=folder .. '/demo_feature.lua'},
        {__name='ignored.txt',__absolute_path=folder .. '/ignored.txt'},
    }}}}}}
end
files = Files.list(folder)
assert(#files == 1 and files[1] == folder .. '/demo_feature.lua')
IterateGameDirectories = original
os.remove(folder .. '/demo_feature.lua')
os.remove(folder .. '/demo_other.lua')
os.remove(folder .. '/ignored.txt')
print('category discovery: direct boot loading and UE4SS directory adapter passed')
