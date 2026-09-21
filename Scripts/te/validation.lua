local U = require('te.util')
local Provider = require('te.provider_settings')
local Events = require('te.event_contracts')
local M = {}

function M.actions(actions, where)
    assert(type(actions) == 'table' and next(actions), where .. ': expected nonempty actions table')
    local shape
    for key, group in pairs(actions) do
        local kind = type(key)
        assert(kind == 'string' or kind == 'number', where .. ': invalid group key')
        assert(not shape or shape == kind, where .. ': mixed group keys')
        shape = kind
        if kind == 'string' then U.text(key, where .. ' group key') end
        local loc = where .. '[' .. tostring(key) .. ']'
        assert(type(group) == 'table', loc .. ': expected group table')
        U.text(group.name, loc .. '.name')
        U.text(group.type, loc .. '.type')
        assert(type(group.slots) == 'number' and group.slots >= 1 and group.slots % 1 == 0
            and group.slots < math.huge, loc .. '.slots: expected positive integer')
    end
    if shape == 'number' then U.array(actions, where) end
end

function M.template(template, categories, where, runtime)
    assert(type(template) == 'table', where .. ': expected template object')
    U.text(template.collection, where .. '.collection')
    U.text(template.category, where .. '.category')
    assert(categories:contains(template.category), where .. ': unregistered category ' .. template.category)
    U.text(template.name, where .. '.name')
    assert(template.providerSettings == nil, where .. '.providerSettings: renamed to settings')
    Provider.normalize(template.settings)
    Events.validate(template.category, template.events, where)
    if template.category == 'player.quickslots' then
        M.actions(template.actions, where .. '.actions')
        if template.actionOrder ~= nil then M.orderedGroups(template) end
    end
    if template.contexts ~= nil then
        U.array(template.contexts, where .. '.contexts')
        for i, context in ipairs(template.contexts) do U.text(context, where .. '.contexts[' .. i .. ']') end
    end
    for _, method in ipairs({'attach', 'detach', 'render'}) do
        assert((not runtime and template[method] == nil) or type(template[method]) == 'function',
            where .. '.' .. method .. ': expected function' .. (runtime and '' or ' or nil'))
    end
    return template
end

function M.flatten(value, categories, where)
    local out, visiting = {}, {}
    local function visit(item, path)
        assert(type(item) == 'table', path .. ': expected template or array')
        assert(not visiting[item], path .. ': cyclic template array')
        -- Partial objects must receive object diagnostics, not array errors.
        if rawget(item, 'collection') ~= nil or rawget(item, 'category') ~= nil
            or rawget(item, 'name') ~= nil then
            M.template(item, categories, path, false)
            out[#out + 1] = {template = item, location = path}
            return
        end
        visiting[item] = true
        local count = U.array(item, path)
        for i = 1, count do visit(item[i], path .. '[' .. i .. ']') end
        visiting[item] = nil
    end
    visit(value, where)
    return out
end

-- Ordering is an explicit adapter input, not inferred from Lua map traversal.
function M.orderedGroups(template, order)
    M.actions(template.actions, template.name .. '.actions')
    if template.actionOrder ~= nil then
        local count = U.array(template.actionOrder, 'actionOrder')
        if order ~= nil then
            assert(U.array(order, 'group order') == count, 'cannot override declared actionOrder')
            for i = 1, count do assert(order[i] == template.actionOrder[i], 'cannot override declared actionOrder') end
        end
        order = template.actionOrder
    end
    local actions, result, used = template.actions, {}, {}
    if type(next(actions)) == 'number' then
        assert(order == nil, 'array actions already define their order')
        for i, group in ipairs(actions) do result[i] = {key = tostring(i), value = group} end
    else
        assert(order, template.name .. ': explicit group order required for named actions')
        U.array(order, 'group order')
        for _, key in ipairs(order) do
            assert(type(key) == 'string' and actions[key] and not used[key], 'invalid/duplicate group order entry')
            used[key] = true
            result[#result + 1] = {key = key, value = actions[key]}
        end
        for key in pairs(actions) do assert(used[key], 'group order missing ' .. key) end
    end
    return result
end

return M
