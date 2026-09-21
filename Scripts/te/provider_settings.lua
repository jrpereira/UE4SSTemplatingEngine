local U = require('te.util')
local M = {}
local function finite(v) return type(v) == 'number' and v == v and math.abs(v) <= 1000000000 end
local function text(v, where)
    U.text(v, where)
    assert(#v <= 4096 and not v:find('[%c|;%[%]]') and not v:match('^%s') and not v:match('%s$'),
        where .. ': unsupported metadata text')
    return v
end
local function identifier(v, where)
    text(v, where)
    assert(#v <= 128 and v:match('^[%a_][%w_]*$'), where .. ': invalid stable identifier')
end
local function level(v)
    assert(v == nil or (finite(v) and v % 1 == 0 and (v == 0 or (v >= 2 and v <= 6))),
        'provider level must be 0 or 2..6; level 1 is reserved for the page header')
end
local function allowed(value, names, where)
    for name in pairs(value) do assert(names[name], where .. ': unsupported property ' .. tostring(name)) end
end
local function order(value, index)
    assert(value == nil or finite(value), 'provider order must be finite')
    return value or index
end
local function sort(a, b)
    if a.order == b.order then return a.index < b.index end
    return a.order < b.order
end

function M.normalize(declaration)
    if declaration == nil then return {} end
    assert(type(declaration) == 'table', 'settings must be a table')
    allowed(declaration, {groups=true,fields=true}, 'settings')
    U.array(declaration.groups, 'settings.groups')
    U.array(declaration.fields, 'settings.fields')
    local groups, byId, fields = {}, {}, {}
    for index, source in ipairs(declaration.groups) do
        assert(type(source) == 'table', 'provider group must be a table')
        allowed(source, {id=true,label=true,level=true,order=true}, 'provider group')
        identifier(source.id, 'provider group id'); text(source.label, 'provider group label'); level(source.level)
        assert(not byId[source.id], 'duplicate provider group ' .. source.id)
        local g = {id=source.id,label=source.label,level=source.level or 4,
            order=order(source.order,index),index=index,fields={}}
        groups[#groups+1], byId[source.id] = g, g
    end
    for index, source in ipairs(declaration.fields) do
        assert(type(source) == 'table', 'provider field must be a table')
        allowed(source, {id=true,label=true,group=true,type=true,order=true,default=true,values=true,
            labels=true,min=true,max=true,step=true,suffix=true,tab=true,level=true,description=true}, 'provider field')
        identifier(source.id, 'provider field id'); text(source.label, 'provider field label'); level(source.level)
        assert(not fields[source.id], 'duplicate provider field ' .. source.id)
        fields[source.id] = true
        local group = assert(byId[source.group], 'undeclared provider group: ' .. tostring(source.group))
        local field = U.copy(source)
        field.order, field.index = order(source.order,index), index
        if field.description ~= nil then text(field.description, 'provider description') end
        if field.suffix ~= nil then text(field.suffix, 'provider suffix') end
        assert(field.tab == nil or type(field.tab) == 'boolean', 'provider tab must be boolean')
        if field.type == 'integer' then
            assert(field.values == nil and field.labels == nil and not field.tab, 'integer cannot declare choices/tabs')
            field.step = field.step or 1
            for _, name in ipairs({'min','max','step','default'}) do
                assert(finite(field[name]) and field[name] % 1 == 0, 'provider integer ' .. name .. ' required')
            end
            assert(field.min < field.max and field.step >= 1 and field.step <= field.max-field.min,
                'invalid provider integer range/step')
            assert(field.default >= field.min and field.default <= field.max, 'provider default outside range')
        elseif field.type == 'picker' then
            assert(field.min == nil and field.max == nil and field.step == nil and field.suffix == nil,
                'picker cannot declare integer range/suffix')
            local count = U.array(field.values, 'provider picker values')
            assert(count >= 2 and count <= 64 and U.array(field.labels, 'provider picker labels') == count,
                'provider picker requires 2..64 matching choices')
            assert(not field.tab or count <= 8, 'provider tabs support at most 8 choices')
            local seen = {}
            for i, value in ipairs(field.values) do
                assert(finite(value) and not seen[value], 'invalid/duplicate provider choice')
                seen[value] = true; text(field.labels[i], 'provider choice label')
            end
            assert(finite(field.default) and seen[field.default], 'provider default must match a choice')
        else error('unsupported provider field type: ' .. tostring(field.type)) end
        group.fields[#group.fields+1] = field
    end
    table.sort(groups, sort)
    for _, group in ipairs(groups) do
        assert(#group.fields > 0, 'empty provider group: ' .. group.id)
        table.sort(group.fields, sort)
    end
    return groups
end

function M.validate(declaration, committed)
    if declaration == nil then
        assert(committed == nil, 'template does not declare settings')
        return nil
    end
    assert(type(committed) == 'table', 'committed settings are required')
    local expected = {}
    for _, group in ipairs(M.normalize(declaration)) do
        for _, field in ipairs(group.fields) do
            expected[field.id] = true
            local value = committed[field.id]
            assert(finite(value), 'missing/invalid provider setting ' .. field.id)
            if field.type == 'integer' then
                assert(value % 1 == 0 and value >= field.min and value <= field.max,
                    'provider setting outside range ' .. field.id)
            else
                local found = false
                for _, candidate in ipairs(field.values) do if value == candidate then found = true end end
                assert(found, 'invalid provider choice ' .. field.id)
            end
        end
    end
    for name in pairs(committed) do
        assert(expected[name], 'unknown provider setting ' .. tostring(name))
    end
    return committed
end

return M
