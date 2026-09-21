local U = require('te.util')
local V = require('te.validation')
local Provider = require('te.provider_settings')
local Events = require('te.event_contracts')
local M = {}

function M.new(registry, options)
    options = options or {}
    local self = {active = {}, pending = {}, multi = {}, revision = 0}
    local busy = false
    local function enabled(template) return template.settings.enabled == true end
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
    local function detach(category, context, reason, stateKey)
        local slot = stateKey or category
        self.pending[slot] = nil
        if reason == 'world_invalidated' then
            self.active[slot] = nil
            return true
        end
        local current = self.active[slot]
        if not current then return true end
        if current.inert or current.suppressed or not enabled(current.template) then
            self.active[slot]=nil;return true
        end
        local service = resolveService(category, context)
        local ok, result, err = pcall(current.template.detach, current.template, service, current.handle, reason)
        if not ok then return nil, tostring(result) end
        if result ~= true then return nil, err or 'detach must return true on success' end
        self.active[slot] = nil
        return true
    end
    function self:detach(category, context, reason)
        return guarded(function()
            local states = self.multi[category]
            if states then
                local keys = {}; for _, stateKey in pairs(states) do keys[#keys + 1] = stateKey end
                table.sort(keys)
                for _, stateKey in ipairs(keys) do
                    local ok, err = detach(category, context, reason or 'disable', stateKey)
                    if not ok then return nil, err end
                end
                self.multi[category] = nil
                return true
            end
            return detach(category, context, reason or 'disable')
        end)
    end
    local function apply(category, identity, configuration, context, suppliedTarget, stateKey)
            local slot = stateKey or category
            assert(registry.categories:contains(category), 'unregistered category: ' .. tostring(category))
            if identity == nil then return detach(category, context, 'none', stateKey) end
            local entry = assert(registry.byId[identity], 'unknown template identity')
            assert(entry.template.category == category, 'template category mismatch')
            V.template(entry.template, registry.categories, entry.location, enabled(entry.template))
            assert(type(configuration) == 'table', 'committed configuration must be a table')
            local spec = U.copy(configuration)
            Provider.validate(entry.template.settings, spec.settings)
            local previous = self.active[slot]
            if not enabled(entry.template) then
                if previous and previous.id ~= identity then
                    local ok, err = detach(category, context, 'switch', stateKey)
                    if not ok then return nil, err end
                end
                self.pending[slot]=nil
                self.active[slot]={id=identity,template=entry.template,configuration=spec,suppressed=true}
                return true, 'disabled'
            end
            if category=='menu.fixes' and entry.template.attach==nil
                and entry.template.detach==nil and entry.template.render==nil then
                self.pending[slot]=nil
                self.active[slot]={id=identity,template=entry.template,configuration=spec,inert=true}
                return true
            end
            -- Validate before releasing an old attachment, then resolve freshly for each call.
            local service = resolveService(category, context)
            local target = resolveTarget(category, context, suppliedTarget)
            if Events.requiresTarget(category) and not service:valid(target) then
                self.pending[slot] = {id=identity, template=entry.template, configuration=spec}
                return true, 'not_ready'
            end
            if previous and previous.suppressed then self.active[slot]=nil;previous=nil end
            if previous and previous.id ~= identity then
                local ok, err = detach(category, context, 'switch', stateKey)
                if not ok then return nil, err end
                previous = nil
            end
            local ok, handle, err = pcall(entry.template.attach, entry.template, service, target,
                U.copy(spec), previous and previous.handle or nil)
            if not ok then return nil, tostring(handle) end
            if (handle == nil or handle == false) and err == 'not_ready' then
                self.pending[slot] = {id=identity, template=entry.template, configuration=spec}
                return true, 'not_ready'
            end
            if handle == nil or handle == false then return nil, err or 'attach returned no handle' end
            self.pending[slot] = nil
            self.active[slot] = {id = identity, template = entry.template, handle = handle, configuration = spec}
            return true
    end
    function self:apply(category, identity, configuration, context)
        return guarded(function()
            return apply(category, identity, configuration, context)
        end)
    end
    function self:retry(category, context)
        return guarded(function()
            local states = self.multi[category]
            if states then
                for _, stateKey in pairs(states) do
                    local pending = self.pending[stateKey]
                    if pending then
                        local ok, why = apply(category, pending.id, pending.configuration, context, nil, stateKey)
                        if not ok or why == 'not_ready' then return ok, why end
                    end
                end
                return true
            end
            local pending = self.pending[category]
            if not pending then return true end
            return apply(category, pending.id, pending.configuration, context)
        end)
    end
    local function renderRecord(category, current, context, target, reason)
        if not current or current.inert or current.suppressed or not enabled(current.template) then return 'ignored' end
        local status, err = current.template:render(resolveService(category, context), current.handle, target, reason)
        assert(status == 'applied' or status == 'not_ready' or status == 'ignored',
            'invalid render status: ' .. tostring(status))
        return status, err
    end
    function self:render(category, context, target, reason)
        return guarded(function()
            local states = self.multi[category]
            if states then
                local overall, detail = 'ignored', nil
                for _, stateKey in pairs(states) do
                    local status, err = renderRecord(category, self.active[stateKey], context, target, reason)
                    if status == 'applied' then overall = 'applied'
                    elseif status == 'not_ready' and overall ~= 'applied' then overall = 'not_ready' end
                    detail = detail or err
                end
                return overall, detail
            end
            local current = self.active[category]
            return renderRecord(category, current, context, target, reason)
        end)
    end
    local function dispatchRecord(category, event, context, payload, stateKey)
        local desired = self.pending[stateKey] or self.active[stateKey]
        if not desired or not Events.interested(desired.template, event) then return 'ignored' end
        if desired.suppressed or not enabled(desired.template) then return 'ignored' end
        if self.pending[stateKey] then
            local attached, why = apply(category, desired.id, desired.configuration, context, nil, stateKey)
            if not attached then return nil, why end
            if why == 'not_ready' then return 'not_ready' end
        end
        local current = self.active[stateKey]
        if not current or current.inert then return 'ignored' end
        return renderRecord(category, current, context, payload, event)
    end
    function self:dispatch(category, event, context, payload)
        return guarded(function()
            assert(Events.supports(category, event), 'unsupported ' .. tostring(category) .. ' event ' .. tostring(event))
            local states = self.multi[category]
            if states then
                local overall, detail = 'ignored', nil
                for _, stateKey in pairs(states) do
                    local status, err = dispatchRecord(category, event, context, payload, stateKey)
                    if status == nil then return nil, err end
                    if status == 'applied' then overall = 'applied'
                    elseif status == 'not_ready' and overall ~= 'applied' then overall = 'not_ready' end
                    detail = detail or err
                end
                return overall, detail
            end
            local desired = self.pending[category] or self.active[category]
            if not desired or not Events.interested(desired.template, event) then return 'ignored' end
            if desired.suppressed or not enabled(desired.template) then return 'ignored' end
            if self.pending[category] then
                local attached, why = apply(category, desired.id, desired.configuration, context)
                if not attached then return nil, why end
                if why == 'not_ready' then return 'not_ready' end
            end
            local current = self.active[category]
            if not current then return 'ignored' end
            if current.inert then return 'ignored' end
            local status, err = current.template:render(resolveService(category, context), current.handle, payload, event)
            assert(status == 'applied' or status == 'not_ready' or status == 'ignored',
                'invalid render status: ' .. tostring(status))
            return status, err
        end)
    end
    function self:selection(category)
        local states = self.multi[category]
        if states then
            local selections = {}
            for identity, stateKey in pairs(states) do
                local current = self.pending[stateKey] or self.active[stateKey]
                if current then selections[#selections + 1] = {id=identity, configuration=U.copy(current.configuration)} end
            end
            table.sort(selections, function(a, b) return a.id < b.id end)
            return selections
        end
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
            if selection.id ~= nil or selection.configuration ~= nil then
                local ok, err = self:apply(category, selection.id, selection.configuration or {}, context)
                if not ok then errors[category] = err end
            else
                U.array(selection, category .. ' multi-template selections')
                local desired, states = {}, self.multi[category] or {}
                self.multi[category] = states
                for _, item in ipairs(selection) do
                    assert(type(item)=='table' and type(item.id)=='string', 'invalid multi-template selection')
                    assert(not desired[item.id], 'duplicate multi-template selection')
                    desired[item.id] = item
                end
                for identity, stateKey in pairs(states) do
                    if not desired[identity] then
                        local ok, err = guarded(function() return detach(category, context, 'none', stateKey) end)
                        if not ok then errors[category .. ':' .. identity] = err else states[identity] = nil end
                    end
                end
                for identity, item in pairs(desired) do
                    if not errors[category .. ':' .. identity] then
                        local stateKey = states[identity] or (category .. '\0' .. identity)
                        local ok, err = guarded(function()
                            return apply(category, identity, item.configuration or {}, context, nil, stateKey)
                        end)
                        if not ok then errors[category .. ':' .. identity] = err else states[identity] = stateKey end
                    end
                end
                if next(states) == nil then self.multi[category] = nil end
            end
        end
        if next(errors) then return nil, errors end
        self.revision = event.revision
        return true, errors
    end
    return self
end

return M
