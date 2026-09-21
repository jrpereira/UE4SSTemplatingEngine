local U = require('te.util')
local V = require('te.validation')
local Provider = require('te.provider_settings')
local Events = require('te.event_contracts')
local M = {}

function M.new(registry, options)
    options = options or {}
    local self = {active = {}, pending = {}, revision = 0}
    local busy = false
    local function resolveService(category, context)
        local service
        if options.resolveService then service = options.resolveService(category, context)
        elseif category == 'player.quickslots' then
            service = type(context) == 'table' and context.playerActions or nil
        elseif type(context) == 'table' and type(context.services) == 'table' then
            service = context.services[category]
        else error('no service resolver for category: ' .. category) end
        assert(type(service) == 'table', category .. ': category service must be a table')
        if category == 'player.quickslots' then
            for _, method in ipairs({'valid', 'same', 'identity', 'parent'}) do
                assert(type(service[method]) == 'function', 'quickslots service requires ' .. method)
            end
        elseif category == 'npc.attacks' then
            for _,method in ipairs({'valid','visible','transition','cancelTransitions','isA','createWidget',
                'viewportSize','viewportScale','nativeBrush','destroyWidget'}) do
                assert(type(service[method])=='function','attacks service requires '..method)
            end
        end
        return service
    end
    local function resolveTarget(category, context, supplied)
        local target = supplied
        if target == nil and options.resolveTarget then target = options.resolveTarget(category, context) end
        if target == nil and type(context) == 'table' and type(context.targets) == 'table' then
            target = context.targets[category]
        end
        return target
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
        self.pending[category] = nil
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
    local function apply(category, identity, configuration, context, suppliedTarget)
            assert(registry.categories:contains(category), 'unregistered category: ' .. tostring(category))
            if identity == nil then return detach(category, context, 'none') end
            local entry = assert(registry.byId[identity], 'unknown template identity')
            assert(entry.template.category == category, 'template category mismatch')
            V.template(entry.template, registry.categories, entry.location, true)
            assert(type(configuration) == 'table', 'committed configuration must be a table')
            local spec = U.copy(configuration)
            Provider.validate(entry.template.settings, spec.settings)
            -- Validate before releasing an old attachment, then resolve freshly for each call.
            local service = resolveService(category, context)
            local target = resolveTarget(category, context, suppliedTarget)
            if Events.requiresTarget(category) and not service:valid(target) then
                self.pending[category] = {id=identity, template=entry.template, configuration=spec}
                return true, 'not_ready'
            end
            local previous = self.active[category]
            if previous and previous.id ~= identity then
                local ok, err = detach(category, context, 'switch')
                if not ok then return nil, err end
                previous = nil
            end
            local ok, handle, err = pcall(entry.template.attach, entry.template, service, target,
                U.copy(spec), previous and previous.handle or nil)
            if not ok then return nil, tostring(handle) end
            if (handle == nil or handle == false) and err == 'not_ready' then
                self.pending[category] = {id=identity, template=entry.template, configuration=spec}
                return true, 'not_ready'
            end
            if handle == nil or handle == false then return nil, err or 'attach returned no handle' end
            self.pending[category] = nil
            self.active[category] = {id = identity, template = entry.template, handle = handle, configuration = spec}
            return true
    end
    function self:apply(category, identity, configuration, context)
        return guarded(function()
            return apply(category, identity, configuration, context)
        end)
    end
    function self:retry(category, context)
        return guarded(function()
            local pending = self.pending[category]
            if not pending then return true end
            return apply(category, pending.id, pending.configuration, context)
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
    function self:dispatch(category, event, context, payload)
        return guarded(function()
            assert(Events.supports(category, event), 'unsupported ' .. tostring(category) .. ' event ' .. tostring(event))
            local desired = self.pending[category] or self.active[category]
            if not desired or not Events.interested(desired.template, event) then return 'ignored' end
            if self.pending[category] then
                local attached, why = apply(category, desired.id, desired.configuration, context)
                if not attached then return nil, why end
                if why == 'not_ready' then return 'not_ready' end
            end
            local current = self.active[category]
            if not current then return 'ignored' end
            local status, err = current.template:render(resolveService(category, context), current.handle, payload, event)
            assert(status == 'applied' or status == 'not_ready' or status == 'ignored',
                'invalid render status: ' .. tostring(status))
            return status, err
        end)
    end
    function self:selection(category)
        local current = self.pending[category] or self.active[category]
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
