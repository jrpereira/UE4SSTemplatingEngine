local M = {}

function M.deliver(template, state, definition, phase, service)
    if definition.shared then
        if phase ~= 'Triggered' then return true end
        local group = state.selectedGroup or state.defaultGroup or 1
        local kind = state.groupTypes and state.groupTypes[group]
        return kind and service:activateQuickslot(kind, definition.slot)
    end
    if definition.slot then
        if phase ~= 'Triggered' then return true end
        return service:activateQuickslot(definition.type, definition.slot)
    end
    if definition.binding.mode == 2 and (phase == 'Completed' or phase == 'Canceled') then
        state.selectedGroup = state.defaultGroup
    elseif phase == 'Triggered' or phase == 'Started' then
        if phase == 'Triggered' and definition.binding.mode == 0 and state.defaultUnbound
            and state.selectedGroup == definition.groupIndex then
            state.selectedGroup = state.defaultGroup
        else
            state.selectedGroup = definition.groupIndex
        end
    else
        return true
    end
    -- A detached wheel is no longer a child of the native switcher. The
    -- selection still updates TE state, but cannot change its active index.
    if template.detachSecondaryWheel == true then return true end
    return service:selectQuickslotGroup(state.selectedGroup)
end

return M
