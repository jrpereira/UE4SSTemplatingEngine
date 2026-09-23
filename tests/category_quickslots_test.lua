package.path = 'Scripts/?.lua;' .. package.path
local category = dofile('Scripts/categories/player_quickslots.lua')
local function node(name) return {name=name} end
local owner, switcher = node('owner'), node('switcher')
owner.children, switcher.children = {switcher}, {}
switcher.parent = owner
local function panelMethods(panel)
    function panel:AddChild(child)
        self.children[#self.children + 1] = child
        child.parent = self
        return child.slot
    end
    function panel:RemoveChild(child)
        for i, current in ipairs(self.children) do
            if current == child then table.remove(self.children, i); child.parent=nil; return true end
        end
        return false
    end
    function panel:GetChildrenCount() return #self.children end
    function panel:GetChildAt(index) return self.children[index + 1] end
end
panelMethods(owner); panelMethods(switcher)
local first, second = node('WBP_AA_Quickslots_C Ability'), node('WBP_HUD_Quickslots_C Consumable')
local function slot()
    local value = node('slot')
    value.Padding = {Left=1, Top=2, Right=3, Bottom=4}
    value.HorizontalAlignment, value.VerticalAlignment = 1, 2
    function value:SetPadding(padding) self.Padding=padding end
    function value:SetHorizontalAlignment(alignment) self.HorizontalAlignment=alignment end
    function value:SetVerticalAlignment(alignment) self.VerticalAlignment=alignment end
    return value
end
first.Slot, second.Slot = slot(), slot()
first.slot, second.slot = first.Slot, second.Slot
switcher:AddChild(first); switcher:AddChild(second)
switcher.active = 1
function switcher:GetActiveWidgetIndex() return self.active end
function switcher:SetActiveWidgetIndex(index) self.active=index end
local service = {}
function service:valid(value) return type(value)=='table' and value.name~=nil end
function service:same(a,b) return rawequal(a,b) end
function service:identity(value) return value.name end
function service:parent(value) return value.parent end
function service:findObject(path)
    assert(path == category.paths[1])
    return switcher
end
assert(category:resolveTarget(service) == switcher)
local plain = assert(category:attach(service, switcher, {}, nil, {}))
assert(not plain.moved and switcher:GetChildrenCount() == 2)
local shared = assert(category:attach(service, switcher, {}, plain,
    {detachSecondaryWheel=true}))
assert(shared.primary == second and shared.secondary == first and shared.moved)
assert(switcher:GetChildrenCount() == 1 and owner.children[2] == first)
assert(category:attach(service, switcher, {}, shared, {detachSecondaryWheel=true}) == shared)
assert(category:attach(service, switcher, {settings={PrimaryWheel=1}}, shared,
    {detachSecondaryWheel=true}) == shared)
assert(shared.primary == first and shared.secondary == second
    and switcher:GetChildAt(0) == first and owner.children[2] == second)
assert(category:detach(service, shared))
assert(switcher:GetChildrenCount() == 2 and switcher:GetChildAt(1) == second
    and switcher.active == 1 and second.parent == switcher)
print('quickslots category: shared wheel references and restoration passed')
