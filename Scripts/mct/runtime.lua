-- Event-driven draft: no timers, no periodic scans, no native hook guesses.
local Selectors = require('mct.selectors')
local M = {}
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
-- Overlay complete setting values by key; nested values are copied, not merged.
local function overlay(base, overrides)
    local result = copy(base)
    for key, value in pairs(overrides) do result[key] = copy(value) end
    return result
end
local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end

function M.new(host, definitions, templates)
    for _, name in ipairs({'valid','identity','ready','matches','parent','find','subscribe','onError'}) do
        assert(type(host[name]) == 'function', 'host requires ' .. name)
    end
    assert(host.unwrap == nil or type(host.unwrap) == 'function', 'host.unwrap must be a function')
    local self = {epoch=1, phase='new', errors={}}
    local categories, byId, candidates, queue = {}, {}, {}, {}
    local busy, unsubscribe, suspended = false, nil, false
    for _, definition in ipairs(definitions) do
        assert(type(definition.name) == 'string' and not categories[definition.name], 'duplicate/invalid category')
        assert(definition.settings == nil or type(definition.settings) == 'table', 'category settings must be a table')
        categories[definition.name] = {settings=copy(definition.settings or {}), graph=Selectors.compile(definition.targets or {}),
            single=definition.single == true, templates={}, objects={}}
    end
    for _, template in ipairs(templates) do
        assert(type(template.id) == 'string' and template.id ~= '' and not byId[template.id], 'duplicate/invalid template id')
        assert(type(template.attach) == 'function' and type(template.update) == 'function'
            and type(template.detach) == 'function', 'template requires attach, update and detach')
        local category = assert(categories[template.category], 'unknown template category')
        assert(template.settings == nil or type(template.settings) == 'table', 'template settings must be a table')
        local record = {definition=template, enabled=false, defaults=copy(template.settings or {}),
            overrides={}, settings={}, revision=0, attached={}}
        byId[template.id], category.templates[template.id] = record, record
    end
    local function report(stage, id, message)
        local error = {stage=stage, template=id, message=tostring(message)}
        self.errors[#self.errors + 1] = error
        -- A diagnostic failure must not break another template's lifecycle.
        pcall(host.onError, error)
    end
    local function serialize(operation)
        queue[#queue + 1] = operation
        if busy then return end
        busy = true
        local index = 1
        while index <= #queue do
            local ok, why = pcall(queue[index])
            if not ok then report('runtime', nil, why) end
            index = index + 1
        end
        queue, busy = {}, false
    end
    local function refreshSettings(category, record)
        record.settings = overlay(category.settings, overlay(record.defaults, record.overrides))
        record.definition.settings = copy(record.settings)
        record.revision = record.revision + 1
    end
    local function invoke(record, operation, object, settings)
        settings = settings or record.settings
        -- Publish the same effective values for callbacks using template.settings.
        record.definition.settings = copy(settings)
        local ok, value, why = pcall(function()
            -- Reference hosts retain the native lifetime token; templates receive
            -- the underlying UObject only after a final validity check.
            if not host.valid(object) then return false, 'not_ready' end
            local target = object
            if host.unwrap then target = host.unwrap(object) end
            if target == nil then return false, 'not_ready' end
            return record.definition[operation](target, copy(settings))
        end)
        record.definition.settings = copy(record.settings)
        if ok and value ~= false then return true end
        if not (ok and why == 'not_ready') then
            report(operation, record.definition.id, ok and (why or 'callback returned false') or value)
        end
        return false
    end
    local function include(object)
        if not host.valid(object) then return end
        for _, category in pairs(categories) do
            for _, name in ipairs(category.graph.order) do
                if host.matches(object, category.graph.byName[name]) then
                    local id = host.identity(object)
                    assert(type(id) == 'string', 'host identity must be a generation-safe string')
                    candidates[id] = object
                    return
                end
            end
        end
    end
    local function discover()
        local seen = {}
        for _, name in ipairs(keys(categories)) do
            local graph = categories[name].graph
            for _, alias in ipairs(graph.order) do
                local selector = graph.byName[alias]
                local key = (selector.object and 'object:' or 'class:') .. (selector.object or selector.class)
                if not seen[key] then
                    seen[key] = true
                    -- Host enumeration returns live candidates, including those not yet ready.
                    for _, object in ipairs(host.find(selector)) do include(object) end
                end
            end
        end
    end
    local function reconcile()
        for id, object in pairs(candidates) do
            if not host.valid(object) then candidates[id] = nil end
        end
        for _, name in ipairs(keys(categories)) do
            local category = categories[name]
            local _, objects = Selectors.resolve(category.graph, candidates, host)
            category.objects = objects
            -- Detach all outgoing templates before any incoming template attaches.
            for _, id in ipairs(keys(category.templates)) do
                local record = category.templates[id]
                for _, token in ipairs(keys(record.attached)) do
                    local attached = record.attached[token]
                    if not host.valid(attached.object) then
                        record.attached[token] = nil
                    elseif not record.enabled or not objects[token] or not host.ready(attached.object) then
                        if invoke(record, 'detach', attached.object, attached.settings) then record.attached[token] = nil end
                    end
                end
            end
            for _, id in ipairs(keys(category.templates)) do
                local record = category.templates[id]
                if record.enabled and not suspended then
                    for _, token in ipairs(keys(objects)) do
                        local object, blocked = objects[token], false
                        -- A failed detach in a single category blocks the replacement.
                        if category.single then
                            for otherId, other in pairs(category.templates) do
                                if otherId ~= id and other.attached[token] then blocked = true end
                            end
                        end
                        local old = record.attached[token]
                        if not blocked and host.valid(object) and host.ready(object)
                            and (not old or old.revision ~= record.revision) then
                            local operation = old and 'update' or 'attach'
                            if invoke(record, operation, object) and host.valid(object) then
                                record.attached[token] = {object=object, revision=record.revision, settings=copy(record.settings)}
                            end
                        end
                    end
                end
            end
        end
    end
    function self:select(categoryName, selections)
        assert(self.phase == 'new' or self.phase == 'running', 'runtime is not accepting selections')
        local category = assert(categories[categoryName], 'unknown category')
        local desired, count = {}, 0
        for id, settings in pairs(selections) do
            assert(category.templates[id], 'template does not belong to category')
            assert(type(settings) == 'table', 'settings must be a table')
            desired[id], count = copy(settings), count + 1
        end
        assert(not category.single or count <= 1, 'single category accepts at most one template')
        serialize(function()
            for id, record in pairs(category.templates) do
                record.enabled = desired[id] ~= nil
                if record.enabled then
                    record.overrides = desired[id]
                    refreshSettings(category, record)
                end
            end
            if self.phase == 'running' and not suspended then reconcile() end
        end)
    end
    function self:setCategorySettings(categoryName, settings)
        assert(self.phase == 'new' or self.phase == 'running', 'runtime is not accepting settings')
        local category = assert(categories[categoryName], 'unknown category')
        assert(type(settings) == 'table', 'category settings must be a table')
        local committed = copy(settings)
        serialize(function()
            category.settings = committed
            for _, record in pairs(category.templates) do
                if record.enabled then refreshSettings(category, record) end
            end
            if self.phase == 'running' and not suspended then reconcile() end
        end)
    end
    -- Menu commits category values and template selections together, then reconciles once.
    function self:commit(changes)
        assert(self.phase == 'new' or self.phase == 'running', 'runtime is not accepting commits')
        local pending = {}
        for name, change in pairs(changes) do
            local category = assert(categories[name], 'unknown category')
            assert(type(change.settings) == 'table' and type(change.selections) == 'table', 'invalid category commit')
            local count = 0
            for id, settings in pairs(change.selections) do
                assert(category.templates[id] and type(settings) == 'table', 'invalid template selection')
                count = count + 1
            end
            assert(not category.single or count <= 1, 'single category accepts at most one template')
            pending[name] = copy(change)
        end
        serialize(function()
            for name, change in pairs(pending) do
                local category = categories[name]
                category.settings = change.settings
                for id, record in pairs(category.templates) do
                    record.enabled = change.selections[id] ~= nil
                    if record.enabled then
                        record.overrides = change.selections[id]
                        refreshSettings(category, record)
                    end
                end
            end
            if next(pending) and self.phase == 'running' and not suspended then reconcile() end
        end)
    end
    function self:event(event)
        assert(type(event) == 'table', 'lifecycle event required')
        local kind, object, epoch = event.kind, event.object, event.epoch
        assert(kind == 'changed' or kind == 'lost' or kind == 'world_invalidated' or kind == 'world_ready', 'unknown lifecycle event')
        assert(type(epoch) == 'number', 'event must carry the epoch captured before queuing')
        -- lost carries the identity captured while the object was valid.
        local id = event.id
        assert(kind ~= 'lost' or type(id) == 'string', 'lost event requires captured identity')
        serialize(function()
            if self.phase ~= 'running' or epoch ~= self.epoch then return end
            if kind == 'world_invalidated' then
                self.epoch, suspended, candidates = self.epoch + 1, true, {}
                for _, category in pairs(categories) do
                    category.objects = {}
                    for _, record in pairs(category.templates) do record.attached = {} end
                end
                return
            elseif kind == 'world_ready' then
                if not suspended then return end
                suspended = false
                discover()
            elseif suspended then return
            elseif kind == 'lost' then candidates[id] = nil
            else
                include(object)
            end
            reconcile()
        end)
    end
    function self:start()
        assert(self.phase == 'new', 'runtime already started')
        -- Subscription precedes the snapshot. Events during subscription are queued.
        serialize(function()
            self.phase = 'running'
            local ok, why = pcall(function()
                unsubscribe = host.subscribe(function(event) self:event(event) end,
                    function() return self.epoch end)
                assert(type(unsubscribe) == 'function', 'host.subscribe must return unsubscribe')
                discover()
                -- Drain notifications captured during subscription/snapshot before attaching.
                queue[#queue + 1] = function()
                    if self.phase == 'running' and not suspended then reconcile() end
                end
            end)
            if not ok then
                self.phase = 'failed'
                if type(unsubscribe) == 'function' then pcall(unsubscribe) end
                unsubscribe, candidates = nil, {}
                error(why)
            end
        end)
    end
    function self:stop()
        serialize(function()
            self.phase = 'stopped'
            if unsubscribe then
                local ok, why = pcall(unsubscribe)
                unsubscribe = nil
                if not ok then report('unsubscribe', nil, why) end
            end
            for _, record in pairs(byId) do record.enabled = false end
            reconcile()
            candidates = {}
        end)
    end
    function self:attachments(id)
        local result = {}
        for token, record in pairs(assert(byId[id], 'unknown template').attached) do result[token] = record.object end
        return result
    end
    return self
end

return M
