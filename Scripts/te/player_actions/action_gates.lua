-- Reversible action-level gates for the game's native quickslot actions.
-- Owned gates are identified by their deterministic object path so reloads do
-- not append duplicates and foreign triggers remain untouched.
return function(e)
    local marker = assert(e.marker, 'gate marker required')
    local pending, first = {}, true
    local api = {}

    local function triggerList(action)
        local list = {}
        e.each(action.Triggers, function(_, trigger)
            trigger = e.unwrap and e.unwrap(trigger) or trigger
            if e.valid(trigger) then list[#list + 1] = trigger end
        end)
        return list
    end
    local function owned(trigger, action)
        return e.valid(trigger) and e.valid(action)
            and e.path(trigger) == e.path(action) .. ':' .. marker
    end
    local function hasOwned(action)
        for _, trigger in ipairs(triggerList(action)) do
            if owned(trigger, action) then return true end
        end
        return false
    end
    local function flush()
        local changed = {}
        for path, action in pairs(pending) do
            if e.valid(action) then changed[#changed + 1] = action else pending[path] = nil end
        end
        if #changed > 0 then
            assert(e.rebuild(changed) ~= false, 'native action gate rebuild rejected')
            for _, action in ipairs(changed) do pending[e.path(action)] = nil end
        end
        first = false
        return #changed
    end
    local function update(action, wanted, inactiveAction)
        local before, after, gate = triggerList(action), {}, nil
        local changed = false
        for _, trigger in ipairs(before) do
            if owned(trigger, action) then
                if wanted and not gate then gate = trigger; after[#after + 1] = trigger
                else changed = true end
            else after[#after + 1] = trigger end
        end
        if wanted and not gate then
            gate = e.construct(action, marker)
            assert(e.valid(gate), 'native action gate construction failed for ' .. e.path(action))
            after[#after + 1], changed = gate, true
        end
        if gate and not e.same(e.chord(gate), inactiveAction) then
            e.setChord(gate, inactiveAction); changed = true
        end
        if changed then e.setTriggers(action, after) end
        return changed
    end
    function api:update(wanted)
        assert(type(wanted) == 'function', 'native gate selector required')
        local actions, needInactive = e.actions(), false
        for _, action in ipairs(actions) do if e.valid(action) and wanted(action) then needInactive = true; break end end
        local inactive = needInactive and e.retainInactive() or nil
        if needInactive then assert(e.valid(inactive), 'inactive native-action gate is unavailable') end
        local changed = {}
        for _, action in ipairs(actions) do
            if e.valid(action) then
                local altered = update(action, wanted(action), inactive)
                if altered then changed[#changed + 1] = action end
                if altered or (first and (wanted(action) or hasOwned(action))) then pending[e.path(action)] = action end
            end
        end
        flush()
        return true, #changed
    end
    function api:restoreAll()
        local changed = {}
        for _, action in ipairs(e.actions()) do
            if e.valid(action) then
                local hadGate = hasOwned(action)
                if update(action, false, nil) then changed[#changed + 1] = action end
                if hadGate then pending[e.path(action)] = action end
            end
        end
        flush()
        return true, #changed
    end
    return api
end
