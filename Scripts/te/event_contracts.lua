local U = require('te.util')
local M = {}

local contracts = {
    ['player.quickslots'] = {
        requiresTarget = true,
        events = {GroupSelected=true, SlotActivated=true},
    },
}

function M.validate(category, events, where)
    if events == nil then return {} end
    local supported = contracts[category] and contracts[category].events or {}
    local count = U.array(events, where .. '.events')
    local result, seen = {}, {}
    for index = 1, count do
        local event = events[index]
        U.text(event, where .. '.events[' .. index .. ']')
        assert(supported[event], where .. ': unsupported ' .. category .. ' event ' .. event)
        assert(not seen[event], where .. ': duplicate event ' .. event)
        seen[event] = true
        result[event] = true
    end
    return result
end

function M.supports(category, event)
    return contracts[category] ~= nil and contracts[category].events[event] == true
end

function M.requiresTarget(category)
    return contracts[category] ~= nil and contracts[category].requiresTarget == true
end

function M.interested(template, event)
    for _, declared in ipairs(template.events or {}) do
        if declared == event then return true end
    end
    return false
end

return M
