local M = {}

function M.unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end

function M.property(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and M.unwrap(value) or nil
end

function M.number(object, name)
    local value = tonumber(M.property(object, name))
    assert(value and value == value and math.abs(value) < math.huge,
        'unavailable visual property ' .. tostring(name))
    return value
end

local function vector(widget, member)
    local value = M.property(M.property(widget, 'RenderTransform'), member)
    return {X=M.number(value, 'X'), Y=M.number(value, 'Y')}
end

function M.translation(widget) return vector(widget, 'Translation') end
function M.scale(widget) return vector(widget, 'Scale') end

function M.opacity(widget)
    local value = tonumber(widget:GetRenderOpacity())
    assert(value and value == value and math.abs(value) < math.huge, 'unavailable render opacity')
    return value
end

function M.setTranslation(widget, x, y)
    local current = M.translation(widget)
    if current.X ~= x or current.Y ~= y then widget:SetRenderTranslation({X=x, Y=y}) end
end

function M.setScale(widget, x, y)
    y = y or x
    local current = M.scale(widget)
    if current.X ~= x or current.Y ~= y then widget:SetRenderScale({X=x, Y=y}) end
end

function M.setOpacity(widget, value)
    if M.opacity(widget) ~= value then widget:SetRenderOpacity(value) end
end

function M.snapshotSlot(widget)
    local slot = assert(M.property(widget, 'Slot'), 'widget slot unavailable')
    local padding = assert(M.property(slot, 'Padding'), 'widget slot padding unavailable')
    return {
        padding = {
            Left=M.number(padding, 'Left'), Top=M.number(padding, 'Top'),
            Right=M.number(padding, 'Right'), Bottom=M.number(padding, 'Bottom'),
        },
        horizontal=M.number(slot, 'HorizontalAlignment'),
        vertical=M.number(slot, 'VerticalAlignment'),
    }
end

function M.restoreSlot(widget, state)
    assert(type(state) == 'table' and type(state.padding) == 'table', 'invalid slot snapshot')
    local slot = assert(M.property(widget, 'Slot'), 'widget slot unavailable')
    slot:SetPadding(state.padding)
    slot:SetHorizontalAlignment(state.horizontal)
    slot:SetVerticalAlignment(state.vertical)
end

return M
