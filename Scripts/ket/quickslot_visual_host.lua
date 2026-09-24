local M = {}

function M.new(runtime, service)
    assert(type(runtime) == 'table' and type(service) == 'table',
        'quickslot visual host requires runtime and service')
    local category = 'player.quickslots'
    local self = {desired = nil}
    local function context() return {playerActions = service} end

    function self:select(selection)
        self.desired = selection and selection.id and
            {id = selection.id, settings = selection.settings or {}} or nil
        if not self.desired then return runtime:apply(category, nil, {}, context()) end
        return runtime:apply(category, self.desired.id, self.desired.settings, context())
    end

    -- Apply events already commit the visual runtime; only remember the choice.
    function self:adopt(identity, settings)
        self.desired = identity and {id = identity, settings = settings or {}} or nil
    end

    function self:wake()
        if not self.desired then return true end
        if runtime.pending[category] then return runtime:retry(category, context()) end
        local active = runtime.active[category]
        if active and active.id == self.desired.id then return true end
        return runtime:apply(category, self.desired.id, self.desired.settings, context())
    end

    function self:worldInvalidated()
        local detached, why = runtime:detach(category, context(), 'world_invalidated')
        if not detached then return nil, why end
        return self:wake()
    end

    return self
end

return M
