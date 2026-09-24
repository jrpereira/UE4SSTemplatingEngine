-- Event-driven, finite readiness lanes. Native discovery supplies the environment.
local M = {}

function M.new(e)
    assert(type(e.maxAttempts) == 'number' and e.maxAttempts >= 1
        and e.maxAttempts % 1 == 0 and e.maxAttempts < math.huge, 'finite maxAttempts required')
    for _, name in ipairs({'key', 'signature', 'valid', 'relevant', 'enabled', 'queue', 'delay', 'run', 'log'}) do
        assert(type(e[name]) == 'function', 'readiness adapter requires ' .. name)
    end
    local lanes, generation = {}, 0
    local api = {}
    function api:invalidate()
        generation = generation + 1
        lanes = {}
    end
    function api:request(context, kind)
        if not e.enabled() or not e.valid(context) or not e.relevant(context, kind) then return false end
        local key, signature = e.key(context, kind), e.signature(context, kind)
        assert(key ~= nil and signature ~= nil, 'readiness requires target key and signature')
        local previous = lanes[key]
        if previous and previous.context == context and previous.signature == signature then return false end
        -- Reclaim dead references only while handling a real event, never from an idle timer.
        for oldKey, lane in pairs(lanes) do if not e.valid(lane.context) then lanes[oldKey] = nil end end
        local lane = {context = context, signature = signature, epoch = generation, attempts = 0, state = 'queued'}
        lanes[key] = lane
        local function current()
            return generation == lane.epoch and lanes[key] == lane
        end
        local function alive()
            if not current() then return false end
            if not e.enabled() or not e.valid(context) or not e.relevant(context, kind) then
                lane.state = 'cancelled'; return false
            end
            return true
        end
        local function fail(message)
            if current() then lane.state = 'failed' end
            e.log(tostring(message))
        end
        local dispatch
        dispatch = function()
            if not current() then return end
            local queued, why = pcall(e.queue, function()
                if not alive() then return end
                lane.attempts = lane.attempts + 1
                local ok, result = pcall(e.run, context, kind)
                if not ok then fail(result); return end
                if not current() then return end
                if result == 'not_ready' then
                    if lane.attempts >= e.maxAttempts then lane.state = 'exhausted'; return end
                    lane.state = 'waiting'
                    local scheduled, err = pcall(e.delay, 100, dispatch)
                    if not scheduled then fail(err) end
                elseif result == 'applied' or result == 'ignored' then
                    lane.state = 'complete'
                else
                    fail('invalid readiness result: ' .. tostring(result))
                end
            end)
            if not queued then fail(why) end
        end
        dispatch()
        return true
    end
    function api:status(key)
        local lane = lanes[key]
        if not lane then return nil end
        return lane.state, lane.attempts
    end
    return api
end

return M
