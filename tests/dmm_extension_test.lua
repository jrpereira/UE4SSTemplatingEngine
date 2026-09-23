local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local cwdPipe = assert(io.popen(package.config:sub(1, 1) == '\\' and 'cd' or 'pwd'))
local root = assert(cwdPipe:read('*l')); cwdPipe:close()

local pagePath = 'menu-pages.lua'
local previous
local existing = io.open(pagePath, 'rb')
if existing then previous = existing:read('*a'); existing:close() end

local fixture = [[return {version=1,pages={
    {id='UE4SSTemplatingEngine.player.quickslots',name='Player Quickslots',category='player.quickslots',manifest='quickslots'},
    {id='UE4SSTemplatingEngine.player.stats',name='Player Stats',category='player.stats',manifest='stats'},
    {id='UE4SSTemplatingEngine.module.QuickslotsForever',name='QuickslotsForever',module='QuickslotsForever',manifest='module'},
}}]]
local file = assert(io.open(pagePath, 'wb')); file:write(fixture); file:close()

local ok, failure = xpcall(function()
    local forwarded
    local providers = {
        {id='zulu',name='Zulu',testOnly=false},
        {id='UE4SSTemplatingEngine',name='Templates',testOnly=false},
        {id='alpha',name='Alpha',testOnly=false},
        {id='beta',name='Beta',testOnly=false},
        {id='detected:ue4ss:quickslotsforever',name='QuickslotsForever',testOnly=false,noSettings=true},
        {id='test',name='A Test Provider',testOnly=true},
    }
    local tree, status, hostApi = {}, {}, {}
    local buildApi = {
        choices = {parse = function(manifest) return {{Id=manifest}} end},
        pages = {build = function(actualTree, actualProviders, actualStatus, actualHostApi)
            forwarded = {tree=actualTree,providers=actualProviders,status=actualStatus,hostApi=actualHostApi}
            return 'built'
        end},
    }
    local savedBoot = package.loaded['te.menu_boot']
    package.loaded['te.menu_boot'] = {prepare=function()
        return {}, {pages=assert(loadfile(pagePath, 't', {}))().pages}
    end}
    local extension=dofile(root..'/Scripts/dmm_extension.lua')
    package.loaded['te.menu_boot'] = savedBoot
    check(extension.install(buildApi)==nil)
    check(extension.install(buildApi)==false)
    check(buildApi.pages.build(tree, providers, status, hostApi) == 'built')
    check(forwarded.tree == tree and forwarded.providers == providers
        and forwarded.status == status and forwarded.hostApi == hostApi)
    local expected = {'alpha','beta','UE4SSTemplatingEngine.module.QuickslotsForever','UE4SSTemplatingEngine',
        'UE4SSTemplatingEngine.player.quickslots','UE4SSTemplatingEngine.player.stats','zulu','test'}
    check(#providers == #expected)
    for index, id in ipairs(expected) do check(providers[index].id == id, 'provider order mismatch at '..index) end
    for index = 5, 6 do
        check(providers[index].ammBrowserLevel == 4)
        check(providers[index].ammBrowserIndent == 20)
        check(providers[index].settingsCount == 1 and #providers[index].choices == 1)
    end
    check(providers[3].ammBrowserLevel == nil and providers[3].ammBrowserIndent == nil
        and providers[3].name == 'QuickslotsForever')
    check(buildApi.pages.build(tree, providers, status, hostApi) == 'built')
    check(#providers == #expected)
    for index, id in ipairs(expected) do check(providers[index].id == id, 'rebuild order mismatch at '..index) end
end, debug.traceback)

if previous ~= nil then
    local restore = assert(io.open(pagePath, 'wb')); restore:write(previous); restore:close()
else
    os.remove(pagePath)
end
assert(ok, failure)
print('DMM extension: '..checks..' checks passed')
