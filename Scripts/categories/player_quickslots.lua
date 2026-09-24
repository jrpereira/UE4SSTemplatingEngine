local Widget = require('ket.widget')

local category = {
    name = "player.quickslots",
    single = true,
    events = { "GroupSelected", "SlotActivated" },

    paths = {
        switcher = "WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher",
    },

    contexts = { "combat", "openworld" },

    actions = {
           { type = "Ability", slot = "Left" },
           { type = "Ability", slot = "Top" },
           { type = "Ability", slot = "Right" },
           { type = "Ability", slot = "Bottom" },

           { type = "Consumable", slot = "Left" },
           { type = "Consumable", slot = "Top" },
           { type = "Consumable", slot = "Right" },
           { type = "Consumable", slot = "Bottom" },
       },

    settings = {
        groups = {{ id = "Shared", label = "Shared", level = 4, heading = false }},
        fields = {
            { id = "AccessMode", type = "picker", label = "Input Keys", description = "Choose between more keys vs more combinations",
              values = { 0, 1, 2 }, labels = { "Grouped", "Individual", "Advanced" }, default = 0,
              tab = true, level = 4, order = 2 },

            { id = "Advanced", type = "text", format = "quickslot_layout",
              default = "0|20,40,1.0,1.0|40,-420,0.8,0.7", order = -1 }

       }
    }
}

function category:resolveTarget(service)
    if type(service.findObject) ~= 'function' then return nil end
    local switcher = service:findObject(self.paths.switcher)
    if not service:valid(switcher) or type(switcher.GetChildrenCount) ~= 'function'
        or switcher:GetChildrenCount() < 2 then return nil end
    return switcher
end

local function restore(service, record)
    if not record.moved then return true end
    if not service:valid(record.switcher) then return true end
    assert(service:valid(record.owner), 'quickslots wheel owner unavailable')
    for _, wheel in ipairs(record.order) do
        assert(service:valid(wheel), 'native quickslot wheel unavailable')
        local parent = service:parent(wheel)
        if parent then
            assert(service:same(parent, record.owner) or service:same(parent, record.switcher),
                'quickslot wheel moved by another owner')
            assert(parent:RemoveChild(wheel) ~= false, 'could not detach wheel for restoration')
        end
    end
    for index, wheel in ipairs(record.order) do
        assert(service:valid(record.switcher:AddChild(wheel)),
            'could not restore native wheel to switcher')
        Widget.restoreSlot(wheel, record.slots[index])
    end
    record.switcher:SetActiveWidgetIndex(record.activeIndex)
    record.moved = false
    return true
end

function category:attach(service, switcher, settings, previous, template)
    assert(service:valid(switcher), 'quickslots switcher unavailable')
    if previous and not service:same(previous.switcher, switcher) then
        restore(service, previous)
        previous = nil
    end
    local record = previous or {switcher = switcher}
    if not service:valid(record.hud) then
        local node = switcher
        for _ = 1, 20 do
            if not service:valid(node) then break end
            if service:identity(node):match('^(%S+)') == 'WBP_GameHUD_C' then
                record.hud = node
                break
            end
            node = service:parent(node)
        end
    end
    if (not record.ability or not record.consumable)
        and type(switcher.GetChildrenCount) == 'function' then
        for index = 0, switcher:GetChildrenCount() - 1 do
            local wheel = switcher:GetChildAt(index)
            local class = service:valid(wheel) and service:identity(wheel):match('^(%S+)')
            if class == 'WBP_AA_Quickslots_C' then record.ability = wheel end
            if class == 'WBP_HUD_Quickslots_C' then record.consumable = wheel end
        end
    end
    if template.detachSecondaryWheel ~= true then
        restore(service, record)
        return record
    end
    local requested = settings.PrimaryWheel or 0
    assert(requested == 0 or requested == 1, 'invalid primary quickslot wheel')
    if record.moved and record.primaryWheel == requested then return record end
    restore(service, record)
    assert(switcher:GetChildrenCount() == 2, 'quickslots switcher must have two wheels')
    local ability, consumable = record.ability, record.consumable
    assert(service:valid(ability) and service:valid(consumable),
        'native Ability or Consumable wheel unavailable')
    local primary = requested == 1 and ability or consumable
    local secondary = requested == 1 and consumable or ability
    local owner = service:parent(switcher)
    assert(service:valid(primary) and service:valid(secondary) and service:valid(owner),
        'native quickslot wheels or owner unavailable')
    local order = {switcher:GetChildAt(0), switcher:GetChildAt(1)}
    assert((service:same(order[1], ability) and service:same(order[2], consumable))
        or (service:same(order[1], consumable) and service:same(order[2], ability)),
        'native quickslot wheel order changed')
    local slots = {Widget.snapshotSlot(order[1]), Widget.snapshotSlot(order[2])}
    local activeIndex = switcher:GetActiveWidgetIndex()
    assert(switcher:RemoveChild(secondary) ~= false, 'could not detach secondary wheel')
    local added, result = pcall(function() return owner:AddChild(secondary) end)
    if not added or not service:valid(result) then
        local restored, why = pcall(restore, service, {
            moved=true, switcher=switcher, owner=owner, order=order,
            slots=slots, activeIndex=activeIndex,
        })
        local failure = added and 'could not attach secondary wheel to owner' or tostring(result)
        if not restored then failure = failure .. '; restoration failed: ' .. tostring(why) end
        error(failure)
    end
    record.primary, record.secondary, record.owner = primary, secondary, owner
    record.order, record.slots = order, slots
    record.activeIndex, record.primaryWheel, record.moved = activeIndex, requested, true
    return record
end

function category:detach(service, record)
    return restore(service, record)
end

return category
