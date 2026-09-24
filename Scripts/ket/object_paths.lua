local U = require('ket.util')
local M = {}

-- A category stores the stable blueprint object path. Its live instance has
-- transient outer names, so match the class and final widget name instead.
function M.findLive(declared, findAll, valid)
    U.text(declared, 'category path')
    assert(type(findAll) == 'function', 'object enumeration adapter required')
    local class, path = declared:match('^(%S+)%s+(.+)$')
    assert(class and path:sub(1, 1) == '/', 'expected class-qualified UE object path')
    local name = path:match('%.([^%.:]+)$')
    assert(name, 'category path must end in an object name')
    local ok, objects = pcall(findAll, class)
    if not ok or type(objects) ~= 'table' then return nil end
    for _, object in ipairs(objects) do
        local alive = valid and valid(object)
        if valid == nil then
            local status, result = pcall(function() return object:IsValid() end)
            alive = status and result == true
        end
        if alive then
            local named, full = pcall(function() return object:GetFullName() end)
            if named and type(full) == 'string'
                and full:sub(1, #class + 1) == class .. ' '
                and full:find('/Engine/Transient', 1, true)
                and full:sub(-#name - 1) == '.' .. name then
                return object
            end
        end
    end
end

return M
