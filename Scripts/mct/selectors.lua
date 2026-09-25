-- Draft selector graph. Native discovery and identity belong to the host.
local M = {}

function M.compile(targets)
    assert(type(targets) == 'table', 'category.targets must be a table')
    local graph, order, visiting, visited = {}, {}, {}, {}
    for name, value in pairs(targets) do
        assert(type(name) == 'string' and name ~= '', 'selector name required')
        assert(type(value) == 'table', name .. ': selector must be a table')
        for key in pairs(value) do
            assert(key == 'object' or key == 'class' or key == 'within', name .. ': unknown selector field ' .. tostring(key))
        end
        assert((value.object ~= nil) ~= (value.class ~= nil), name .. ': declare object or class')
        local target = value.object or value.class
        assert(type(target) == 'string' and target ~= '', name .. ': selector target required')
        assert(value.within == nil or type(value.within) == 'string', name .. ': invalid within')
        graph[name] = {object=value.object, class=value.class, within=value.within}
    end
    local function visit(name)
        assert(graph[name], 'unknown within selector: ' .. name)
        assert(not visiting[name], 'circular within reference: ' .. name)
        if visited[name] then return end
        visiting[name] = true
        if graph[name].within then visit(graph[name].within) end
        visiting[name], visited[name] = nil, true
        order[#order + 1] = name
    end
    local names = {}
    for name in pairs(graph) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do visit(name) end
    return {byName=graph, order=order}
end

function M.resolve(graph, candidates, host)
    local sets, union = {}, {}
    local function beneath(object, roots)
        local seen = {}
        local parent = host.parent(object)
        while parent ~= nil and host.valid(parent) do
            local id = host.identity(parent)
            if seen[id] then return false end
            if roots[id] then return true end
            seen[id] = true
            parent = host.parent(parent)
        end
        return false
    end
    for _, name in ipairs(graph.order) do
        local selector, matches = graph.byName[name], {}
        for id, object in pairs(candidates) do
            if host.valid(object) and host.matches(object, selector)
                and (not selector.within or beneath(object, sets[selector.within])) then
                matches[id], union[id] = object, object
            end
        end
        sets[name] = matches
    end
    return sets, union
end

return M
