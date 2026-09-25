-- Injected by the native helper before MCT main.lua executes.
-- The returned closure is called once, on the first UE4SS update after loading.
local callbacks, fired = {}, false
local api = {version=1, boundary='first_mct_update_after_all_modules'}
function api.onLoopStart(callback)
    assert(type(callback) == 'function', 'Loop Start callback required')
    assert(not fired, 'Loop Start already fired for this Lua session')
    local record = {callback=callback}
    callbacks[#callbacks + 1] = record
    return function() record.callback = nil end
end
-- Capture the native session once. Old queued Lua closures cannot borrow a new session.
if type(MCTNativeLifetimeSession) == 'function' then
    local session = MCTNativeLifetimeSession()
    local capture, valid, takeLost = MCTNativeCapture, MCTNativeValid, MCTNativeTakeLost
    api.lifetimes = {
        version = 1,
        capture = function(address) return capture(session, address) end,
        valid = function(address, token) return valid(session, address, token) end,
        takeLost = function() return takeLost(session) end,
    }
end
if type(MCTNativeTakeRegisteredTemplates) == 'function' then
    local session = MCTNativeLifetimeSession()
    local take = MCTNativeTakeRegisteredTemplates
    api.registeredTemplates = function()
        local payload = assert(take(session), 'MCT native registration session ended')
        local paths = {}
        for path in payload:gmatch('[^\n]+') do paths[#paths+1] = path end
        return paths
    end
end
MCTNative = api
return function()
    if fired then return end
    fired = true
    local pending = callbacks
    callbacks = {}
    for _, record in ipairs(pending) do
        local callback = record.callback
        record.callback = nil
        if callback then
            local ok, why = pcall(callback)
            if not ok then print('[MCT] Loop Start callback failed: ' .. tostring(why) .. '\n') end
        end
    end
end
