local VERSION = '0.0.20'
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate KET Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate KET module')
package.path = scripts .. '/?.lua;' .. package.path
local function log(message) print('[ModCoreTemplates] ' .. tostring(message) .. '\n') end
local ok, err = pcall(function()
    assert(type(ExecuteInGameThread) == 'function', 'game-thread dispatch unavailable')
    local Settings = require('ket.settings_api')
    require('ket.menu_host').start(root, Settings, ExecuteInGameThread, log)
end)
if not ok then log(VERSION .. ' startup failed: ' .. tostring(err))
else log(VERSION .. ' loaded; template input activates after a committed Apply') end
