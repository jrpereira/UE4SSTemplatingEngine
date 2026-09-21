local U = require('te.util')
local M = {}

function M.new()
    local self = {entries = {}}
    function self:registerCategory(root, children)
        U.text(root, 'category')
        assert(root:match('^[%a_][%w_]*$'), 'category: invalid root name')
        U.array(children, root .. ' subcategories')
        local pending = {[root] = true}
        assert(not self.entries[root], 'duplicate category: ' .. root)
        for _, child in ipairs(children) do
            U.text(child, root .. ' subcategory')
            assert(child:match('^[%a_][%w_]*$'), 'invalid subcategory: ' .. child)
            local name = root .. '.' .. child
            assert(not pending[name] and not self.entries[name], 'duplicate category: ' .. name)
            pending[name] = true
        end
        for name in pairs(pending) do self.entries[name] = true end
    end
    function self:contains(name) return self.entries[name] == true end
    function self:list()
        local names = {}
        for name in pairs(self.entries) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
    return self
end

return M
