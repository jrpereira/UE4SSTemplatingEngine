local M = {}

local function tuple(source, where)
    local parts = {}
    for part in (source .. ','):gmatch('(.-),') do parts[#parts + 1] = part end
    assert(#parts == 4, where .. ' must contain X,Y,S,O')
    local values = {}
    for index, part in ipairs(parts) do
        assert(part ~= '' and not part:find('%s'), where .. ' contains whitespace or an empty value')
        local value = tonumber(part)
        assert(value and value == value and math.abs(value) <= 1000000000,
            where .. ' contains a non-finite number')
        values[index] = value
    end
    assert(values[3] > 0, where .. ' size must be positive')
    assert(values[4] >= 0 and values[4] <= 1, where .. ' opacity must be 0..1')
    return {x=values[1], y=values[2], size=values[3], opacity=values[4]}
end

function M.parse(source)
    assert(type(source) == 'string' and #source > 0 and #source <= 256,
        'Advanced layout must be a short string')
    assert(not source:find('[%c;#]'), 'Advanced layout contains an INI separator or control')
    local first, second, third = source:match('^([^|]+)|([^|]+)|([^|]+)$')
    assert(first and (first == '0' or first == '1'),
        'Advanced layout must be A|X,Y,S,O|X,Y,S,O with A=0 or 1')
    return {defaultWheel=tonumber(first), first=tuple(second, 'first wheel'),
        second=tuple(third, 'second wheel')}
end

return M
