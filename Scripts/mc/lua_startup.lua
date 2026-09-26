-- Start the self-contained Lua runtime on UE4SS's game thread.
local Bootstrap = require('mc.bootstrap')
local M = {}
function M.start(options, api)
    api = api or _G
    assert(type(api.ExecuteInGameThread) == 'function', 'game-thread dispatch unavailable')
    local configured = {}
    for key, value in pairs(options) do configured[key] = value end
    if not configured.host and not configured.objectSource then
        local definitions = {}
        local execute = configured.execute or function(path) return assert(loadfile(path))() end
        for _, path in ipairs(configured.categoryFiles or {}) do
            definitions[#definitions+1] = execute(path)
        end
        configured.objectSource = require('mc.widget_source').new(definitions, api)
    end
    if configured.objectSource then
        assert(not configured.host, 'supply either objectSource or host')
        local source = configured.objectSource
        configured.host = require('mc.lua_references').new(source)
        configured.closeHost = source.stop
        configured.objectSource = nil
    end
    configured.subscribeLoopStart = function(callback)
        local active = true
        api.ExecuteInGameThread(function() if active then callback() end end)
        return function() active = false end
    end
    configured.startOnGameThread = api.ExecuteInGameThread
    configured.queue = api.ExecuteInGameThread
    if configured.menuRoot then configured.menuShared = assert(api.ModRef, 'ModRef unavailable') end
    return Bootstrap.new(configured)
end
return M
