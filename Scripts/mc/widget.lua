local Objects = require('mc.objects')
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
    -- UE4SS struct fields are views into their parent struct. Keep that
    -- parent wrapper alive while reading the nested vector components.
    local transform = M.property(widget, 'RenderTransform')
    local value = M.property(transform, member)
    local x, y = M.number(value, 'X'), M.number(value, 'Y')
    assert(transform ~= nil, 'render transform unavailable')
    return {X=x, Y=y}
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

function M.appearance(widget, settings, prefix, position)
    M.setTranslation(widget, position.X + settings[prefix .. 'X'],
        position.Y + settings[prefix .. 'Y'])
    M.setScale(widget, settings[prefix .. 'Size'] / 100)
    M.setOpacity(widget, settings[prefix .. 'Opacity'] / 100)
end

function M.reparent(widget, parent)
    local previous = assert(Objects.parent(widget), 'widget parent unavailable')
    assert(previous:RemoveChild(widget) ~= false, 'could not remove widget from parent')
    local slot = assert(parent:AddChild(widget), 'could not reparent widget')
    assert(Objects.valid(slot), 'widget slot unavailable after reparenting')
    slot:SetPadding({Left=0, Top=0, Right=0, Bottom=0})
    slot:SetHorizontalAlignment(1)
    slot:SetVerticalAlignment(1)
    return slot
end

function M.measure(widget)
    widget:ForceLayoutPrepass()
    local size = widget:GetDesiredSize()
    local width, height = M.number(size, 'X'), M.number(size, 'Y')
    assert(width > 0 and height > 0, 'widget layout size is not ready')
    local pivot = assert(M.property(widget, 'RenderTransformPivot'), 'widget pivot unavailable')
    return {width=width, height=height, pivotX=M.number(pivot, 'X'), pivotY=M.number(pivot, 'Y')}
end

-- Place the rendered bounds at x/y, including negative scale and pivot.
function M.position(widget, box, x, y, scale)
    M.setScale(widget, scale)
    M.setTranslation(widget,
        x - box.pivotX * box.width * (1 - scale) - math.min(0, scale * box.width),
        y - box.pivotY * box.height * (1 - scale) - math.min(0, scale * box.height))
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
