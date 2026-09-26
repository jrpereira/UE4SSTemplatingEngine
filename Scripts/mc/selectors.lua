-- Category selector graph. Native discovery and identity belong to the host.
local M = {}
local TemplateTargets = require('mc.template_targets')

function M.compile(targets)
    assert(type(targets) == 'table', 'category.targets must be a table')
    local graph, order, visiting, visited = {}, {}, {}, {}
    for name, value in pairs(targets) do
        assert(type(name) == 'string' and name ~= '', 'selector name required')
        assert(type(value) == 'table', name .. ': selector must be a table')
        for key in pairs(value) do
            assert(key == 'object' or key == 'class' or key == 'within' or key == 'from'
                or key == 'member' or key == 'attach' or key == 'required' or key == 'properties',
                name .. ': unknown selector field ' .. tostring(key))
        end
        assert(not (value.from and value.within), name .. ': from and within are exclusive')
        if value.from then
            assert(type(value.from) == 'string' and value.from ~= '', name .. ': invalid from')
            assert(value.object == nil and (value.member ~= nil or value.class ~= nil),
                name .. ': scoped selector needs a member or class')
        else
            assert(value.member == nil and (value.object ~= nil) ~= (value.class ~= nil),
                name .. ': declare object or class')
        end
        local target = value.object or value.class or value.member
        assert(type(target) == 'string' and target ~= '', name .. ': selector target required')
        assert(value.within == nil or type(value.within) == 'string', name .. ': invalid within')
        assert(value.attach == nil or type(value.attach) == 'boolean', name .. ': invalid attach')
        assert(value.required == nil or type(value.required) == 'boolean', name .. ': invalid required')
        assert(value.properties == nil or type(value.properties) == 'table', name .. ': invalid properties')
        assert(not value.from or value.attach == nil, name .. ': scoped targets cannot attach independently')
        graph[name] = {object=value.object, class=value.class, within=value.within,
            from=value.from, member=value.member, attach=value.attach ~= false,
            required=value.required == true,properties=value.properties}
    end
    local function visit(name)
        assert(graph[name], 'unknown within selector: ' .. name)
        assert(not visiting[name], 'circular within reference: ' .. name)
        if visited[name] then return end
        visiting[name] = true
        if graph[name].within then visit(graph[name].within) end
        if graph[name].from then visit(graph[name].from) end
        visiting[name], visited[name] = nil, true
        order[#order + 1] = name
    end
    local names = {}
    for name in pairs(graph) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do visit(name) end
    local roots = {}
    for _, name in ipairs(order) do
        local selector = graph[name]
        roots[name] = selector.from and roots[selector.from] or name
    end
    return {byName=graph, order=order, roots=roots}
end

-- A template requests only the category targets it names and their dependencies.
function M.project(graph, targets)
    local _, names=TemplateTargets.compile(graph,targets)
    local wanted={}
    local function include(name)
        local selector=graph.byName[name]
        assert(selector, 'unknown template target: '..tostring(name))
        if wanted[name] then return end
        wanted[name]=true
        if selector.from then include(selector.from) end
        if selector.within then include(selector.within) end
    end
    for _,name in ipairs(names) do include(name) end
    local projected={byName={},order={},roots={}}
    for _,name in ipairs(graph.order) do
        if wanted[name] then
            projected.byName[name]=graph.byName[name]
            projected.order[#projected.order+1]=name
            projected.roots[name]=graph.roots[name]
        end
    end
    return projected
end

function M.resolve(graph, candidates, host)
    local sets, union, bundles = {}, {}, {}
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
        if selector.from then
            for id, bundle in pairs(bundles) do
                local parent = bundle[selector.from]
                if parent and host.valid(parent) then
                    local object
                    if selector.member then object = host.member(parent, selector.member)
                    else object = host.child(parent, selector.class) end
                    if object and host.valid(object)
                        and (not selector.class or host.matches(object, selector)) then
                        bundle[name] = object
                        matches[host.identity(object)] = object
                    end
                end
            end
        else
            for id, object in pairs(candidates) do
                if host.valid(object) and host.matches(object, selector)
                    and (not selector.within or beneath(object, sets[selector.within])) then
                    matches[id] = object
                    if selector.attach then union[id] = object end
                    bundles[id] = bundles[id] or {}
                    bundles[id][name] = object
                end
            end
        end
        sets[name] = matches
    end
    for id, bundle in pairs(bundles) do
        if union[id] then
            for name, selector in pairs(graph.byName) do
                if selector.from and selector.required
                    and bundle[graph.roots[name]] == union[id] and bundle[name] == nil then
                    union[id] = nil
                    break
                end
            end
        end
    end
    return sets, union, bundles
end

return M
