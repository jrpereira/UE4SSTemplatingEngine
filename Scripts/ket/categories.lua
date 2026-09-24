local U = require('ket.util')
local M = {}

function M.new()
    local self = {_categories = {}, _registered = {}}
    function self:addCategory(definition)
        assert(type(definition) == 'table', 'category object must be a table')
        local name = U.text(definition.name, 'category name')
        local module, category = name:match('^([%a_][%w_]*)%.([%a_][%w_]*)$')
        assert(module and category, name .. ': invalid category name')
        assert(not self._registered[name], 'duplicate category: ' .. name)
        self._categories[module] = self._categories[module] or {}
        local state = {visible = 0, count = 0, templates = {}}
        for key, value in pairs(definition) do
            U.text(key, name .. ' property')
            state[key] = value
        end
        self._categories[module][category] = state
        self._registered[name] = true
        return state
    end
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
            registered[category] = {visible = 0, count = 0, templates = {}}
        end
        self._categories[module] = registered
        for category in pairs(registered) do
            self._registered[module .. '.' .. category] = true
        end
    end
    function self:contains(name)
        return self._registered[name] == true
    end
    function self:getCategory(name)
        U.text(name, 'category')
        assert(self:contains(name), 'unregistered category: ' .. name)
        local module, category = name:match('^([^.]+)%.([^.]+)$')
        return self._categories[module][category]
    end
    function self:setCategory(name, values)
        assert(type(values) == 'table', name .. ': category values must be a table')
        local target = self:getCategory(name)
        local pending = {}
        for key, value in pairs(values) do
            U.text(key, name .. ' property')
            pending[key] = value
        end
        for key, value in pairs(pending) do target[key] = value end
        return target
    end
    function self:list()
        local names = {}
        for name in pairs(self._registered) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
    return self
end

return M
