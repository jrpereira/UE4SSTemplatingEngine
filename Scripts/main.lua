local VERSION = '0.0.17'
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate TE Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate TE module')
package.path = scripts .. '/?.lua;' .. package.path
local function log(message) print('[UE4SSTemplatingEngine] ' .. tostring(message) .. '\n') end
local ok, err = pcall(function()
    assert(type(ExecuteInGameThread) == 'function', 'game-thread dispatch unavailable')
    local Settings = require('te.settings_api')
    require('te.menu_host').start(root, Settings, ExecuteInGameThread, log)
end)
if not ok then log(VERSION .. ' startup failed: ' .. tostring(err))
else log(VERSION .. ' loaded; no native gameplay cutover') end
