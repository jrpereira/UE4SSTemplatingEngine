local U = require('te.util')
local V = require('te.validation')
local M = {}

function M.new(registry, options)
    options = options or {}
    local self = {active = {}, revision = 0}
    local busy = false
    local function resolveService(category, context)
        local service
        if options.resolveService then service = options.resolveService(category, context)
        elseif category == 'player.quickslots' then
            service = type(context) == 'table' and context.playerActions or nil
        else error('no service resolver for category: ' .. category) end
        assert(type(service) == 'table', category .. ': category service must be a table')
        if category == 'player.quickslots' then
            for _, method in ipairs({'valid', 'same', 'identity', 'parent'}) do
                assert(type(service[method]) == 'function', 'quickslots service requires ' .. method)
            end
        end
        return service
    end
    local function guarded(operation)
        if busy then return nil, 'reentrant lifecycle operation' end
        busy = true
        local ok, result, err = pcall(operation)
        busy = false
        if not ok then return nil, tostring(result) end
        return result, err
    end
    local function detach(category, context, reason)
        if reason == 'world_invalidated' then
            self.active[category] = nil
            return true
        end
        local current = self.active[category]
        if not current then return true end
        local service = resolveService(category, context)
        local ok, result, err = pcall(current.template.detach, current.template, service, current.handle, reason)
        if not ok then return nil, tostring(result) end
        if result ~= true then return nil, err or 'detach must return true on success' end
        self.active[category] = nil
        return true
    end
    function self:detach(category, context, reason)
        return guarded(function() return detach(category, context, reason or 'disable') end)
    end
    function self:apply(category, identity, configuration, context)
        return guarded(function()
            assert(registry.categories:contains(category), 'unregistered category: ' .. tostring(category))
            if identity == nil then return detach(category, context, 'none') end
            local entry = assert(registry.byId[identity], 'unknown template identity')
            assert(entry.template.category == category, 'template category mismatch')
            V.template(entry.template, registry.categories, entry.location, true)
            assert(type(configuration) == 'table', 'committed configuration must be a table')
            local spec = U.copy(configuration)
            -- Validate before releasing an old attachment, then resolve freshly for each call.
            resolveService(category, context)
            local previous = self.active[category]
            if previous and previous.id ~= identity then
                local ok, err = detach(category, context, 'switch')
                if not ok then return nil, err end
                previous = nil
            end
            local ok, handle, err = pcall(entry.template.attach, entry.template, resolveService(category, context),
                U.copy(spec), previous and previous.handle or nil)
            if not ok then return nil, tostring(handle) end
            if handle == nil or handle == false then return nil, err or 'attach returned no handle' end
            self.active[category] = {id = identity, template = entry.template, handle = handle, configuration = spec}
            return true
        end)
    end
    function self:render(category, context, target, reason)
        return guarded(function()
            local current = self.active[category]
            if not current then return 'ignored' end
            local status, err = current.template:render(resolveService(category, context), current.handle, target, reason)
            assert(status == 'applied' or status == 'not_ready' or status == 'ignored',
                'invalid render status: ' .. tostring(status))
            return status, err
        end)
    end
    function self:selection(category)
        local current = self.active[category]
        if not current then return nil end
        return current.id, U.copy(current.configuration)
    end
    -- Use this only for an already durable Apply event, never staged picker changes.
    -- A batch can partially succeed across categories: expose every failure for retry.
    function self:commit(event, decode, context)
        if busy then return nil, 'reentrant lifecycle operation' end
        assert(type(event) == 'table' and type(event.revision) == 'number'
            and event.revision >= 1 and event.revision % 1 == 0 and event.revision < math.huge,
            'invalid Apply revision')
        if event.revision <= self.revision then return true, {} end
        local selections = decode(U.copy(event.values))
        assert(type(selections) == 'table', 'decoder must return category selections')
        local names = {}
        for category, selection in pairs(selections) do
            assert(registry.categories:contains(category), 'unregistered decoded category')
            assert(type(selection) == 'table', 'invalid decoded selection')
            names[#names + 1] = category
        end
        table.sort(names)
        local errors = {}
        for _, category in ipairs(names) do
            local selection = selections[category]
            local ok, err = self:apply(category, selection.id, selection.configuration or {}, context)
            if not ok then errors[category] = err end
        end
        if next(errors) then return nil, errors end
        self.revision = event.revision
        return true, errors
    end
    return self
end

return M
