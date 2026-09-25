-- Connect the verified all-modules barrier to bootstrap; native object host is separate.
local Bootstrap = require('mct.bootstrap')
local M = {}
function M.start(options, api)
    api = api or _G
    assert(api.MCTNative and api.MCTNative.version == 1
        and api.MCTNative.boundary == 'first_mct_update_after_all_modules'
        and type(api.MCTNative.onLoopStart) == 'function',
        'MCT native Loop Start helper for UE4SS 97b7e501 is required')
    assert(type(api.ExecuteInGameThread) == 'function', 'game-thread dispatch unavailable')
    assert(type(api.MCTNative.registeredTemplates) == 'function',
        'native cross-module registration service required')
    local configured = {}
    for key, value in pairs(options) do configured[key] = value end
    assert(not configured.subscribeLoopStart and not configured.startOnGameThread,
        'native startup owns the Loop Start and game-thread adapters')
    if not configured.host and not configured.objectSource then
        local definitions = {}
        local execute = configured.execute or function(path) return assert(loadfile(path))() end
        for _, path in ipairs(configured.categoryFiles or {}) do
            definitions[#definitions+1] = execute(path)
        end
        configured.objectSource = require('mct.widget_source').new(definitions, api)
    end
    if configured.objectSource then
        assert(not configured.host, 'supply either objectSource or host')
        local source = configured.objectSource
        configured.host = require('mct.native_references').new(source,
            api.MCTNative.lifetimes)
        configured.closeHost = source.stop
        configured.objectSource = nil
    end
    configured.consumeRegistrations = api.MCTNative.registeredTemplates
    configured.subscribeLoopStart = api.MCTNative.onLoopStart
    configured.startOnGameThread = api.ExecuteInGameThread
    configured.queue = api.ExecuteInGameThread
    if configured.menuRoot then configured.menuShared = assert(api.ModRef, 'ModRef unavailable') end
    return Bootstrap.new(configured)
end
return M
