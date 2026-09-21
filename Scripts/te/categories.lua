local U = require('te.util')
local M = {}

function M.new()
    local self = {_categories = {}}
    function self:registerCategory(module, categories)
        U.text(module, 'category')
        assert(module:match('^[%a_][%w_]*$'), 'category: invalid root name')
        U.array(categories, module .. ' subcategories')
        assert(not self._categories[module], 'duplicate category: ' .. module)
        local registered = {}
        for _, category in ipairs(categories) do
            U.text(category, module .. ' subcategory')
            assert(category:match('^[%a_][%w_]*$'), 'invalid subcategory: ' .. category)
            assert(not registered[category], 'duplicate category: ' .. module .. '.' .. category)
            registered[category] = {}
        end
        self._categories[module] = registered
    end
    function self:contains(name)
        local module, category = name:match('^([^.]+)%.([^.]+)$')
        if module then
            return type(self._categories[module]) == 'table'
                and type(self._categories[module][category]) == 'table'
        end
        return type(self._categories[name]) == 'table'
    end
    function self:list()
        local names = {}
        for module, categories in pairs(self._categories) do
            names[#names + 1] = module
            for category in pairs(categories) do
                names[#names + 1] = module .. '.' .. category
            end
        end
        table.sort(names)
        return names
    end
    return self
end

return M
