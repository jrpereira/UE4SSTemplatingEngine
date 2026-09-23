local U = require('te.util')
local V = require('te.validation')
local Provider = require('te.provider_settings')
local Events = require('te.event_contracts')
local M = {}

function M.new(registry, options)
    options = options or {}
    local self = {active = {}, pending = {}, multi = {}, categoryHandles = {}, revision = 0}
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
    local function resolveTarget(category, context, supplied, service)
        local target = supplied
        if target == nil and type(context) == 'table' and type(context.targets) == 'table' then
            target = context.targets[category]
        end
        local definition = registry.categories:getCategory(category)
        if target == nil and definition.resolveTarget then
            target = definition:resolveTarget(service, context)
        end
        if target == nil and options.resolveTarget then
            target = options.resolveTarget(category, context, definition)
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
    local function categoryInUse(category)
        for _, current in pairs(self.active) do
            if current.template.category == category and not current.inert and not current.suppressed then
                return true
            end
        end
        return false
    end
    local function detachCategory(category, context, reason)
        local record = self.categoryHandles[category]
        if not record then return true end
        if reason == 'world_invalidated' then self.categoryHandles[category] = nil; return true end
        local definition = registry.categories:getCategory(category)
        local ok, result, err = pcall(definition.detach, definition,
            resolveService(category, context), record.handle, reason)
        if not ok then return nil, tostring(result) end
        if result ~= true then return nil, err or 'category detach must return true on success' end
        self.categoryHandles[category] = nil
        return true
    end
    local function clearUnusedCategory(category, context, reason)
        if categoryInUse(category) then return true end
        return detachCategory(category, context, reason)
    end
    local function detach(category, context, reason, stateKey, preserveCategory)
        local slot = stateKey or category
        self.pending[slot] = nil
        if reason == 'world_invalidated' then
            self.active[slot] = nil
            if not categoryInUse(category) then return clearUnusedCategory(category, context, reason) end
            return true
        end
        local current = self.active[slot]
        if not current then
            if not preserveCategory then
                return clearUnusedCategory(category, context, reason)
            end
            return true
        end
        if current.inert or current.suppressed or not enabled(current.template) then
            self.active[slot]=nil
            if not preserveCategory then
                return clearUnusedCategory(category, context, reason)
            end
            return true
        end
        local service = resolveService(category, context)
        local shared = self.categoryHandles[category]
        local ok, result, err = pcall(current.template.detach, current.template, service, current.handle,
            reason, shared and shared.handle or nil)
        if not ok then return nil, tostring(result) end
        if result ~= true then return nil, err or 'detach must return true on success' end
        self.active[slot] = nil
        if not preserveCategory then
            return clearUnusedCategory(category, context, reason)
        end
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
    local function apply(category, identity, settings, context, suppliedTarget, stateKey)
            local slot = stateKey or category
            assert(registry.categories:contains(category), 'unregistered category: ' .. tostring(category))
            if identity == nil then return detach(category, context, 'none', stateKey) end
            local entry = assert(registry.byId[identity], 'unknown template identity')
            assert(entry.template.category == category, 'template category mismatch')
            V.template(entry.template, registry.categories, entry.location, enabled(entry.template))
            assert(type(settings) == 'table', 'committed settings must be a table')
            local spec = U.copy(settings)
            local declared, own = {}, {}
            for _, group in ipairs(Provider.normalize(entry.template.settings)) do
                for _, field in ipairs(group.fields) do
                    declared[field.id] = true
                    own[field.id] = spec[field.id]
                end
            end
            Provider.validate(entry.template.settings, next(declared) and own or nil)
            local categoryDeclaration = registry.categories:getCategory(category).settings
            local categoryGroups, static = Provider.normalizeCategory(categoryDeclaration)
            local categoryValues, categoryFields = {}, {}
            for _, group in ipairs(categoryGroups) do
                for _, field in ipairs(group.fields) do
                    categoryFields[field.id] = true
                    categoryValues[field.id] = declared[field.id] and field.default or spec[field.id]
                end
            end
            for field, default in pairs(static) do
                categoryFields[field] = true
                categoryValues[field] = declared[field] and default or spec[field]
            end
            Provider.validateCategory(categoryDeclaration,
                next(categoryFields) and categoryValues or nil)
            if next(declared) then
                local generated = category == 'player.quickslots' and
                    {access=true,firstGroupDefault=true,direct=true,groups=true,shared=true,advanced=true} or {}
                for name in pairs(spec) do
                    assert(declared[name] or categoryFields[name] or generated[name],
                        'unknown provider setting ' .. tostring(name))
                end
            end
            local previous = self.active[slot]
            if not enabled(entry.template) then
                if previous and previous.id ~= identity then
                    local ok, err = detach(category, context, 'switch', stateKey)
                    if not ok then return nil, err end
                end
                self.pending[slot]=nil
                self.active[slot]={id=identity,template=entry.template,settings=spec,suppressed=true}
                return true, 'disabled'
            end
            if category=='menu.fixes' and entry.template.attach==nil
                and entry.template.detach==nil and entry.template.render==nil then
                self.pending[slot]=nil
                self.active[slot]={id=identity,template=entry.template,settings=spec,inert=true}
                return true
            end
            -- Validate before releasing an old attachment, then resolve freshly for each call.
            local service = resolveService(category, context)
            local target = resolveTarget(category, context, suppliedTarget, service)
            if Events.requiresTarget(category) and not service:valid(target) then
                self.pending[slot] = {id=identity, template=entry.template, settings=spec}
                return true, 'not_ready'
            end
            if previous and previous.suppressed then self.active[slot]=nil;previous=nil end
            if previous and previous.id ~= identity then
                local ok, err = detach(category, context, 'switch', stateKey, true)
                if not ok then return nil, err end
                previous = nil
            end
            local definition = registry.categories:getCategory(category)
            local function recover(failure)
                if previous and previous.id == identity and self.active[slot] == previous then
                    local shared = self.categoryHandles[category]
                    if definition.attach then
                        local ok, restored, why = pcall(definition.attach, definition, service, target,
                            U.copy(previous.settings), shared and shared.handle or nil, previous.template)
                        if not ok or restored == nil or restored == false then
                            return nil, tostring(failure) .. '; category restoration failed: '
                                .. tostring(ok and why or restored)
                        end
                        self.categoryHandles[category] = {handle=restored}
                        shared = self.categoryHandles[category]
                    end
                    local ok, restored, why = pcall(previous.template.attach, previous.template,
                        service, target, U.copy(previous.settings), previous.handle,
                        shared and shared.handle or nil)
                    if not ok or restored == nil or restored == false then
                        return nil, tostring(failure) .. '; template restoration failed: '
                            .. tostring(ok and why or restored)
                    end
                    previous.handle = restored
                    return nil, failure
                end
                local cleaned, why = clearUnusedCategory(category, context, 'attach_failed')
                if not cleaned then return nil, tostring(failure) .. '; category cleanup: ' .. tostring(why) end
                return nil, failure
            end
            if definition.attach then
                local prior = self.categoryHandles[category]
                local ok, handle, err = pcall(definition.attach, definition, service, target,
                    U.copy(spec), prior and prior.handle or nil, entry.template)
                if not ok then
                    return recover(tostring(handle))
                end
                if (handle == nil or handle == false) and err == 'not_ready' then
                    local _, why = recover('not_ready')
                    if why ~= 'not_ready' then return nil, why end
                    self.pending[slot] = {id=identity, template=entry.template, settings=spec}
                    return true, 'not_ready'
                end
                if handle == nil or handle == false then
                    return recover(err or 'category attach returned no handle')
                end
                self.categoryHandles[category] = {handle=handle}
            end
            local ok, handle, err = pcall(entry.template.attach, entry.template, service, target,
                U.copy(spec), previous and previous.handle or nil,
                self.categoryHandles[category] and self.categoryHandles[category].handle or nil)
            if not ok then
                return recover(tostring(handle))
            end
            if (handle == nil or handle == false) and err == 'not_ready' then
                local _, why = recover('not_ready')
                if why ~= 'not_ready' then return nil, why end
                self.pending[slot] = {id=identity, template=entry.template, settings=spec}
                return true, 'not_ready'
            end
            if handle == nil or handle == false then
                return recover(err or 'attach returned no handle')
            end
            self.pending[slot] = nil
            self.active[slot] = {id = identity, template = entry.template, handle = handle, settings = spec}
            return true
    end
    function self:apply(category, identity, settings, context)
        return guarded(function()
            return apply(category, identity, settings, context)
        end)
    end
    function self:retry(category, context)
        return guarded(function()
            local states = self.multi[category]
            if states then
                for _, stateKey in pairs(states) do
                    local pending = self.pending[stateKey]
                    if pending then
                        local ok, why = apply(category, pending.id, pending.settings, context, nil, stateKey)
                        if not ok or why == 'not_ready' then return ok, why end
                    end
                end
                return true
            end
            local pending = self.pending[category]
            if not pending then return true end
            return apply(category, pending.id, pending.settings, context)
        end)
    end
    local function renderRecord(category, current, context, target, reason)
        if not current or current.inert or current.suppressed or not enabled(current.template) then return 'ignored' end
        local shared = self.categoryHandles[category]
        local status, err = current.template:render(resolveService(category, context), current.handle,
            target, reason, shared and shared.handle or nil)
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
        if not desired or not Events.interested(desired.template, event,
            registry.categories:getCategory(category).events) then return 'ignored' end
        if desired.suppressed or not enabled(desired.template) then return 'ignored' end
        if self.pending[stateKey] then
            local attached, why = apply(category, desired.id, desired.settings, context, nil, stateKey)
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
            if not desired or not Events.interested(desired.template, event,
                registry.categories:getCategory(category).events) then return 'ignored' end
            if desired.suppressed or not enabled(desired.template) then return 'ignored' end
            if self.pending[category] then
                local attached, why = apply(category, desired.id, desired.settings, context)
                if not attached then return nil, why end
                if why == 'not_ready' then return 'not_ready' end
            end
            local current = self.active[category]
            if not current then return 'ignored' end
            if current.inert then return 'ignored' end
            local shared = self.categoryHandles[category]
            local status, err = current.template:render(resolveService(category, context), current.handle,
                payload, event, shared and shared.handle or nil)
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
                if current then selections[#selections + 1] = {id=identity, settings=U.copy(current.settings)} end
            end
            table.sort(selections, function(a, b) return a.id < b.id end)
            return selections
        end
        local current = self.pending[category] or self.active[category]
        if not current then return nil end
        return current.id, U.copy(current.settings)
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
            if selection.id ~= nil or selection.settings ~= nil then
                local ok, err = self:apply(category, selection.id, selection.settings or {}, context)
                if not ok then errors[category] = err end
            else
                local partial, known = selection._partial == true, selection._known
                if partial then assert(type(known) == 'table', 'partial multi-template selection requires known identities') end
                local count = 0
                for key in pairs(selection) do
                    if type(key) == 'number' then
                        assert(key >= 1 and key % 1 == 0, 'invalid multi-template selection index')
                        count = count + 1
                    else
                        assert(key == '_partial' or key == '_known', 'invalid multi-template selection metadata')
                    end
                end
                for index = 1, count do assert(rawget(selection,index) ~= nil, 'sparse multi-template selections') end
                local desired, states = {}, self.multi[category] or {}
                self.multi[category] = states
                for _, item in ipairs(selection) do
                    assert(type(item)=='table' and type(item.id)=='string', 'invalid multi-template selection')
                    assert(not desired[item.id], 'duplicate multi-template selection')
                    desired[item.id] = item
                end
                for identity, stateKey in pairs(states) do
                    if (not partial or known[identity]) and not desired[identity] then
                        local ok, err = guarded(function() return detach(category, context, 'none', stateKey) end)
                        if not ok then errors[category .. ':' .. identity] = err else states[identity] = nil end
                    end
                end
                for identity, item in pairs(desired) do
                    if not errors[category .. ':' .. identity] then
                        local stateKey = states[identity] or (category .. '\0' .. identity)
                        local ok, err = guarded(function()
                            return apply(category, identity, item.settings or {}, context, nil, stateKey)
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
