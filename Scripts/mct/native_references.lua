-- Non-owning native references for the lifecycle runtime. Engine discovery/readiness
-- signals remain the source's responsibility; construction is not readiness.
local M = {}
function M.new(source, native)
    assert(native and native.version == 1, 'MCT native lifetime service required')
    for _, name in ipairs({'capture', 'valid', 'takeLost'}) do
        assert(type(native[name]) == 'function', 'native lifetimes require ' .. name)
    end
    for _, name in ipairs({'valid', 'ready', 'matches', 'parent', 'find', 'subscribe', 'onError'}) do
        assert(type(source[name]) == 'function', 'object source requires ' .. name)
    end
    local host = {onError=source.onError}
    -- Records own Lua wrappers, never Unreal roots. Ephemeron tables keep references
    -- only as long as a caller/runtime still retains their wrapper or reference.
    local records = setmetatable({}, {__mode='k'})
    local wrappers = setmetatable({}, {__mode='k'})
    local tokens = setmetatable({}, {__mode='v'})
    local sink, getEpoch
    function host.valid(reference)
        local record = records[reference]
        -- Native identity must be checked BEFORE calling into an Unreal object.
        if not record or not native.valid(record.address, record.token) then return false end
        return source.valid(record.object) == true
    end
    function host.capture(object)
        if object == nil then return nil end
        if records[object] then return host.valid(object) and object or nil end
        local cached = wrappers[object]
        -- Never recapture a stale wrapper after its address has been reused.
        if cached then return host.valid(cached) and cached or nil end
        -- GetAddress reads the pointer stored in the Lua wrapper, not object memory.
        local ok, address = pcall(function() return object:GetAddress() end)
        if not ok or type(address) ~= 'number' or address == 0 then return nil end
        local token = native.capture(address)
        if not token then return nil end
        assert(type(token) == 'string', 'native lifetime token must be a string')
        local reference = tokens[token]
        if not reference then
            reference = {}
            records[reference] = {object=object, address=address, token=token}
            tokens[token] = reference
        end
        wrappers[object] = reference
        return host.valid(reference) and reference or nil
    end
    function host.identity(reference)
        return 'mct:' .. assert(records[reference], 'unknown native reference').token
    end
    function host.unwrap(reference)
        if host.valid(reference) then return records[reference].object end
    end
    function host.ready(reference)
        local object = host.unwrap(reference)
        return object ~= nil and source.ready(object) == true
    end
    function host.matches(reference, selector)
        local object = host.unwrap(reference)
        return object ~= nil and source.matches(object, selector) == true
    end
    function host.parent(reference)
        local object = host.unwrap(reference)
        if object ~= nil then return host.capture(source.parent(object)) end
    end
    function host.find(selector)
        local result = {}
        for _, object in ipairs(source.find(selector)) do
            local reference = host.capture(object)
            if reference then result[#result + 1] = reference end
        end
        return result
    end
    -- Drain recorded losses only at explicit lifecycle boundaries, never on a timer.
    -- A future native wakeup can call this on the game thread. Validity is immediate
    -- even if no such boundary occurs and bookkeeping remains until the next event.
    function host.flushLost()
        if not sink then return end
        local epoch = getEpoch()
        while sink do
            local token = native.takeLost()
            if not token then break end
            sink({kind='lost', id='mct:' .. token, epoch=epoch})
        end
    end
    function host.subscribe(callback, epoch)
        assert(not sink, 'native reference host already subscribed')
        sink, getEpoch = callback, epoch
        local active = true
        local ok, unsubscribe = pcall(source.subscribe, function(event)
            if not active then return end
            assert(type(event.epoch) == 'number', 'source event requires its captured epoch')
            host.flushLost()
            if not active then return end
            local translated = {kind=event.kind, epoch=event.epoch}
            if event.kind == 'changed' then
                translated.object = host.capture(event.object)
                if not translated.object then return end
            elseif event.kind == 'lost' then
                -- Capture while still valid or use a previously captured reference.
                local reference = records[event.object] and event.object or wrappers[event.object]
                if not reference then reference = host.capture(event.object) end
                if not reference then return end
                translated.id = host.identity(reference)
            end
            callback(translated)
        end, epoch)
        if not ok or type(unsubscribe) ~= 'function' then
            active, sink, getEpoch = false, nil, nil
            error(ok and 'source.subscribe must return unsubscribe' or unsubscribe)
        end
        return function()
            if not active then return end
            active, sink, getEpoch = false, nil, nil
            unsubscribe()
        end
    end
    return host
end
return M
