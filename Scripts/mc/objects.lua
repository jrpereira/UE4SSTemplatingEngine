-- Shared helpers for live UE4SS objects; these do not own or retain objects.
local M = {}

function M.call(object, method, ...)
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
end

function M.valid(object)
    return object ~= nil and M.call(object, 'IsValid') == true
end

-- Compare current live wrappers. This is not a persistent lifetime identity.
function M.same(a, b)
    if not M.valid(a) or not M.valid(b) then return false end
    local name = M.call(a, 'GetFullName')
    return type(name) == 'string' and name ~= '' and name == M.call(b, 'GetFullName')
end

-- UMG panel parent, not UObject outer ownership.
function M.parent(object)
    if not M.valid(object) then return nil end
    local parent = M.call(object, 'GetParent')
    return M.valid(parent) and parent or nil
end

return M
