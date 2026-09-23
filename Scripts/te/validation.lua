local U = require('te.util')
local Provider = require('te.provider_settings')
local Events = require('te.event_contracts')
local M = {}

function M.actions(actions, where)
    assert(type(actions) == 'table' and next(actions), where .. ': expected nonempty actions table')
    if type(actions[1]) == 'table' and actions[1].slot ~= nil then
        U.array(actions, where)
        local grouped, positions, seen = {}, {}, {}
        for index, action in ipairs(actions) do
            local loc = where .. '[' .. index .. ']'
            assert(type(action) == 'table', loc .. ': expected slot action')
            U.text(action.type, loc .. '.type')
            U.text(action.slot, loc .. '.slot')
            local kind = action.type:lower()
            assert(kind == 'ability' or kind == 'consumable', loc .. ': unsupported quickslot type ' .. action.type)
            local identity = kind .. '\0' .. action.slot
            assert(not seen[identity], loc .. ': duplicate quickslot action')
            seen[identity] = true
            local position = positions[kind]
            if not position then
                position = #grouped + 1
                positions[kind] = position
                grouped[position] = {name = kind == 'ability' and 'Abilities' or 'Consumables',
                    type = kind, slots = 0, slotNames = {}}
            end
            local group = grouped[position]
            group.slots = group.slots + 1
            group.slotNames[#group.slotNames + 1] = action.slot
        end
        return grouped
    end
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
        if group.contexts ~= nil then
            U.array(group.contexts, loc .. '.contexts')
            for i, context in ipairs(group.contexts) do U.text(context, loc .. '.contexts[' .. i .. ']') end
        end
    end
    if shape == 'number' then U.array(actions, where) end
    return actions
end

function M.template(template, categories, where, runtime)
    assert(type(template) == 'table', where .. ': expected template object')
    assert(template.collection == nil, where .. '.collection: removed field')
    U.text(template.category, where .. '.category')
    assert(categories:contains(template.category), where .. ': unregistered category ' .. template.category)
    local category = categories:getCategory(template.category)
    U.text(template.name, where .. '.name')
    assert(template.single == nil or type(template.single) == 'boolean',
        where .. '.single: expected boolean or nil')
    assert(template.providerSettings == nil, where .. '.providerSettings: renamed to settings')
    Provider.normalize(template.settings)
    assert(template.modules==nil,where..'.modules: declare native targets inside events')
    Events.validate(template.category, category.events or template.events, template.subscribe, where)
    if template.category == 'player.quickslots' then
        M.actions(category.actions or template.actions, where .. '.actions')
        if template.actionOrder ~= nil then M.orderedGroups(template, nil, category.actions) end
    end
    if category.contexts ~= nil then
        U.array(category.contexts, where .. '.category.contexts')
        for i, context in ipairs(category.contexts) do U.text(context, where .. '.category.contexts[' .. i .. ']') end
    end
    if template.contexts ~= nil then
        assert(template.category~='npc.attacks',where..'.contexts: declare contexts inside target events')
        U.array(template.contexts, where .. '.contexts')
        for i, context in ipairs(template.contexts) do U.text(context, where .. '.contexts[' .. i .. ']') end
    end
    local inert=template.category=='menu.fixes' and template.attach==nil
        and template.detach==nil and template.render==nil
    for _, method in ipairs({'attach', 'detach', 'render'}) do
        assert(inert or (not runtime and template[method] == nil) or type(template[method]) == 'function',
            where .. '.' .. method .. ': expected function' .. (runtime and '' or ' or nil'))
    end
    return template
end

function M.flatten(value, categories, where, header)
    assert(header == nil or type(header) == 'table', where .. ': expected header table')
    local out, visiting = {}, {}
    local function visit(item, path)
        assert(type(item) == 'table', path .. ': expected template or array')
        assert(not visiting[item], path .. ': cyclic template array')
        -- Partial objects must receive object diagnostics, not array errors.
        local object = rawget(item, 'category') ~= nil or rawget(item, 'name') ~= nil
        if header and not object then
            for key in pairs(item) do
                if type(key) == 'string' then object = true; break end
            end
        end
        if object then
            local template = item
            if header then
                template = U.copy(header)
                for key, field in pairs(item) do template[key] = U.copy(field) end
            end
            M.template(template, categories, path, false)
            out[#out + 1] = {template = template, location = path}
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
function M.orderedGroups(template, order, categoryActions)
    local actions = M.actions(categoryActions or template.actions, template.name .. '.actions')
    if template.actionOrder ~= nil then
        local count = U.array(template.actionOrder, 'actionOrder')
        if order ~= nil then
            assert(U.array(order, 'group order') == count, 'cannot override declared actionOrder')
            for i = 1, count do assert(order[i] == template.actionOrder[i], 'cannot override declared actionOrder') end
        end
        order = template.actionOrder
    end
    local result, used = {}, {}
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
