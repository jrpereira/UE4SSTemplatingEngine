-- Binds generated actions through KEngineBridge after their IMC mappings exist. The
-- binding owner is deliberately separate from InputContext so travel/reload
-- cleanup never leaves native subscriptions behind.
return function(e)
    local active = nil
    local api = {}
    local function path(object)
        local full = assert(e.fullName(object), 'generated action has no name')
        return assert(full:match('^%S+%s+(.+)$'), 'unexpected generated action name: ' .. full)
    end
    function api:close()
        if active then
            local ok, why = e.bridge.CloseInputComponent(active.target)
            if not ok then return false, why end
        end
        active = nil
        return true
    end
    function api:bind(component, actions, plan, callback)
        assert(type(callback) == 'function', 'generated-action callback required')
        local closed, why = self:close()
        if not closed then return false, why end
        local target, openWhy = e.bridge.OpenInputComponent(e.componentPath(component))
        if not target then return false, openWhy end
        active = {target=target}
        for _, definition in ipairs(plan.actions) do
            if definition.binding.key ~= 0 and definition.binding.mode ~= -1 then
                local action = assert(actions[definition.id], 'missing generated action: ' .. definition.id)
                local phases = definition.binding.mode == 2 and {'Started','Completed','Canceled'} or {'Triggered'}
                for _, phase in ipairs(phases) do
                    local handle, bindWhy = e.bridge.BindAction(target, path(action), phase, function(event)
                        callback(definition, phase, event)
                    end)
                    if not handle then self:close(); return false, bindWhy end
                end
            end
        end
        return true
    end
    return api
end
